const admin = require('firebase-admin');
const { onCall, HttpsError, onRequest } = require('firebase-functions/v2/https');
const { onDocumentDeleted, onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onUserDeleted } = require('firebase-functions/v2/identity');
const { onSchedule } = require('firebase-functions/v2/scheduler');

admin.initializeApp();

const db = admin.firestore();

function isAuthUserNotFound(error) {
  return error?.code === 'auth/user-not-found';
}

function isFirestoreNotFound(error) {
  return error?.code === 5;
}

async function safeDeleteDocument(ref) {
  try {
    await ref.delete();
  } catch (error) {
    if (!isFirestoreNotFound(error)) {
      throw error;
    }
  }
}

async function safeDeleteAuthUser(uid) {
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (!isAuthUserNotFound(error)) {
      throw error;
    }
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
}

async function cleanupUserBackendsByUid(
  uid,
  { deleteAuth = true, deleteUserDocument = false } = {},
) {
  if (deleteAuth) {
    await safeDeleteAuthUser(uid);
  }

  if (deleteUserDocument) {
    await safeDeleteDocument(db.collection('users').doc(uid));
  }

  await safeDeleteDocument(db.collection('therapist_profiles').doc(uid));

  const childSnapshot = await db
    .collection('child_profiles')
    .where('parentId', '==', uid)
    .get();
  const childIds = [];
  for (const childDoc of childSnapshot.docs) {
    childIds.push(childDoc.id);
    await childDoc.ref.delete();
  }

  for (const childId of childIds) {
    await safeDeleteDocument(db.collection('child_assignments').doc(childId));
    await safeDeleteDocument(db.collection('dashboard_snapshots').doc(childId));
    await deleteCollectionByField('mood_logs', 'childId', childId);
    await deleteCollectionByField('activity_progress', 'childId', childId);
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
  }

  const subscriptions = await db
    .collection('subscriptions')
    .where('userId', '==', uid)
    .get();
  for (const doc of subscriptions.docs) {
    await doc.ref.delete();
  }

  await deleteCollectionByField('feedback', 'userId', uid);
}



exports.cleanupDeletedUserDocument = onDocumentDeleted(
  'users/{uid}',
  async (event) => {
    const uid = event.params.uid;
    if (!uid) {
      return;
    }

    const deletedData = event.data?.data() || {};
    const role = deletedData.role || 'parent';

    // For admin accounts, only delete the Auth user — no therapy/child data to clean up
    if (role === 'admin') {
      await safeDeleteAuthUser(uid);
      return;
    }

    await cleanupUserBackendsByUid(uid, {
      deleteAuth: true,
      deleteUserDocument: false,
    });
  },
);

exports.cleanupDeletedAuthUser = onUserDeleted(async (event) => {
  const uid = event.data?.uid;
  if (!uid) {
    return;
  }

  // Primary path: remove users/{uid} and let cleanupDeletedUserDocument handle
  // the cascade. Fallback path: if users/{uid} does not exist, cleanup directly.
  const userRef = db.collection('users').doc(uid);
  const userSnapshot = await userRef.get();
  if (userSnapshot.exists) {
    await safeDeleteDocument(userRef);
    return;
  }

  await cleanupUserBackendsByUid(uid, {
    deleteAuth: false,
    deleteUserDocument: false,
  });
});

exports.checkAccountExistsByEmail = onCall(async (request) => {
  const email = (request.data?.email || '').toString().trim().toLowerCase();
  if (!email) {
    throw new HttpsError('invalid-argument', 'Email is required');
  }

  // Prefer Auth as source of truth, then fall back to profile presence.
  let existsInAuth = false;
  try {
    await admin.auth().getUserByEmail(email);
    existsInAuth = true;
  } catch (error) {
    if (!isAuthUserNotFound(error)) {
      throw new HttpsError('internal', 'Unable to verify account existence');
    }
  }

  const userDocSnapshot = await db
    .collection('users')
    .where('email', '==', email)
    .limit(1)
    .get();
  const existsInUsers = !userDocSnapshot.empty;

  return {
    exists: existsInAuth || existsInUsers,
  };
});

