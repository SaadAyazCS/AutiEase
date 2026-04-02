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

function getScope(args) {
  const raw = (args.scope || 'all').toString().trim().toLowerCase();
  if (raw === 'daily' || raw === 'weekly' || raw === 'all') {
    return raw;
  }
  throw new Error('Invalid --scope. Use daily, weekly, or all.');
}

function cutoffForScope(scope) {
  const now = new Date();
  if (scope === 'daily') {
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }
  if (scope === 'weekly') {
    return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  }
  return null;
}

function toDateOrNull(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate();
  }
  return null;
}

async function clearCollectionForChild(collection, childId, cutoff, timeField) {
  const snapshot = await db.collection(collection).where('childId', '==', childId).get();
  let deleted = 0;
  for (const doc of snapshot.docs) {
    if (cutoff) {
      const value = toDateOrNull(doc.data()?.[timeField]);
      if (!value || value < cutoff) {
        continue;
      }
    }
    await doc.ref.delete();
    deleted += 1;
  }
  return { scanned: snapshot.size, deleted };
}

async function main() {
  const args = parseArgs(process.argv);
  const scope = getScope(args);
  const childId = await resolveChildId(args);
  if (!childId) {
    throw new Error(
      'Unable to resolve childId. Use --childId <id> or --parentEmail/--parentUid.',
    );
  }

  const cutoff = cutoffForScope(scope);
  const activity = await clearCollectionForChild(
    'activity_progress',
    childId,
    cutoff,
    'completedAt',
  );
  const moods = await clearCollectionForChild(
    'mood_logs',
    childId,
    cutoff,
    'createdAt',
  );

  console.log(
    JSON.stringify(
      {
        childId,
        scope,
        cutoff: cutoff ? cutoff.toISOString() : null,
        activityProgress: activity,
        moodLogs: moods,
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
