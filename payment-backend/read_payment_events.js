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
  const eventsSnap = await db.collection('payment_events')
    .orderBy('processedAt', 'desc')
    .limit(5)
    .get();
  if (eventsSnap.empty) {
    console.log('No payment events found.');
  } else {
    eventsSnap.forEach(doc => {
      console.log(`EVENT ID: ${doc.id}`);
      console.log(JSON.stringify(doc.data(), null, 2));
    });
  }
}

main().catch(console.error);
