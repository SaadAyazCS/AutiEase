// Load .env file manually if it exists to make running the server foolproof
try {
  const fs = require('fs');
  const path = require('path');
  const envPath = path.join(__dirname, '.env');
  if (fs.existsSync(envPath)) {
    const envContent = fs.readFileSync(envPath, 'utf8');
    envContent.split(/\r?\n/).forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const index = trimmed.indexOf('=');
      if (index === -1) return;
      const key = trimmed.substring(0, index).trim();
      let val = trimmed.substring(index + 1).trim();
      // Remove surrounding quotes if any
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      if (key && !process.env[key]) {
        process.env[key] = val;
      }
    });
  }
} catch (err) {
  console.warn('Failed to load .env file manually:', err.message);
}

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const cron = require('node-cron');

const app = express();

function isTruthy(value) {
  if (value == null) {
    return false;
  }
  const normalized = value.toString().trim().toLowerCase();
  return ['1', 'true', 'yes', 'on'].includes(normalized);
}

function normalizeValue(value) {
  if (value == null) {
    return '';
  }
  if (Array.isArray(value)) {
    return value.length > 0 ? normalizeValue(value[0]) : '';
  }
  return value.toString().trim();
}

function normalizeBaseUrl(url) {
  const value = normalizeValue(url);
  if (!value) {
    return '';
  }
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function parseAllowedOrigins() {
  const raw = normalizeValue(process.env.ALLOWED_ORIGINS);
  if (!raw) {
    return [];
  }
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function initFirebaseAdmin() {
  if (admin.apps.length > 0) {
    return;
  }

  const projectId =
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT;

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: projectId || serviceAccount.project_id,
    });
    return;
  }

  const gCredentials = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (gCredentials) {
    try {
      const fs = require('fs');
      const serviceAccount = JSON.parse(fs.readFileSync(gCredentials, 'utf8'));
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: projectId || serviceAccount.project_id,
      });
      console.log('Firebase Admin SDK initialized using GOOGLE_APPLICATION_CREDENTIALS file');
      return;
    } catch (err) {
      console.error('Failed to load GOOGLE_APPLICATION_CREDENTIALS file:', err.message);
    }
  }

  if (projectId) {
    admin.initializeApp({ projectId });
    return;
  }

  admin.initializeApp();
}

function jsonError(res, status, message) {
  res.status(status).json({ error: message });
}

function getBearerToken(req) {
  const authHeader = req.header('authorization') || req.header('Authorization');
  if (!authHeader) {
    return null;
  }
  const [scheme, token] = authHeader.split(' ');
  if (!scheme || !token || scheme.toLowerCase() !== 'bearer') {
    return null;
  }
  return token.trim();
}

async function requireAuth(req, res, next) {
  try {
    const token = getBearerToken(req);
    if (!token) {
      return jsonError(res, 401, 'Missing bearer token');
    }
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    return next();
  } catch (error) {
    const details = error?.message || error?.code || 'Unknown auth error';
    console.error('Auth verification failed:', details);
    if (process.env.NODE_ENV !== 'production') {
      return jsonError(res, 401, `Unauthorized: ${details}`);
    }
    return jsonError(res, 401, 'Unauthorized');
  }
}

function resolveCheckoutBaseUrl(req) {
  const explicit = normalizeBaseUrl(process.env.PAYMENT_REDIRECT_BASE_URL || process.env.BACKEND_PUBLIC_BASE_URL);
  if (explicit) {
    return explicit;
  }
  const proto = req.headers['x-forwarded-proto'] || req.protocol || 'https';
  const host = req.headers['x-forwarded-host'] || req.get('host');
  return `${proto}://${host}`;
}

function formatOrderDate(date = new Date()) {
  const pad = (value) => value.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(
    date.getHours(),
  )}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function parseAmount(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(0, value);
  }
  if (typeof value === 'string') {
    const cleaned = value.replace(/[^\d.]/g, '');
    if (!cleaned) {
      return 0;
    }
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
  }
  return 0;
}

function resolveProductAmount(product) {
  const candidates = [
    product.amount,
    product.price,
    product.amountPkr,
    product.unitAmount,
    product.priceLabel,
  ];
  for (const candidate of candidates) {
    const amount = parseAmount(candidate);
    if (amount > 0) {
      return amount;
    }
  }
  return 0;
}

function toAmountString(amount) {
  return amount.toFixed(2);
}

function buildBasketId(uid, productId) {
  const safeProductId = normalizeValue(productId).replace(/[^a-zA-Z0-9-]/g, '-').slice(0, 24);
  const timestamp = Date.now();
  return `ae-${uid.slice(0, 8)}-${safeProductId}-${timestamp}`;
}

function normalizeSubscriptionDocId(userId, therapistId) {
  return `${normalizeValue(userId)}_${normalizeValue(therapistId)}`;
}

function isSuccessStatus(statusValue, responseCodeValue) {
  const status = normalizeValue(statusValue).toLowerCase();
  const responseCode = normalizeValue(responseCodeValue).toLowerCase();
  const successStatuses = new Set(['success', 'successful', 'completed', 'paid', 'processed', 'active', '00', '000']);
  const successCodes = new Set(['00', '0', '000', 'success', 'successful']);
  return successStatuses.has(status) || successCodes.has(responseCode);
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
  const transactionId =
    payload.transaction_id ||
    payload.TRANSACTION_ID ||
    payload.pp_TxnRefNo ||
    payload.TxnRefNo ||
    payload.txn_ref_no ||
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
  const status =
    payload.TRANSACTION_STATUS ||
    payload.transaction_status ||
    payload.STATUS ||
    payload.status ||
    payload.txn_status ||
    payload.message ||
    '';

  return {
    basketId: normalizeValue(basketId),
    transactionId: normalizeValue(transactionId),
    responseCode: normalizeValue(responseCode),
    status: normalizeValue(status),
    raw: payload,
  };
}

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
  if (!normalizedPayload.basketId || !errorCode) {
    return { verified: false, reason: 'Missing basket id or error code for hash verification', errorCode };
  }

  const hashInput = `${normalizedPayload.basketId}|${payfastConfig.securedKey}|${payfastConfig.merchantId}|${errorCode}`;
  const computedHash = crypto.createHash('sha256').update(hashInput, 'utf8').digest('hex').toLowerCase();
  const verified = computedHash === providedHash;

  return {
    verified,
    reason: verified ? '' : 'Validation hash mismatch',
    errorCode,
    providedHash,
    computedHash,
  };
}