exports.sendPushNotificationOnNewNotification = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const data = event.data.data();
    if (!data) return;

    const userId = data.userId;
    const title = data.title || 'AutiEase';
    const message = data.message || '';
    const route = data.navigationTarget?.route || '';

    if (!userId) return;

    try {
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      const tokens = userDoc.data()?.fcmTokens || [];
      if (tokens.length === 0) {
        console.log(`No FCM tokens found for user: ${userId}`);
        return;
      }

      const payload = {
        notification: {
          title: title,
          body: message,
        },
        data: {
          route: route,
        },
      };

      // Send to all registered devices for this user
      const messages = tokens.map((token) => ({
        token: token,
        ...payload,
      }));

      const response = await admin.messaging().sendEach(messages);
      console.log(`Successfully sent ${response.successCount} push notifications; failed ${response.failureCount} for user ${userId}.`);

      // Remove stale/unregistered tokens to keep the token list clean
      const staleTokens = [];
      response.responses.forEach((resp, index) => {
        if (!resp.success) {
          const errorCode = resp.error?.code || '';
          if (
            errorCode === 'messaging/registration-token-not-registered' ||
            errorCode === 'messaging/invalid-registration-token' ||
            errorCode === 'messaging/invalid-argument'
          ) {
            staleTokens.push(tokens[index]);
          }
        }
      });

      if (staleTokens.length > 0) {
        console.log(`Removing ${staleTokens.length} stale FCM token(s) for user ${userId}.`);
        await db.collection('users').doc(userId).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
        });
      }
    } catch (error) {
      console.error('Error sending push notification:', error);
    }
  }
);

async function updateTherapistRating(therapistId) {
  if (!therapistId) return;

  const reviewsSnapshot = await db
    .collection('therapist_reviews')
    .where('therapistId', '==', therapistId)
    .get();

  let totalReviews = 0;
  let totalRating = 0;
  const ratingBreakdown = { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 };

  reviewsSnapshot.forEach((doc) => {
    const data = doc.data();
    const rating = Math.round(Number(data.rating) || 5);
    if (rating >= 1 && rating <= 5) {
      ratingBreakdown[rating.toString()] += 1;
      totalRating += rating;
      totalReviews += 1;
    }
  });

  const averageRating = totalReviews > 0 ? parseFloat((totalRating / totalReviews).toFixed(2)) : 0;

  await db.collection('therapist_profiles').doc(therapistId).set({
    rating: averageRating,
    totalReviews,
    ratingBreakdown,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.onReviewCreated = onDocumentCreated(
  'therapist_reviews/{reviewId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const therapistId = data.therapistId;
    await updateTherapistRating(therapistId);
  }
);

exports.onReviewUpdated = onDocumentUpdated(
  'therapist_reviews/{reviewId}',
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return;
    const therapistId = data.therapistId;
    await updateTherapistRating(therapistId);
  }
);

exports.onReviewDeleted = onDocumentDeleted(
  'therapist_reviews/{reviewId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const therapistId = data.therapistId;
    await updateTherapistRating(therapistId);
  }
);

// ─── Moderation: Disable / Enable Firebase Auth Account ──────────────────────

/**
 * Disables a Firebase Auth user account (suspend / ban).
 * Also revokes all refresh tokens so the user is immediately signed out
 * from all devices.
 *
 * Must be called by an authenticated admin user.
 */
exports.disableUserAccount = onCall(async (request) => {
  // Verify the caller is authenticated
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Caller must be authenticated.');
  }

  // Verify the caller is an admin
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection('users').doc(callerUid).get();
  if (!callerDoc.exists || callerDoc.data().role !== 'admin') {
    throw new HttpsError('permission-denied', 'Only admins may disable user accounts.');
  }

  const { uid } = request.data;
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'uid must be a non-empty string.');
  }

  try {
    // Disable the Auth account (prevents new sign-ins)
    await admin.auth().updateUser(uid, { disabled: true });
    // Revoke all existing refresh tokens (forces immediate sign-out)
    await admin.auth().revokeRefreshTokens(uid);
    console.log(`disableUserAccount: disabled and revoked tokens for uid=${uid}`);
  } catch (error) {
    console.error(`disableUserAccount: failed for uid=${uid}:`, error);
    throw new HttpsError('internal', `Failed to disable account: ${error.message}`);
  }
});

/**
 * Re-enables a Firebase Auth user account (unsuspend / restore).
 * Must be called by an authenticated admin user.
 */
