const admin = require('firebase-admin');

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT;

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

function isAuthUserNotFound(error) {
  return error?.code === 'auth/user-not-found';
}

function isFirestoreNotFound(error) {
  return error?.code === 5;
}

async function safeDeleteDocument(ref) {
  try {
    await ref.delete();
    return true;
  } catch (error) {
    if (isFirestoreNotFound(error)) {
      return false;
    }
    throw error;
  }
}

async function safeDeleteAuthUser(uid) {
  try {
    await admin.auth().deleteUser(uid);
    return true;
  } catch (error) {
    if (isAuthUserNotFound(error)) {
      return false;
    }
    throw error;
  }
}

async function deleteCollectionByField(collectionName, fieldName, value) {
  const snapshot = await db
    .collection(collectionName)
    .where(fieldName, '==', value)
    .get();
  for (const doc of snapshot.docs) {
    await doc.ref.delete();
  }
  return snapshot.size;
}

async function resolveUid({ uid, email }) {
  if (uid) {
    return uid;
  }

  const normalizedEmail = (email || '').toString().trim().toLowerCase();
  if (!normalizedEmail) {
    return null;
  }

  try {
    const authUser = await admin.auth().getUserByEmail(normalizedEmail);
    return authUser.uid;
  } catch (error) {
    if (!isAuthUserNotFound(error)) {
      throw error;
    }
  }

  const userSnapshot = await db
    .collection('users')
    .where('email', '==', normalizedEmail)
    .limit(1)
    .get();

  if (!userSnapshot.empty) {
    return userSnapshot.docs[0].id;
  }

  return null;
}

async function cleanupUser(uid) {
  const summary = {
    uid,
    authUserDeleted: false,
    usersDocDeleted: false,
    therapistProfileDeleted: false,
    childProfilesDeleted: 0,
    childAssignmentsDeleted: 0,
    dashboardSnapshotsDeleted: 0,
    moodLogsDeleted: 0,
    activityProgressDeleted: 0,
    therapistThreadsDeleted: 0,
    subscriptionsDeleted: 0,
    feedbackDeleted: 0,
  };

  summary.authUserDeleted = await safeDeleteAuthUser(uid);
  summary.therapistProfileDeleted = await safeDeleteDocument(
    db.collection('therapist_profiles').doc(uid),
  );

  const childSnapshot = await db
    .collection('child_profiles')
    .where('parentId', '==', uid)
    .get();
  const childIds = [];
  for (const childDoc of childSnapshot.docs) {
    childIds.push(childDoc.id);
    await childDoc.ref.delete();
  }
  summary.childProfilesDeleted = childIds.length;

  for (const childId of childIds) {
    const childAssignmentDeleted = await safeDeleteDocument(
      db.collection('child_assignments').doc(childId),
    );
    const dashboardSnapshotDeleted = await safeDeleteDocument(
      db.collection('dashboard_snapshots').doc(childId),
    );
    if (childAssignmentDeleted) {
      summary.childAssignmentsDeleted += 1;
    }
    if (dashboardSnapshotDeleted) {
      summary.dashboardSnapshotsDeleted += 1;
    }
    summary.moodLogsDeleted += await deleteCollectionByField(
      'mood_logs',
      'childId',
      childId,
    );
    summary.activityProgressDeleted += await deleteCollectionByField(
      'activity_progress',
      'childId',
      childId,
    );
  }

  const threadRefs = new Map();
  const parentThreads = await db
    .collection('therapist_threads')
    .where('parentId', '==', uid)
    .get();
  for (const doc of parentThreads.docs) {
    threadRefs.set(doc.ref.path, doc.ref);
  }
  const therapistThreads = await db
    .collection('therapist_threads')
    .where('therapistId', '==', uid)
    .get();
  for (const doc of therapistThreads.docs) {
    threadRefs.set(doc.ref.path, doc.ref);
  }
  for (const ref of threadRefs.values()) {
    await db.recursiveDelete(ref);
    summary.therapistThreadsDeleted += 1;
  }

  const subscriptions = await db
    .collection('subscriptions')
    .where('userId', '==', uid)
    .get();
  for (const doc of subscriptions.docs) {
    await doc.ref.delete();
  }
  summary.subscriptionsDeleted = subscriptions.size;

  summary.feedbackDeleted = await deleteCollectionByField('feedback', 'userId', uid);
  summary.usersDocDeleted = await safeDeleteDocument(db.collection('users').doc(uid));

  return summary;
}

async function main() {
  const args = parseArgs(process.argv);
  const targetUid = await resolveUid({
    uid: args.uid ? args.uid.toString().trim() : '',
    email: args.email ? args.email.toString().trim() : '',
  });

  if (!targetUid) {
    throw new Error(
      'Could not resolve target user. Pass --uid <uid> or --email <email> that exists in Auth/users.',
    );
  }

  const summary = await cleanupUser(targetUid);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