function escapeHtml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function buildAutoPostHtml(actionUrl, fields) {
  const escapedAction = escapeHtml(actionUrl);
  const inputs = Object.entries(fields)
    .filter(([, value]) => value != null)
    .map(([key, value]) => {
      const escapedKey = escapeHtml(key);
      const escapedValue = escapeHtml(value.toString());
      return `<input type="hidden" name="${escapedKey}" value="${escapedValue}" />`;
    })
    .join('\n');

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Redirecting to PayFast</title>
  </head>
  <body style="font-family: Arial, sans-serif; background:#f7fafc; color:#1f2937;">
    <div style="max-width:560px;margin:64px auto;padding:24px;background:white;border-radius:12px;box-shadow:0 2px 20px rgba(0,0,0,0.08);">
      <h2 style="margin-top:0;color:#1e3a8a;">Redirecting to secure checkout...</h2>
      <p style="line-height:1.45;color:#4b5563;">If you are not redirected automatically, click the button below.</p>
      <form id="payfast-checkout" method="post" action="${escapedAction}">
        ${inputs}
        <button type="submit" style="margin-top:12px;padding:12px 20px;border:0;border-radius:8px;background:#00c853;color:white;font-weight:bold;cursor:pointer;box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);">Continue to PayFast</button>
      </form>
    </div>
    <script>
      window.setTimeout(function () {
        var form = document.getElementById('payfast-checkout');
        if (form) form.submit();
      }, 50);
    </script>
  </body>
</html>`;
}

function buildStatusPageHtml(isSuccess, message) {
  const title = isSuccess ? 'Payment Successful' : 'Payment Failed';
  const color = isSuccess ? '#00c853' : '#dc2626';
  const bgLight = isSuccess ? '#edfdf2' : '#fef2f2';
  const icon = isSuccess 
    ? `<div style="width:72px;height:72px;border-radius:50%;background:#dcfce7;display:flex;align-items:center;justify-content:center;margin:0 auto 20px;"><svg width="36" height="36" fill="none" stroke="${color}" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg></div>`
    : `<div style="width:72px;height:72px;border-radius:50%;background:#fee2e2;display:flex;align-items:center;justify-content:center;margin:0 auto 20px;"><svg width="36" height="36" fill="none" stroke="${color}" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg></div>`;

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
      body {
        font-family: 'Inter', sans-serif;
        background: #f3f4f6;
        color: #1f2937;
        margin: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 100vh;
      }
      .card {
        max-width: 480px;
        width: 90%;
        background: white;
        padding: 32px;
        border-radius: 16px;
        box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1);
        text-align: center;
      }
      h2 {
        color: #111827;
        margin-top: 0;
        font-size: 24px;
        font-weight: 700;
      }
      p {
        color: #4b5563;
        font-size: 15px;
        line-height: 1.5;
        margin-bottom: 28px;
      }
      .btn {
        display: inline-block;
        padding: 12px 24px;
        background: #00c853;
        color: white;
        font-weight: 600;
        text-decoration: none;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0, 200, 83, 0.2);
        transition: transform 0.2s, box-shadow 0.2s;
      }
      .btn:hover {
        transform: translateY(-1px);
        box-shadow: 0 6px 16px rgba(0, 200, 83, 0.3);
      }
    </style>
  </head>
  <body>
    <div class="card">
      ${icon}
      <h2>${title}</h2>
      <p>${escapeHtml(message)}</p>
      <a
        class="btn"
        style="background: ${color}; box-shadow: 0 4px 12px ${color}33; text-decoration: none; display: inline-block; cursor: pointer; font-size: 1rem; color: white;"
        href="autiease://payment-result"
        onclick="setTimeout(function() { try { window.close(); } catch(e) {} }, 1000);"
      >Return to AutiEase</a>
    </div>
    <script>
      function returnToApp() {
        // Fire the custom scheme deep link to bring the app to foreground
        window.location.href = 'autiease://payment-result';
        // Attempt to close the browser tab after a short delay
        setTimeout(function() { try { window.close(); } catch(e) {} }, 800);
      }
      // Auto-trigger on page load after 1.5 seconds so user doesn't have to tap
      setTimeout(returnToApp, 1500);
    </script>
  </body>
</html>`;
}

const payfastConfig = {
  provider: normalizeValue(process.env.PAYMENT_PROVIDER) || 'payfast_pk',
  baseUrl: normalizeBaseUrl(
    process.env.PAYFAST_BASE_URL || 'https://ipguat.apps.net.pk/Ecommerce/api/Transaction',
  ),
  accessTokenPath: normalizeValue(process.env.PAYFAST_ACCESS_TOKEN_PATH) || '/GetAccessToken',
  postTransactionPath: normalizeValue(process.env.PAYFAST_POST_TRANSACTION_PATH) || '/PostTransaction',
  statusPath: normalizeValue(process.env.PAYFAST_STATUS_PATH) || '/Inquiry',
  merchantId: normalizeValue(process.env.PAYFAST_MERCHANT_ID) || '102',
  securedKey: normalizeValue(process.env.PAYFAST_SECURED_KEY) || 'zWHjBp2AlttNu1sK',
  merchantName: normalizeValue(process.env.PAYFAST_MERCHANT_NAME) || 'AutiEase',
  currencyCode: normalizeValue(process.env.PAYFAST_CURRENCY_CODE) || 'PKR',
  txDescription:
    normalizeValue(process.env.PAYFAST_TXN_DESC) || 'AutiEase Professional Support Monthly Subscription',
  version: normalizeValue(process.env.PAYFAST_VERSION) || 'MERCHANT-CART-0.1',
  procCode: normalizeValue(process.env.PAYFAST_PROCCODE) || '00',
  tranType: normalizeValue(process.env.PAYFAST_TRAN_TYPE) || 'ECOMM_PURCHASE',
  storeId: normalizeValue(process.env.PAYFAST_STORE_ID) || '',
  customerMobileDefault: normalizeValue(process.env.PAYFAST_CUSTOMER_MOBILE_DEFAULT) || '03001234567',
  checkoutUrlField: normalizeValue(process.env.PAYFAST_CHECKOUT_URL_FIELD),
  signatureStatic: normalizeValue(process.env.PAYFAST_SIGNATURE_STATIC) || 'testsign',
  strictWebhookVerification: isTruthy(process.env.PAYFAST_STRICT_WEBHOOK_VERIFICATION),
};

