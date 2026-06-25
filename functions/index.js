const admin = require('firebase-admin');
const { onCall, HttpsError, onRequest } = require('firebase-functions/v2/https');
const { onDocumentDeleted, onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onUserDeleted } = require('firebase-functions/v2/identity');

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
