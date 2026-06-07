const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccountPath = 'autiease-fyp-2026-firebase-adminsdk-fbsvc-f6075fecb2.json';
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'autiease-fyp-2026'
  });
}

const db = admin.firestore();

async function main() {
  const userId = '95ADutdQPHNiEpTrwB91Qj09aLE2';
  const subsSnap = await db.collection('subscriptions')
    .where('userId', '==', userId)
    .get();

  console.log(`Found ${subsSnap.size} subscriptions for user ${userId}:`);
  subsSnap.forEach(doc => {
    console.log(`ID: ${doc.id}`);
    console.log(JSON.stringify(doc.data(), null, 2));
  });

  console.log('\n--- LATEST CHECKOUT SESSIONS ---');
  const checkoutsSnap = await db.collection('checkout_sessions')
    .where('userId', '==', userId)
    .orderBy('createdAt', 'desc')
    .limit(3)
    .get();
  checkoutsSnap.forEach(doc => {
    console.log(`ID: ${doc.id}`);
    console.log(JSON.stringify(doc.data(), null, 2));
  });
}

main().catch(console.error);