function ensurePayFastConfigured() {
  if (!payfastConfig.baseUrl || !payfastConfig.merchantId || !payfastConfig.securedKey) {
    throw new Error(
      'PayFast is not configured. Required: PAYFAST_BASE_URL, PAYFAST_MERCHANT_ID, PAYFAST_SECURED_KEY.',
    );
  }
}

function payFastUrl(path) {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${payfastConfig.baseUrl}${normalizedPath}`;
}

async function getPayFastAccessToken({ basketId, amount }) {
  ensurePayFastConfigured();
  const body = new URLSearchParams({
    MERCHANT_ID: payfastConfig.merchantId,
    SECURED_KEY: payfastConfig.securedKey,
    BASKET_ID: basketId,
    TXNAMT: toAmountString(amount),
    CURRENCY_CODE: payfastConfig.currencyCode,
  });

  const response = await fetch(payFastUrl(payfastConfig.accessTokenPath), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`PayFast access token request failed (${response.status}): ${text}`);
  }

  const payload = await response.json();
  const token = normalizeValue(payload.ACCESS_TOKEN || payload.access_token || payload.token);
  if (!token) {
    throw new Error('PayFast access token response did not include ACCESS_TOKEN.');
  }

  return token;
}

function addDays(date, days) {
  const result = new Date(date.getTime());
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

async function syncUserSubscriptionEntitlements(userId) {
  const activeSnapshot = await db
    .collection('subscriptions')
    .where('userId', '==', userId)
    .where('status', 'in', ['active', 'trialing'])
    .limit(1)
    .get();
  const active = !activeSnapshot.empty;

  await db.collection('users').doc(userId).set(
    {
      entitlements: {
        professionalSupport: active,
        chatAccess: active,
      },
      subscriptionTier: active ? 'professional-support' : 'free',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function updateTherapistThreadAccess(userId, therapistId, active) {
  const normalizedUserId = normalizeValue(userId);
  const normalizedTherapistId = normalizeValue(therapistId);
  if (!normalizedUserId || !normalizedTherapistId) {
    return;
  }
  const threadSnapshot = await db
    .collection('therapist_threads')
    .where('parentId', '==', normalizedUserId)
    .where('therapistId', '==', normalizedTherapistId)
    .get();

  if (threadSnapshot.empty) {
    return;
  }

  const batch = db.batch();
  for (const doc of threadSnapshot.docs) {
    batch.set(
      doc.ref,
      {
        status: active ? 'active' : 'locked',
        postCancelVisible: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
}

async function markPaymentEventProcessed(eventId, payload) {
  const ref = db.collection('payment_events').doc(eventId);
  try {
    await ref.create({
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      payload,
    });
    return true;
  } catch (error) {
    if (error?.code === 6 || error?.code === 'already-exists' || error?.message?.includes('ALREADY_EXISTS')) {
      return false;
    }
    throw error;
  }
}

async function findSubscriptionByBasketId(basketId) {
  const snapshot = await db
    .collection('subscriptions')
    .where('basketId', '==', basketId)
    .limit(1)
    .get();
  if (snapshot.empty) {
    return null;
  }
  return snapshot.docs[0];
}

async function verifyTransactionWithGateway(normalizedPayload, expectedAmount) {
  const transactionId = normalizedPayload.transactionId;
  const basketId = normalizedPayload.basketId;
  if (!transactionId && !basketId) {
    return { verified: false, reason: 'Missing transaction identifiers' };
  }

  try {
    const token = await getPayFastAccessToken({
      basketId: basketId || `verify_${Date.now()}`,
      amount: expectedAmount > 0 ? expectedAmount : 1,
    });

    const query = new URLSearchParams();
    if (transactionId) {
      query.set('transaction_id', transactionId);
    }
    if (basketId) {
      query.set('basket_id', basketId);
    }

    const statusUrl = `${payFastUrl(payfastConfig.statusPath)}${query.toString() ? `?${query.toString()}` : ''}`;
    const response = await fetch(statusUrl, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      const text = await response.text();
      return { verified: false, reason: `Status API failed (${response.status}): ${text}` };
    }

    const payload = await response.json();
    const status =
      payload.status ||
      payload.transaction_status ||
      payload.TRANSACTION_STATUS ||
      payload.message ||
      '';
    const responseCode = payload.code || payload.response_code || payload.RESPONSE_CODE || '';
    const verified = isSuccessStatus(status, responseCode);

    return {
      verified,
      status: normalizeValue(status),
      responseCode: normalizeValue(responseCode),
      payload,
      reason: verified ? '' : 'Gateway status did not indicate success',
    };
  } catch (error) {
    return { verified: false, reason: error?.message || String(error) };
  }
}

async function reconcileExpiredSubscriptions() {
  const now = admin.firestore.Timestamp.now();
  const snapshot = await db
    .collection('subscriptions')
    .where('status', 'in', ['active', 'trialing'])
    .where('currentPeriodEnd', '<=', now)
    .get();

  if (snapshot.empty) {
    return { expiredCount: 0 };
  }

  const updatedUserIds = new Set();
  const updatedPairs = [];
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const userId = normalizeValue(data.userId);
    const therapistId = normalizeValue(data.therapistId);
    if (!userId) {
      continue;
    }
    batch.set(
      doc.ref,
      {
        status: 'expired',
        isActive: false,
        cancelAtPeriodEnd: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    updatedUserIds.add(userId);
    if (therapistId) {
      updatedPairs.push({ userId, therapistId });
    }
  }

  await batch.commit();

  for (const pair of updatedPairs) {
    await updateTherapistThreadAccess(pair.userId, pair.therapistId, false);
  }
  for (const userId of updatedUserIds) {
    await syncUserSubscriptionEntitlements(userId);
  }

  return { expiredCount: snapshot.size };
}

initFirebaseAdmin();
const db = admin.firestore();
const allowedOrigins = parseAllowedOrigins();
const mockPaymentsEnabled = isTruthy(process.env.PAYMENTS_MOCK_MODE) || isTruthy(process.env.MOCK_PAYMENTS);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('Origin not allowed by CORS policy'));
    },
  }),
);

app.use(express.urlencoded({ extended: false }));
app.use(express.json());

app.get('/health', (_req, res) => {
  res.status(200).json({ ok: true, service: 'autiease-payment-backend', provider: payfastConfig.provider, mock: mockPaymentsEnabled });
});

app.get('/api/v1/checkout/redirect/:checkoutId', async (req, res) => {
  try {
    const checkoutId = normalizeValue(req.params.checkoutId);
    if (!checkoutId) {
      return jsonError(res, 400, 'Missing checkout id');
    }
    const checkoutDoc = await db.collection('checkout_sessions').doc(checkoutId).get();
    if (!checkoutDoc.exists) {
      return jsonError(res, 404, 'Checkout session not found');
    }

    const checkoutData = checkoutDoc.data() || {};
    if (checkoutData.status !== 'pending') {
      return jsonError(res, 400, 'Checkout session is no longer pending');
    }

    const html = buildAutoPostHtml(payFastUrl(payfastConfig.postTransactionPath), checkoutData.formFields || {});
    res.status(200).set('Content-Type', 'text/html; charset=utf-8').send(html);
  } catch (error) {
    console.error('Checkout redirect failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to initialize checkout');
  }
});

app.post('/api/v1/checkout/session', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { therapistId, productId, successUrl, cancelUrl } = req.body || {};

    if (!therapistId || !productId || !successUrl || !cancelUrl) {
      return jsonError(res, 400, 'Missing checkout parameters');
    }
    const normalizedTherapistId = normalizeValue(therapistId);
    const normalizedProductId = normalizeValue(productId);
    if (!normalizedTherapistId || !normalizedProductId) {
      return jsonError(res, 400, 'Invalid checkout parameters');
    }

    const therapistSnapshot = await db.collection('therapist_profiles').doc(normalizedTherapistId).get();
    if (!therapistSnapshot.exists) {
      return jsonError(res, 404, 'Therapist profile not found');
    }
    const therapist = therapistSnapshot.data() || {};

    let productSnapshot = await db.collection('subscription_products').doc(normalizedProductId).get();
    let product;
    if (!productSnapshot.exists) {
      const packages = Array.isArray(therapist.servicePackages) ? therapist.servicePackages : [];
      const visiblePackages = packages.filter((p) => p && p.visible !== false);

      // Resolve package index from auto-provisioned productId (e.g. auto_<therapistId>_<packageIndex>)
      let pkgIndex = 0;
      if (normalizedProductId.startsWith('auto_')) {
        const parts = normalizedProductId.split('_');
        if (parts.length >= 3) {
          const parsedIndex = parseInt(parts[parts.length - 1], 10);
          if (!isNaN(parsedIndex)) {
            pkgIndex = parsedIndex;
          }
        }
      }

      const visiblePkg = visiblePackages[pkgIndex] || visiblePackages[0];
      if (!visiblePkg) {
        return jsonError(res, 404, 'Subscription product not found and therapist has no visible service packages');
      }
      const pkgPrice = parseAmount(visiblePkg.price);
      if (pkgPrice <= 0) {
        return jsonError(res, 400, 'Therapist service package has no valid price');
      }
      product = {
        title: normalizeValue(visiblePkg.title) || 'Therapy Package',
        amount: pkgPrice,
        currency: 'PKR',
        interval: 'month',
        isActive: true,
        therapistId: normalizedTherapistId,
        autoProvisioned: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      await db.collection('subscription_products').doc(normalizedProductId).set(product);
      // Link the product back to the therapist profile only if not auto-provisioned
      if (!normalizedProductId.startsWith('auto_')) {
        await db.collection('therapist_profiles').doc(normalizedTherapistId).set(
          { subscriptionProductId: normalizedProductId, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
      console.log(`Auto-provisioned subscription product ${normalizedProductId} for therapist ${normalizedTherapistId}`);
    } else {
      product = productSnapshot.data() || {};
      if (product.isActive === false) {
        return jsonError(res, 400, 'Subscription product is not active');
      }
    }

    const userSnapshot = await db.collection('users').doc(uid).get();
    if (!userSnapshot.exists) {
      return jsonError(res, 404, 'User profile not found');
    }
    const user = userSnapshot.data() || {};

    const amount = resolveProductAmount(product);
    if (amount <= 0) {
      return jsonError(
        res,
        400,
        'Subscription product amount is missing. Add numeric `amount` to subscription_products.',
      );
    }

    const basketId = buildBasketId(uid, normalizedProductId);
    const checkoutId = basketId;
    const subscriptionId = normalizeSubscriptionDocId(uid, normalizedTherapistId);
    const transactionAmount = toAmountString(amount);

    if (mockPaymentsEnabled) {
      await db.collection('subscriptions').doc(subscriptionId).set(
        {
          userId: uid,
          therapistId: normalizedTherapistId,
          productId: normalizedProductId,
          provider: 'payfast_pk',
          providerTransactionId: `mock_txn_${Date.now()}`,
          providerCustomerRef: normalizeValue(user.email),
          lastPaymentRef: `mock_ref_${Date.now()}`,
          basketId,
          amount,
          status: 'active',
          isActive: true,
          cancelAtPeriodEnd: false,
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(addDays(new Date(), 30)),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isMock: true,
        },
        { merge: true },
      );
      
      // Update earnings for therapist
      const earningsId = `earn_${basketId}`;
      await db.collection('therapist_earnings').doc(earningsId).set({
        therapistId: normalizedTherapistId,
        userId: uid,
        parentName: user.displayName || user.email || 'Parent',
        subscriptionId,
        amount,
        basketId,
        transactionId: `mock_txn_${Date.now()}`,
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      // Update therapist wallet balance
      await db.collection('therapist_profiles').doc(normalizedTherapistId).set(
        {
          walletBalance: admin.firestore.FieldValue.increment(amount),
          totalEarnings: admin.firestore.FieldValue.increment(amount),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      await updateTherapistThreadAccess(uid, normalizedTherapistId, true);
      await syncUserSubscriptionEntitlements(uid);

      return res.status(200).json({
        sessionId: subscriptionId,
        url: `${resolveCheckoutBaseUrl(req)}/api/v1/payment/return/success?mock=1&basket_id=${encodeURIComponent(
          basketId,
        )}`,
        mock: true,
      });
    }

    ensurePayFastConfigured();

    const token = await getPayFastAccessToken({ basketId, amount });
    const baseUrl = resolveCheckoutBaseUrl(req);
    const webhookUrl = `${baseUrl}/api/v1/payment/webhook`;

    const formFields = {
      CURRENCY_CODE: payfastConfig.currencyCode,
      MERCHANT_ID: payfastConfig.merchantId,
      MERCHANT_NAME: payfastConfig.merchantName,
      TOKEN: token,
      BASKET_ID: basketId,
      TXNAMT: transactionAmount,
      ORDER_DATE: formatOrderDate(),
      SUCCESS_URL: `${baseUrl}/api/v1/payment/return/success?basket_id=${encodeURIComponent(basketId)}`,
      FAILURE_URL: `${baseUrl}/api/v1/payment/return/failure?basket_id=${encodeURIComponent(basketId)}`,
      CHECKOUT_URL: payfastConfig.checkoutUrlField || webhookUrl,
      CUSTOMER_EMAIL_ADDRESS: normalizeValue(user.email),
      CUSTOMER_MOBILE_NO: normalizeValue(user.phone) || payfastConfig.customerMobileDefault,
      SIGNATURE: payfastConfig.signatureStatic,
      VERSION: payfastConfig.version,
      TXNDESC: payfastConfig.txDescription,
      PROCCODE: payfastConfig.procCode,
      TRAN_TYPE: payfastConfig.tranType,
      STORE_ID: payfastConfig.storeId || '',
      RECURRING_TXN: '',
      BILL_NUMBER: '',
      CUSTOMER_ID: uid,
      ADDITIONAL_VALUE: '',
      CUSTOMER_NAME: normalizeValue(user.displayName) || 'Customer',
      MERCHANT_CUSTOMER_ID: uid,
      CUSTOMER_IPADDRESS: req.ip || '127.0.0.1',
      MERCHANT_USERAGENT: req.headers['user-agent'] || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'ITEMS[0][SKU]': normalizedProductId,
      'ITEMS[0][NAME]': product.title || 'Therapy Package',
      'ITEMS[0][PRICE]': transactionAmount,
      'ITEMS[0][QTY]': '1',
    };

    await db.collection('checkout_sessions').doc(checkoutId).set(
      {
        userId: uid,
        therapistId: normalizedTherapistId,
        productId: normalizedProductId,
        subscriptionId,
        basketId,
        amount,
        status: 'pending',
        provider: 'payfast_pk',
        formFields,
        successUrl,
        cancelUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await db.collection('subscriptions').doc(subscriptionId).set(
      {
        userId: uid,
        therapistId: normalizedTherapistId,
        productId: normalizedProductId,
        provider: 'payfast_pk',
        status: 'pending',
        isActive: false,
        cancelAtPeriodEnd: false,
        basketId,
        amount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      sessionId: subscriptionId,
      url: `${baseUrl}/api/v1/checkout/redirect/${encodeURIComponent(checkoutId)}`,
    });
  } catch (error) {
    console.error('Checkout session failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to create checkout session');
  }
});

app.post('/api/v1/checkout/status', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { therapistId } = req.body || {};
    if (!therapistId) {
      return jsonError(res, 400, 'therapistId is required');
    }

    const normalizedTherapistId = normalizeValue(therapistId);
    const subscriptionId = normalizeSubscriptionDocId(uid, normalizedTherapistId);
    const subscriptionDoc = await db.collection('subscriptions').doc(subscriptionId).get();
    
    if (!subscriptionDoc.exists) {
      return res.status(200).json({ status: 'not_found', message: 'Subscription not found' });
    }

    const subscription = subscriptionDoc.data() || {};

    // If subscription is already active, return immediately — no gateway call needed
    if (subscription.status === 'active' && subscription.isActive === true) {
      return res.status(200).json({ status: 'active', message: 'Subscription is active.' });
    }

    // If subscription is in a terminal failure state, report it
    const terminalFailureStatuses = ['canceled', 'expired'];
    if (terminalFailureStatuses.includes(normalizeValue(subscription.status))) {
      return res.status(200).json({ status: subscription.status, message: `Subscription is ${subscription.status}.` });
    }

    // For pending/payment_failed subscriptions, try gateway verification to confirm
    const basketId = normalizeValue(subscription.basketId);
    if (!basketId) {
      // No basket ID — return current status, nothing we can verify
      return res.status(200).json({ status: normalizeValue(subscription.status) || 'pending', message: 'No basket ID to verify.' });
    }

    const amount = parseAmount(subscription.amount);

    let gatewayVerification = { verified: false, reason: 'Gateway inquiry not attempted' };
    try {
      // Attempt gateway verification but don't crash if it fails (UAT may be unreliable)
      gatewayVerification = await verifyTransactionWithGateway({ basketId }, amount);
    } catch (verifyError) {
      console.warn(`Gateway verification threw for basket ${basketId}: ${verifyError?.message}`);
      gatewayVerification = { verified: false, reason: verifyError?.message || 'Gateway inquiry error' };
    }
    
    if (gatewayVerification.verified) {
      const transactionId = gatewayVerification.payload?.transaction_id || gatewayVerification.payload?.pp_TxnRefNo || basketId;
      
      const eventId = crypto.createHash('sha256').update(`refresh:${basketId}:${transactionId}`).digest('hex');
      const wasInserted = await markPaymentEventProcessed(eventId, gatewayVerification.payload || {});
      
      if (wasInserted) {
        await subscriptionDoc.ref.set(
          {
            provider: 'payfast_pk',
            providerTransactionId: transactionId,
            lastPaymentRef: transactionId || basketId,
            status: 'active',
            isActive: true,
            cancelAtPeriodEnd: false,
            currentPeriodEnd: admin.firestore.Timestamp.fromDate(addDays(new Date(), 30)),
            verification: {
              verifiedByGateway: true,
              verifiedByHash: false,
              responseCode: gatewayVerification.responseCode || '00',
              status: gatewayVerification.status || 'success',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        // Fetch user profile for display name
        const userSnap = await db.collection('users').doc(uid).get();
        const parentName = userSnap.exists ? (userSnap.data().displayName || userSnap.data().email || 'Parent') : 'Parent';

        // Record therapist earnings
        const earningsId = `earn_${basketId}`;
        await db.collection('therapist_earnings').doc(earningsId).set({
          therapistId: normalizedTherapistId,
          userId: uid,
          parentName,
          subscriptionId,
          amount,
          basketId,
          transactionId,
          status: 'completed',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update therapist profile balance
        await db.collection('therapist_profiles').doc(normalizedTherapistId).set(
          {
            walletBalance: admin.firestore.FieldValue.increment(amount),
            totalEarnings: admin.firestore.FieldValue.increment(amount),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        await updateTherapistThreadAccess(uid, normalizedTherapistId, true);
        await syncUserSubscriptionEntitlements(uid);

        // Update checkout session status
        const checkoutSessionSnapshot = await db
          .collection('checkout_sessions')
          .where('basketId', '==', basketId)
          .limit(1)
          .get();
        if (!checkoutSessionSnapshot.empty) {
          await checkoutSessionSnapshot.docs[0].ref.set(
            {
              status: 'completed',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      return res.status(200).json({ status: 'active', message: 'Payment verified successfully.' });
    } else {
      // Gateway verification failed or not yet confirmed — return current Firestore status.
      // Do NOT mark the subscription as failed here — the PayFast webhook may arrive
      // asynchronously and activate it. Only report what Firestore currently shows.
      const currentStatus = normalizeValue(subscription.status) || 'pending';
      console.log(`Gateway verification not confirmed for basket ${basketId}: ${gatewayVerification.reason}. Current Firestore status: ${currentStatus}`);
      return res.status(200).json({ 
        status: currentStatus, 
        message: `Payment pending confirmation. ${gatewayVerification.reason || 'Webhook may still arrive.'}` 
      });
    }
  } catch (error) {
    console.error('Subscription status check failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to verify checkout status');
  }
});


async function processTransactionResult(rawPayload) {
  const normalized = normalizeProviderPayload(rawPayload);
  if (!normalized.basketId) {
    throw new Error('Missing basket id in payload');
  }

  const eventKey = normalized.transactionId || `${normalized.basketId}:${normalized.responseCode}:${normalized.status}`;
  const eventId = crypto.createHash('sha256').update(eventKey).digest('hex');
  const wasInserted = await markPaymentEventProcessed(eventId, normalized.raw);
  if (!wasInserted) {
    console.log(`Payment event ${eventId} already processed, skipping.`);
    return { status: 'already_processed' };
  }

  const subscriptionDoc = await findSubscriptionByBasketId(normalized.basketId);
  if (!subscriptionDoc) {
    throw new Error(`Subscription not found for basket ${normalized.basketId}`);
  }
  const subscription = subscriptionDoc.data() || {};
  const subscriptionUserId = normalizeValue(subscription.userId);
  const therapistId = normalizeValue(subscription.therapistId);

  const amount = parseAmount(subscription.amount);
  const gatewayVerification = payfastConfig.strictWebhookVerification
    ? await verifyTransactionWithGateway(normalized, amount)
    : {
        verified: false,
        status: '',
        responseCode: '',
        reason: 'Skipped gateway inquiry verification (strict mode disabled).',
      };
  const hashVerification = verifyPayFastValidationHash(normalized);
  const webhookSuccess = isSuccessStatus(normalized.status, normalized.responseCode);
  const isSuccess = payfastConfig.strictWebhookVerification
    ? gatewayVerification.verified && hashVerification.verified
    : webhookSuccess;

  if (isSuccess) {
    await subscriptionDoc.ref.set(
      {
        provider: 'payfast_pk',
        providerTransactionId: normalized.transactionId,
        lastPaymentRef: normalized.transactionId || normalized.basketId,
        status: 'active',
        isActive: true,
        cancelAtPeriodEnd: false,
        currentPeriodEnd: admin.firestore.Timestamp.fromDate(addDays(new Date(), 30)),
        verification: {
          verifiedByGateway: gatewayVerification.verified,
          verifiedByHash: hashVerification.verified,
          responseCode: gatewayVerification.responseCode || normalized.responseCode,
          status: gatewayVerification.status || normalized.status,
          hashErrorCode: hashVerification.errorCode || normalized.responseCode,
          hashProvided: hashVerification.providedHash || '',
          hashComputed: hashVerification.computedHash || '',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // Fetch user profile for display name
    const userSnap = await db.collection('users').doc(subscriptionUserId).get();
    const parentName = userSnap.exists ? (userSnap.data().displayName || userSnap.data().email || 'Parent') : 'Parent';

    // Record therapist earnings
    const earningsId = `earn_${normalized.basketId}`;
    await db.collection('therapist_earnings').doc(earningsId).set({
      therapistId,
      userId: subscriptionUserId,
      parentName,
      subscriptionId: subscriptionDoc.id,
      amount,
      basketId: normalized.basketId,
      transactionId: normalized.transactionId,
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update therapist profile balance
    await db.collection('therapist_profiles').doc(therapistId).set(
      {
        walletBalance: admin.firestore.FieldValue.increment(amount),
        totalEarnings: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (subscriptionUserId && therapistId) {
      await updateTherapistThreadAccess(subscriptionUserId, therapistId, true);
    }
    if (subscriptionUserId) {
      await syncUserSubscriptionEntitlements(subscriptionUserId);
    }
    
    const checkoutSessionSnapshot = await db
      .collection('checkout_sessions')
      .where('basketId', '==', normalized.basketId)
      .limit(1)
      .get();
    if (!checkoutSessionSnapshot.empty) {
      await checkoutSessionSnapshot.docs[0].ref.set(
        {
          status: 'completed',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return { received: true, status: 'active' };
  }

  await subscriptionDoc.ref.set(
    {
      status: 'payment_failed',
      isActive: false,
      cancelAtPeriodEnd: true,
      verification: {
        verifiedByGateway: gatewayVerification.verified,
        verifiedByHash: hashVerification.verified,
        responseCode: gatewayVerification.responseCode || normalized.responseCode,
        status: gatewayVerification.status || normalized.status,
        hashErrorCode: hashVerification.errorCode || normalized.responseCode,
        hashProvided: hashVerification.providedHash || '',
        hashComputed: hashVerification.computedHash || '',
        reason:
          (payfastConfig.strictWebhookVerification &&
            ((!gatewayVerification.verified && gatewayVerification.reason) ||
              (!hashVerification.verified && hashVerification.reason))) ||
          'Transaction failed',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  if (subscriptionUserId && therapistId) {
    await updateTherapistThreadAccess(subscriptionUserId, therapistId, false);
  }
  if (subscriptionUserId) {
    await syncUserSubscriptionEntitlements(subscriptionUserId);
  }

  const checkoutSessionSnapshot = await db
    .collection('checkout_sessions')
    .where('basketId', '==', normalized.basketId)
    .limit(1)
    .get();
  if (!checkoutSessionSnapshot.empty) {
    await checkoutSessionSnapshot.docs[0].ref.set(
      {
        status: 'failed',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  return { received: true, status: 'failed', reason: gatewayVerification.reason || hashVerification.reason || 'Transaction failed' };
}

app.post('/api/v1/payment/webhook', async (req, res) => {
  try {
    const result = await processTransactionResult(req.body || {});
    return res.status(200).json(result);
  } catch (error) {
    console.error('Payment webhook processing failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to process payment webhook');
  }
});

app.get('/api/v1/payment/return/success', async (req, res) => {
  const payload = req.query || {};
  const basketId = normalizeValue(payload.basket_id || payload.BASKET_ID);
  
  if (basketId) {
    try {
      // PayFast only redirects to SUCCESS_URL on successful payment.
      // Directly activate the subscription by basket_id without requiring
      // VALIDATION_HASH or STATUS fields (which are not included in redirect URLs).
      const subscriptionDoc = await findSubscriptionByBasketId(basketId);
      if (subscriptionDoc) {
        const subscription = subscriptionDoc.data() || {};
        const subscriptionUserId = normalizeValue(subscription.userId);
        const therapistId = normalizeValue(subscription.therapistId);
        const amount = parseAmount(subscription.amount);

        // Only activate if not already active (avoid double-processing)
        if (subscription.status !== 'active') {
          const eventId = crypto.createHash('sha256').update(`success_redirect:${basketId}`).digest('hex');
          const wasInserted = await markPaymentEventProcessed(eventId, { ...payload, source: 'success_redirect' });

          if (wasInserted) {
            const transactionId = normalizeValue(payload.transaction_id || payload.TRANSACTION_ID || payload.pp_TxnRefNo || '');
            
            await subscriptionDoc.ref.set(
              {
                provider: 'payfast_pk',
                providerTransactionId: transactionId || basketId,
                lastPaymentRef: transactionId || basketId,
                status: 'active',
                isActive: true,
                cancelAtPeriodEnd: false,
                currentPeriodEnd: admin.firestore.Timestamp.fromDate(addDays(new Date(), 30)),
                verification: {
                  verifiedByGateway: false,
                  verifiedByHash: false,
                  verifiedBySuccessRedirect: true,
                  responseCode: normalizeValue(payload.RESPONSE_CODE || payload.response_code || '00'),
                  status: 'success_redirect',
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );

            // Record earnings if therapist exists
            if (therapistId && amount > 0) {
              const userSnap = await db.collection('users').doc(subscriptionUserId).get();
              const parentName = userSnap.exists ? (userSnap.data().displayName || userSnap.data().email || 'Parent') : 'Parent';
              const earningsId = `earn_${basketId}`;
              await db.collection('therapist_earnings').doc(earningsId).set({
                therapistId,
                userId: subscriptionUserId,
                parentName,
                subscriptionId: subscriptionDoc.id,
                amount,
                basketId,
                transactionId: transactionId || basketId,
                status: 'completed',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              await db.collection('therapist_profiles').doc(therapistId).set(
                {
                  walletBalance: admin.firestore.FieldValue.increment(amount),
                  totalEarnings: admin.firestore.FieldValue.increment(amount),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
              );
            }

            if (subscriptionUserId && therapistId) {
              await updateTherapistThreadAccess(subscriptionUserId, therapistId, true);
            }
            if (subscriptionUserId) {
              await syncUserSubscriptionEntitlements(subscriptionUserId);
            }

            // Update checkout session
            const checkoutSessionSnapshot = await db
              .collection('checkout_sessions')
              .where('basketId', '==', basketId)
              .limit(1)
              .get();
            if (!checkoutSessionSnapshot.empty) {
              await checkoutSessionSnapshot.docs[0].ref.set(
                { status: 'completed', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
                { merge: true },
              );
            }

            console.log(`Payment success redirect processed for basket ${basketId}: subscription activated.`);
          } else {
            console.log(`Payment success redirect for basket ${basketId}: event already processed.`);
          }
        } else {
          console.log(`Payment success redirect for basket ${basketId}: subscription already active.`);
        }
      } else {
        console.warn(`Payment success redirect: no subscription found for basket ${basketId}.`);
      }
    } catch (error) {
      console.warn('Success redirect processing failed:', error?.message || error);
    }
  }

  res.status(200).send(buildStatusPageHtml(true, 'Your checkout payment was completed successfully. You can close this browser page and return to the AutiEase app to start chatting with your therapist.'));
});

app.get('/api/v1/payment/return/failure', async (req, res) => {
  const payload = req.query || {};
  const basketId = normalizeValue(payload.basket_id || payload.BASKET_ID);

  if (basketId) {
    try {
      // PayFast redirects to FAILURE_URL when payment fails or is cancelled.
      // Mark subscription as payment_failed so the user can retry.
      const subscriptionDoc = await findSubscriptionByBasketId(basketId);
      if (subscriptionDoc) {
        const subscription = subscriptionDoc.data() || {};
        // Only mark failed if not already active (don't downgrade a successful payment)
        if (subscription.status !== 'active') {
          const eventId = crypto.createHash('sha256').update(`failure_redirect:${basketId}`).digest('hex');
          const wasInserted = await markPaymentEventProcessed(eventId, { ...payload, source: 'failure_redirect' });
          if (wasInserted) {
            await subscriptionDoc.ref.set(
              {
                status: 'payment_failed',
                isActive: false,
                cancelAtPeriodEnd: true,
                verification: {
                  verifiedByGateway: false,
                  verifiedByHash: false,
                  verifiedBySuccessRedirect: false,
                  responseCode: normalizeValue(payload.RESPONSE_CODE || payload.response_code || ''),
                  status: 'failure_redirect',
                  reason: 'Payment failed or cancelled by user',
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
            console.log(`Payment failure redirect processed for basket ${basketId}: subscription marked payment_failed.`);
          }
        }
      }
    } catch (error) {
      console.warn('Redirect failure processing failed:', error?.message || error);
    }
  }

  res.status(200).send(buildStatusPageHtml(false, 'Your checkout payment was not completed or failed. If money was deducted, please wait a few minutes and tap Refresh Status in the app. Otherwise, please try again.'));
});

app.post('/api/v1/subscription/cancel', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { subscriptionId } = req.body || {};
    if (!subscriptionId) {
      return jsonError(res, 400, 'subscriptionId is required');
    }

    const subscriptionRef = db.collection('subscriptions').doc(subscriptionId);
    const snapshot = await subscriptionRef.get();
    if (!snapshot.exists) {
      return jsonError(res, 404, 'Subscription not found');
    }

    const subscription = snapshot.data() || {};
    if (normalizeValue(subscription.userId) !== uid) {
      return jsonError(res, 403, 'Cannot cancel another user subscription');
    }

    await subscriptionRef.set(
      {
        cancelAtPeriodEnd: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const currentPeriodEnd = subscription.currentPeriodEnd;
    const shouldDeactivateNow = !(currentPeriodEnd instanceof admin.firestore.Timestamp) || currentPeriodEnd.toDate() <= new Date();
    if (shouldDeactivateNow) {
      await subscriptionRef.set(
        {
          status: 'canceled',
          isActive: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await updateTherapistThreadAccess(uid, normalizeValue(subscription.therapistId), false);
    }
    await syncUserSubscriptionEntitlements(uid);

    return res.status(200).json({ status: shouldDeactivateNow ? 'canceled' : 'cancel_scheduled' });
  } catch (error) {
    console.error('Cancel subscription failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to cancel subscription');
  }
});

app.post('/api/v1/subscription/reactivate', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { subscriptionId } = req.body || {};
    if (!subscriptionId) {
      return jsonError(res, 400, 'subscriptionId is required');
    }

    const subscriptionRef = db.collection('subscriptions').doc(subscriptionId);
    const snapshot = await subscriptionRef.get();
    if (!snapshot.exists) {
      return jsonError(res, 404, 'Subscription not found');
    }

    const subscription = snapshot.data() || {};
    if (normalizeValue(subscription.userId) !== uid) {
      return jsonError(res, 403, 'Cannot reactivate another user subscription');
    }

    const currentPeriodEnd = subscription.currentPeriodEnd;
    const periodStillActive = currentPeriodEnd instanceof admin.firestore.Timestamp && currentPeriodEnd.toDate() > new Date();

    await subscriptionRef.set(
      {
        cancelAtPeriodEnd: false,
        status: periodStillActive ? 'active' : 'expired',
        isActive: periodStillActive,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await updateTherapistThreadAccess(uid, normalizeValue(subscription.therapistId), periodStillActive);
    await syncUserSubscriptionEntitlements(uid);

    return res.status(200).json({ status: periodStillActive ? 'reactivated' : 'expired_needs_renewal' });
  } catch (error) {
    console.error('Reactivate subscription failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to reactivate subscription');
  }
});

// Therapist withdrawal request endpoint
app.post('/api/v1/therapist/withdraw', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { amount, paymentMethod, accountDetails } = req.body || {};

    if (!amount || !paymentMethod || !accountDetails) {
      return jsonError(res, 400, 'amount, paymentMethod, and accountDetails are required');
    }

    const parsedWithdrawAmount = parseAmount(amount);
    if (parsedWithdrawAmount <= 0) {
      return jsonError(res, 400, 'Withdrawal amount must be greater than zero');
    }

    const therapistRef = db.collection('therapist_profiles').doc(uid);
    const therapistSnap = await therapistRef.get();
    if (!therapistSnap.exists) {
      return jsonError(res, 404, 'Therapist profile not found');
    }

    const therapistData = therapistSnap.data() || {};
    const walletBalance = parseAmount(therapistData.walletBalance);

    if (walletBalance < parsedWithdrawAmount) {
      return jsonError(res, 400, 'Insufficient balance in wallet');
    }

    // Deduct balance and add to pending withdrawals
    await therapistRef.set(
      {
        walletBalance: admin.firestore.FieldValue.increment(-parsedWithdrawAmount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const txnId = `withdraw_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;

    // Create withdrawal request log
    await db.collection('withdrawal_requests').doc(txnId).set({
      therapistId: uid,
      therapistName: therapistData.displayName || 'Therapist',
      amount: parsedWithdrawAmount,
      paymentMethod,
      accountDetails,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Create transaction history log in therapist_earnings
    await db.collection('therapist_earnings').doc(txnId).set({
      therapistId: uid,
      amount: parsedWithdrawAmount,
      type: 'withdrawal',
      paymentMethod,
      accountDetails,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).json({ success: true, remainingBalance: walletBalance - parsedWithdrawAmount });
  } catch (error) {
    console.error('Withdrawal failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to request withdrawal');
  }
});

// Self-contained cron checks every night at midnight to reconcile expired subscriptions
cron.schedule('0 0 * * *', async () => {
  console.log('Running daily automated subscription expiry reconciliation...');
  try {
    const result = await reconcileExpiredSubscriptions();
    console.log(`Reconciliation finished: expired ${result.expiredCount} subscriptions.`);
  } catch (error) {
    console.error('Automated reconciliation cron failed:', error);
  }
});

// Trigger endpoint for manual reconciliation
app.post('/api/v1/subscription/reconcile-expired', async (req, res) => {
  try {
    const expectedSecret = normalizeValue(process.env.RECONCILE_CRON_SECRET);
    if (expectedSecret) {
      const provided = normalizeValue(req.header('x-cron-secret'));
      if (!provided || provided !== expectedSecret) {
        return jsonError(res, 401, 'Unauthorized cron request');
      }
    }

    const result = await reconcileExpiredSubscriptions();
    return res.status(200).json({ ok: true, ...result });
  } catch (error) {
    console.error('Reconcile expired subscriptions failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to reconcile subscriptions');
  }
});

const port = Number.parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => {
  console.log(`AutiEase GoPayFast payment backend running on port ${port}`);
});