exports.enableUserAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Caller must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const callerDoc = await db.collection('users').doc(callerUid).get();
  if (!callerDoc.exists || callerDoc.data().role !== 'admin') {
    throw new HttpsError('permission-denied', 'Only admins may enable user accounts.');
  }

  const { uid } = request.data;
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'uid must be a non-empty string.');
  }

  try {
    await admin.auth().updateUser(uid, { disabled: false });
    console.log(`enableUserAccount: re-enabled uid=${uid}`);
  } catch (error) {
    console.error(`enableUserAccount: failed for uid=${uid}:`, error);
    throw new HttpsError('internal', `Failed to enable account: ${error.message}`);
  }
});

// ─── Moderation: Auto-Expire Restrictions ────────────────────────────────────

/**
 * Runs every hour. Finds all restriction records whose endDate has passed
 * and status is still 'active', marks them as 'expired', and clears the
 * hasActiveRestrictions flag from affected users if they have no remaining
 * active restrictions.
 */
exports.autoExpireRestrictions = onSchedule('every 60 minutes', async () => {
  const now = admin.firestore.Timestamp.now();
  const snapshot = await db
    .collection('restrictions')
    .where('status', '==', 'active')
    .where('endDate', '<=', now)
    .get();

  if (snapshot.empty) {
    console.log('autoExpireRestrictions: no expired restrictions found.');
    return;
  }

  console.log(`autoExpireRestrictions: expiring ${snapshot.size} restriction(s).`);

  // Collect all affected user IDs (parentId + therapistId for each expired record)
  const affectedUserIds = new Set();

  const batch = db.batch();
  for (const doc of snapshot.docs) {
    batch.update(doc.ref, { status: 'expired', expiredAt: now });
    const data = doc.data();
    if (data.parentId) affectedUserIds.add(data.parentId);
    if (data.therapistId) affectedUserIds.add(data.therapistId);
  }
  await batch.commit();

  // For each affected user, check if they have any remaining active restrictions.
  // If not, clear the hasActiveRestrictions flag.
  for (const uid of affectedUserIds) {
    const remainingSnap = await db
      .collection('restrictions')
      .where('status', '==', 'active')
      .where('endDate', '>', now)
      .get();

    // Filter for this specific user client-side (Firestore doesn't support OR queries on different fields)
    const stillRestricted = remainingSnap.docs.some(
      (d) => d.data().parentId === uid || d.data().therapistId === uid
    );

    if (!stillRestricted) {
      const userRef = db.collection('users').doc(uid);
      const userDoc = await userRef.get();
      if (userDoc.exists) {
        const role = userDoc.data()?.role;
        await userRef.update({ hasActiveRestrictions: false, updatedAt: now });

        // Also update therapist_profiles if therapist
        if (role === 'therapist') {
          const therapistRef = db.collection('therapist_profiles').doc(uid);
          const therapistDoc = await therapistRef.get();
          if (therapistDoc.exists) {
            await therapistRef.update({ hasActiveRestrictions: false, updatedAt: now });
          }
        }

        // Send a notification to the user that the restriction has lifted
        await db.collection('notifications').add({
          userId: uid,
          title: '✅ Communication Restriction Lifted',
          message:
            'Your temporary communication restriction has expired. ' +
            'You may now communicate normally with the other party.',
          category: 'moderation',
          isRead: false,
          timestamp: now,
        });

        console.log(`autoExpireRestrictions: cleared hasActiveRestrictions for uid=${uid}`);
      }
    }
  }
});


exports.createSecondaryAdmin = onCall(async (request) => {
  // Verify caller is the primary admin
  const callerEmail = request.auth?.token?.email || '';
  if (callerEmail !== 'admin@autiease.com') {
    throw new HttpsError('permission-denied', 'Only the primary admin can create secondary admins.');
  }

  const { name, email, password } = request.data || {};
  if (!name || !email || !password) {
    throw new HttpsError('invalid-argument', 'name, email, and password are required.');
  }
  if (password.length < 8) {
    throw new HttpsError('invalid-argument', 'Password must be at least 8 characters.');
  }

  // Check if email is already registered
  try {
    await admin.auth().getUserByEmail(email);
    throw new HttpsError('already-exists', 'An account with this email already exists.');
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }

  // Create the Auth account
  const userRecord = await admin.auth().createUser({
    displayName: name,
    email,
    password,
  });

  return { uid: userRecord.uid };
});
