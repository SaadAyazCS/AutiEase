const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function readSeedFile() {
  const seedPath = path.join(__dirname, '..', 'seed', 'firestore.seed.json');
  const raw = fs.readFileSync(seedPath, 'utf8');
  return JSON.parse(raw);
}

function toFirestoreValue(value) {
  if (value === null) {
    return { nullValue: null };
  }

  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map(toFirestoreValue),
      },
    };
  }

  switch (typeof value) {
    case 'string':
      return { stringValue: value };
    case 'boolean':
      return { booleanValue: value };
    case 'number':
      return Number.isInteger(value)
        ? { integerValue: String(value) }
        : { doubleValue: value };
    case 'object':
      return {
        mapValue: {
          fields: Object.fromEntries(
            Object.entries(value).map(([key, nestedValue]) => [
              key,
              toFirestoreValue(nestedValue),
            ]),
          ),
        },
      };
    default:
      throw new Error(`Unsupported Firestore seed value type: ${typeof value}`);
  }
}

function getFirebaseCliAccessToken() {
  const candidates = [
    path.join(process.env.USERPROFILE || '', '.config', 'configstore', 'firebase-tools.json'),
    path.join(process.env.APPDATA || '', 'configstore', 'firebase-tools.json'),
  ];

  for (const configPath of candidates) {
    if (!configPath || !fs.existsSync(configPath)) {
      continue;
    }

    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const accessToken = config?.tokens?.access_token;
    if (accessToken) {
      return accessToken;
    }
  }

  return null;
}

async function seedWithAdminSdk(seed) {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }

  const db = admin.firestore();

  for (const [collectionName, docs] of Object.entries(seed)) {
    for (const doc of docs) {
      const { id, ...data } = doc;
      if (!id) {
        throw new Error(`Missing id for collection ${collectionName}`);
      }
      await db.collection(collectionName).doc(id).set(data, { merge: true });
      console.log(`Seeded ${collectionName}/${id}`);
    }
  }
}

async function seedWithFirebaseCliToken(seed) {
  const projectId =
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT;

  if (!projectId) {
    throw new Error(
      'Missing Firebase project id. Set FIREBASE_PROJECT_ID when using Firebase CLI token fallback.',
    );
  }

  const accessToken = getFirebaseCliAccessToken();
  if (!accessToken) {
    throw new Error(
      'No Firebase CLI access token found. Run "firebase login" first or provide GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }

  for (const [collectionName, docs] of Object.entries(seed)) {
    for (const doc of docs) {
      const { id, ...data } = doc;
      if (!id) {
        throw new Error(`Missing id for collection ${collectionName}`);
      }

      const response = await fetch(
        `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collectionName}/${encodeURIComponent(
          id,
        )}`,
        {
          method: 'PATCH',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            fields: Object.fromEntries(
              Object.entries(data).map(([key, value]) => [key, toFirestoreValue(value)]),
            ),
          }),
        },
      );

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(
          `Failed ${collectionName}/${id}: ${response.status} ${errorText}`,
        );
      }

      console.log(`Seeded ${collectionName}/${id}`);
    }
  }
}

async function main() {
  const seed = readSeedFile();

  try {
    await seedWithAdminSdk(seed);
  } catch (error) {
    const canFallbackToCli =
      !process.env.GOOGLE_APPLICATION_CREDENTIALS &&
      !process.env.GOOGLE_CLOUD_PROJECT &&
      !process.env.GCLOUD_PROJECT &&
      !!process.env.FIREBASE_PROJECT_ID;

    if (!canFallbackToCli) {
      throw error;
    }

    console.warn(
      'Admin SDK seed failed, falling back to Firebase CLI token-based Firestore import.',
    );
    await seedWithFirebaseCliToken(seed);
  }

  console.log('Firestore seed import completed.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
