const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccountPath = 'autiease-fyp-2026-firebase-adminsdk-fbsvc-f6075fecb2.json';
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'autiease-fyp-2026'
});

const db = admin.firestore();

async function main() {
  const subRef = db.collection('subscriptions').doc('95ADutdQPHNiEpTrwB91Qj09aLE2_Lz0vBurjD6OyHhzk4rJottHPB2u2');
  const doc = await subRef.get();
  if (doc.exists) {
    console.log(JSON.stringify(doc.data(), null, 2));
  } else {
    console.log('Subscription not found.');
  }
}

main().catch(console.error);
