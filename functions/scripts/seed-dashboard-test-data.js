const admin = require('firebase-admin');

const fs = require('fs');
const path = require('path');

function readDefaultProjectId() {
  try {
    const rcPath = path.join(__dirname, '..', '..', '.firebaserc');
    if (!fs.existsSync(rcPath)) {
      return null;
    }
    const data = JSON.parse(fs.readFileSync(rcPath, 'utf8'));
    return data?.projects?.default || null;
  } catch (_) {
    return null;
  }
}

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  readDefaultProjectId();

if (admin.apps.length === 0) {
  if (projectId) {
    admin.initializeApp({ projectId });
  } else {
    admin.initializeApp();
  }
}

const db = admin.firestore();

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const part = argv[i];
    if (!part.startsWith('--')) {
      continue;
    }
    const key = part.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

async function resolveParentUid(args) {
  if (args.parentUid) {
    return args.parentUid.toString().trim();
  }
  if (args.parentEmail) {
    const normalized = args.parentEmail.toString().trim().toLowerCase();
    if (!normalized) {
      return null;
    }
    const byEmail = await db
      .collection('users')
      .where('email', '==', normalized)
      .limit(1)
      .get();
    if (!byEmail.empty) {
      return byEmail.docs[0].id;
    }
  }
  return null;
}

async function resolveChildId(args) {
  if (args.childId) {
    return args.childId.toString().trim();
  }

  const parentUid = await resolveParentUid(args);
  if (!parentUid) {
    return null;
  }

  const userDoc = await db.collection('users').doc(parentUid).get();
  const activeChildId = userDoc.data()?.activeChildId;
  if (activeChildId) {
    return activeChildId.toString();
  }

  const childSnapshot = await db
    .collection('child_profiles')
    .where('parentId', '==', parentUid)
    .limit(1)
    .get();
  if (!childSnapshot.empty) {
    return childSnapshot.docs[0].id;
  }
  return null;
}

function nowMinusDays(days, hours = 10) {
  const now = new Date();
  const value = new Date(now);
  value.setDate(now.getDate() - days);
  value.setHours(hours, 0, 0, 0);
  return admin.firestore.Timestamp.fromDate(value);
}

async function clearRecentForChild(childId) {
  const weeklyCutoff = nowMinusDays(10);
  const progressSnapshot = await db
    .collection('activity_progress')
    .where('childId', '==', childId)
    .get();
  let progressDeleted = 0;
  for (const doc of progressSnapshot.docs) {
    const completedAt = doc.data()?.completedAt;
    if (
      completedAt &&
      typeof completedAt.toMillis === 'function' &&
      completedAt.toMillis() < weeklyCutoff.toMillis()
    ) {
      continue;
    }
    await doc.ref.delete();
    progressDeleted += 1;
  }

  const moodsSnapshot = await db
    .collection('mood_logs')
    .where('childId', '==', childId)
    .get();
  let moodsDeleted = 0;
  for (const doc of moodsSnapshot.docs) {
    const createdAt = doc.data()?.createdAt;
    if (
      createdAt &&
      typeof createdAt.toMillis === 'function' &&
      createdAt.toMillis() < weeklyCutoff.toMillis()
    ) {
      continue;
    }
    await doc.ref.delete();
    moodsDeleted += 1;
  }

  return {
    activityDeleted: progressDeleted,
    moodsDeleted,
  };
}

async function seedActivityProgress(childId) {
  const assignmentDoc = await db.collection('child_assignments').doc(childId).get();
  const assignment = assignmentDoc.data() || {};
  const moduleIds = Array.isArray(assignment.assignedModuleIds)
    ? assignment.assignedModuleIds.map((v) => `${v}`.trim()).filter(Boolean)
    : [];

  const move = moduleIds.filter((id) => id.includes('move') || id.includes('tap') || id.includes('drag') || id.includes('trace'));
  const talk = moduleIds.filter((id) => id.includes('speak') || id.includes('word') || id.includes('sentence') || id.includes('alphabet'));
  const focus = moduleIds.filter((id) => id.includes('focus') || id.includes('find') || id.includes('match') || id.includes('hold'));

  const events = [];
  if (move.length > 0) {
    events.push({ itemId: move[0], moduleId: move[0], completedAt: nowMinusDays(1) });
  }
  if (talk.length > 1) {
    events.push({ itemId: talk[0], moduleId: talk[0], completedAt: nowMinusDays(2) });
  } else if (talk.length === 1) {
    events.push({ itemId: talk[0], moduleId: talk[0], completedAt: nowMinusDays(5) });
  }
  if (focus.length > 0) {
    // Keep focus older than 7 days so weekly and monthly differ.
    events.push({ itemId: focus[0], moduleId: focus[0], completedAt: nowMinusDays(9) });
  }

  const activityTemplateIds = Array.isArray(assignment.assignedActivityTemplateIds)
    ? assignment.assignedActivityTemplateIds.map((v) => `${v}`.trim()).filter(Boolean)
    : [];
  if (activityTemplateIds.length > 0) {
    events.push({
      itemId: activityTemplateIds[0],
      moduleId: activityTemplateIds[0],
      completedAt: nowMinusDays(0, 8),
    });
  }

  for (const event of events) {
    await db.collection('activity_progress').add({
      childId,
      itemId: event.itemId,
      moduleId: event.moduleId,
      status: 'completed',
      score: 1,
      attempts: 1,
      completedAt: event.completedAt,
    });
  }

  await db.collection('mood_logs').add({
    childId,
    emotion: 'Happy',
    note: 'Seeded dashboard mood for testing',
    source: 'seed-script',
    createdAt: nowMinusDays(0, 9),
  });

  return {
    insertedEvents: events.length,
    insertedMoodLogs: 1,
    modules: { move: move.length, talk: talk.length, focus: focus.length },
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const childId = await resolveChildId(args);
  if (!childId) {
    throw new Error(
      'Unable to resolve childId. Use --childId <id> or pass --parentEmail/--parentUid.',
    );
  }

  const cleared = await clearRecentForChild(childId);
  const seeded = await seedActivityProgress(childId);

  console.log(
    JSON.stringify(
      {
        childId,
        cleared,
        seeded,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
