const admin = require('firebase-admin');
const fs = require('fs');
const crypto = require('crypto');

const serviceAccountPath = 'autiease-fyp-2026-firebase-adminsdk-fbsvc-f6075fecb2.json';
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'autiease-fyp-2026'
  });
}

const db = admin.firestore();

function normalizeValue(value) {
  if (value == null) {
    return '';
  }
  if (Array.isArray(value)) {
    return value.length > 0 ? normalizeValue(value[0]) : '';
  }
  return value.toString().trim();
}

function normalizeProviderPayload(rawPayload) {
  const payload = rawPayload || {};
  const basketId =
    payload.BASKET_ID ||
    payload.basket_id ||
    payload.order_id ||
    payload.ORDER_ID ||
    payload.merchant_basket_id ||
    '';
  const responseCode =
    payload.RESPONSE_CODE ||
    payload.response_code ||
    payload.ERR_CODE ||
    payload.err_code ||
    payload.ERROR_CODE ||
    payload.error_code ||
    payload.RespCode ||
    payload.respCode ||
    payload.code ||
    '';

  return {
    basketId: normalizeValue(basketId),
    responseCode: normalizeValue(responseCode),
    raw: payload,
  };
}

const payfastConfig = {
  merchantId: '103',
  securedKey: 'PzPx6ut-SVay7tCUMqG',
};

function verifyPayFastValidationHash(normalizedPayload) {
  const payload = normalizedPayload.raw || {};
  const providedHash = normalizeValue(
    payload.VALIDATION_HASH ||
      payload.validation_hash ||
      payload.HASH ||
      payload.hash ||
      payload.SECURE_HASH ||
      payload.secure_hash,
  ).toLowerCase();
  const errorCode = normalizeValue(
    payload.ERR_CODE ||
      payload.err_code ||
      payload.ERROR_CODE ||
      payload.error_code ||
      payload.RESPONSE_CODE ||
      payload.response_code ||
      normalizedPayload.responseCode,
  );

  if (!providedHash) {
    return { verified: false, reason: 'Missing validation hash in webhook payload', errorCode };
  }

  const hashInput = `${normalizedPayload.basketId}|${payfastConfig.securedKey}|${payfastConfig.merchantId}|${errorCode}`;
  const computedHash = crypto.createHash('sha256').update(hashInput, 'utf8').digest('hex').toLowerCase();
  const verified = computedHash === providedHash;

  return {
    verified,
    errorCode,
    providedHash,
    computedHash,
    hashInput,
  };
}

async function main() {
  const eventsSnap = await db.collection('payment_events')
    .orderBy('processedAt', 'desc')
    .limit(1)
    .get();

  if (eventsSnap.empty) {
    console.log('No events found.');
    return;
  }

  const event = eventsSnap.docs[0].data();
  console.log('Last Event ID:', eventsSnap.docs[0].id);
  console.log('Raw Payload Basket ID:', event.payload.basket_id);
  console.log('Raw Payload Validation Hash:', event.payload.validation_hash);

  const normalized = normalizeProviderPayload(event.payload);
  console.log('Normalized Basket ID:', normalized.basketId);

  const result = verifyPayFastValidationHash(normalized);
  console.log('Hash Input used:', result.hashInput);
  console.log('Computed Hash: ', result.computedHash);
  console.log('Provided Hash: ', result.providedHash);
  console.log('Verified:      ', result.verified);
}

main().catch(console.error);
