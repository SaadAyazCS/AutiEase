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

/**
 * Build an HTML page that opens the AutiEase app via a custom-scheme deep link.
 *
 * WHY: Chrome on Android IGNORES server-side HTTP redirects to custom schemes (autiease://).
 * The only reliable approach is an HTML page that triggers window.location.href via JavaScript
 * and also shows a visible "Return to AutiEase" button as a manual fallback.
 *
 * @param {boolean} isSuccess - Whether the payment was successful
 * @param {string}  deepLink  - The full autiease:// URL to open (e.g. autiease://payment-result?status=success&basket_id=...)
 * @param {string}  message   - Human-readable message to show on the page
 * @param {string}  title     - Page/card title
 */
function buildDeepLinkPage(isSuccess, deepLink, message, title) {
  const color      = isSuccess ? '#00c853' : '#ef4444';
  const bgColor    = isSuccess ? '#f0fdf4' : '#fef2f2';
  const borderColor = isSuccess ? '#bbf7d0' : '#fecaca';
  const icon = isSuccess
    ? `<svg width="48" height="48" fill="none" stroke="${color}" stroke-width="2.5" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4"/></svg>`
    : `<svg width="48" height="48" fill="none" stroke="${color}" stroke-width="2.5" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 9l-6 6M9 9l6 6"/></svg>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${title} — AutiEase</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet"/>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', sans-serif;
      background: ${bgColor};
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    .card {
      background: white;
      border: 1.5px solid ${borderColor};
      border-radius: 20px;
      padding: 40px 32px;
      max-width: 400px;
      width: 100%;
      text-align: center;
      box-shadow: 0 8px 32px rgba(0,0,0,0.08);
    }
    .icon { margin-bottom: 20px; }
    h2 { font-size: 22px; font-weight: 700; color: #111827; margin-bottom: 10px; }
    p  { font-size: 14px; color: #6b7280; line-height: 1.6; margin-bottom: 28px; }
    .btn {
      display: block;
      width: 100%;
      padding: 14px 24px;
      background: ${color};
      color: white;
      font-size: 16px;
      font-weight: 600;
      text-decoration: none;
      border-radius: 12px;
      border: none;
      cursor: pointer;
      transition: opacity 0.2s;
    }
    .btn:hover { opacity: 0.9; }
    .hint { margin-top: 16px; font-size: 12px; color: #9ca3af; }
    .countdown { font-weight: 600; color: ${color}; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">${icon}</div>
    <h2>${title}</h2>
    <p>${message}</p>
    <a class="btn" href="${deepLink}" id="returnBtn">Return to AutiEase</a>
    <p class="hint">Auto-opening in <span class="countdown" id="countdown">3</span>s...</p>
  </div>
  <script>
    var deepLink = ${JSON.stringify(deepLink)};
    var attempts = 0;

    function openApp() {
      window.location.href = deepLink;
    }

    // Auto-trigger with countdown
    var secs = 3;
    var timer = setInterval(function() {
      secs--;
      var el = document.getElementById('countdown');
      if (el) el.textContent = secs;
      if (secs <= 0) {
        clearInterval(timer);
        openApp();
      }
    }, 1000);

    // Also trigger immediately on button tap
    document.getElementById('returnBtn').addEventListener('click', function(e) {
      e.preventDefault();
      clearInterval(timer);
      openApp();
    });
  </script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// SafePay Configuration
// ---------------------------------------------------------------------------
const SAFEPAY_ENV = normalizeValue(process.env.SAFEPAY_ENVIRONMENT) || 'sandbox';
const safepayConfig = {
  environment: SAFEPAY_ENV,
  apiKey: normalizeValue(process.env.SAFEPAY_API_KEY),
  secretKey: normalizeValue(process.env.SAFEPAY_SECRET_KEY),
  webhookSecret: normalizeValue(process.env.SAFEPAY_WEBHOOK_SECRET),
  baseUrl: SAFEPAY_ENV === 'production'
    ? 'https://api.getsafepay.com'
    : 'https://sandbox.api.getsafepay.com',
  checkoutBaseUrl: SAFEPAY_ENV === 'production'
    ? 'https://api.getsafepay.com'
    : 'https://sandbox.api.getsafepay.com',
};

function ensureSafepayConfigured() {
  if (!safepayConfig.apiKey || !safepayConfig.secretKey) {
    throw new Error(
      'SafePay is not configured. Required: SAFEPAY_API_KEY, SAFEPAY_SECRET_KEY.'
    );
  }
}

/**
 * Verify SafePay webhook HMAC-SHA256 signature.
 * Header X-SFPY-SIGNATURE = HMAC-SHA256(timestamp + '.' + rawBody, base64Decode(webhookSecret))
 */
function verifySafepayWebhook(req) {
  const providedSignature = req.headers['x-sfpy-signature'] || '';
  const timestamp = req.headers['x-sfpy-timestamp'] || '';
  const rawBody = req.rawBody || '';
  const secret = safepayConfig.webhookSecret;

  if (!secret) {
    // If no webhook secret configured, skip verification in dev (log a warning)
    console.warn('SAFEPAY_WEBHOOK_SECRET not set — skipping webhook signature check.');
    return { verified: true, reason: 'no-secret-configured' };
  }
  if (!providedSignature || !timestamp) {
    return { verified: false, reason: 'Missing X-SFPY-SIGNATURE or X-SFPY-TIMESTAMP header' };
  }

  try {
    let keyBytes;
    if (/^[0-9a-fA-F]{64}$/.test(secret)) {
      keyBytes = Buffer.from(secret, 'hex');
    } else {
      keyBytes = Buffer.from(secret, 'base64');
    }
    const signingPayload = `${timestamp}.${rawBody}`;
    const computedHmac = crypto
      .createHmac('sha256', keyBytes)
      .update(signingPayload, 'utf8')
      .digest('hex');

    // Constant-time comparison to prevent timing attacks
    const computedBuf = Buffer.from(computedHmac, 'hex');
    const providedBuf = Buffer.from(providedSignature.toLowerCase(), 'hex');
    const verified =
      computedBuf.length === providedBuf.length &&
      crypto.timingSafeEqual(computedBuf, providedBuf);

    return {
      verified,
      reason: verified ? '' : 'HMAC signature mismatch',
    };
  } catch (err) {
    return { verified: false, reason: `Signature verification error: ${err.message}` };
  }
}

/**
 * Calculate SafePay fees and AutiEase platform revenue.
 *
 * SafePay pricing (from getsafepay.pk/pricing):
 *   - Local card (Visa/Mastercard PKR): 2.9% + Rs.30 flat + 13% Pakistan GST on total fee
 *   - International card:               3.2% + Rs.30 flat + 13% Pakistan GST on total fee
 *   - Mobile wallets (EasyPaisa/JazzCash): 1.5%, no flat fee, no GST
 *   - Bank / Raast:                     1.5%, no flat fee, no GST
 *
 * Sandbox vs Production:
 *   SANDBOX  — Rs.30 flat fee is WAIVED by SafePay (confirmed from dashboard Jun 2026):
 *              10,000 × 2.9% = Rs.290 processing + 290 × 13% = Rs.37.70 GST → total Rs.327.70
 *   PRODUCTION — Rs.30 flat fee IS charged:
 *              10,000 × 2.9% = Rs.290 + Rs.30 flat = Rs.320 sub-total
 *              Rs.320 × 13% GST = Rs.41.60 → total fee Rs.361.60
 *
 * Auto-detected via SAFEPAY_ENVIRONMENT env var ("production" = live, anything else = sandbox).
 * Can be overridden per-variable: SAFEPAY_GATEWAY_RATE, SAFEPAY_GATEWAY_FLAT, SAFEPAY_GST_RATE.
 *
 * @param {number} grossAmount - Full subscription amount paid by parent
 * @param {object} rawPayload  - Webhook payload or SafePay API transaction data
 * @returns {{ safepayFee: number, safepayGst: number, platformFee: number, netAmount: number }}
 */
function calculateFees(grossAmount, rawPayload = {}) {
  // Detect environment — sandbox waives the Rs.30 flat fee
  const isProduction = normalizeValue(process.env.SAFEPAY_ENVIRONMENT).toLowerCase() === 'production';

  // Default: local Pakistan card (2.9% + Rs.30 in production, 2.9% only in sandbox)
  let gatewayRate = 0.029;
  let gatewayFlat = isProduction ? 30 : 0; // Rs.30 flat only in production
  let gstRate = 0.13;  // Pakistan mandatory GST on the total processing fee
  let applyGst = true;

  const payload = rawPayload || {};
  const data = payload.data || payload;

  const channel = normalizeValue(
    data.channel ||
    data.payment_method?.channel ||
    data.payment_method?.type ||
    payload.payment_method ||
    payload.channel ||
    ''
  ).toLowerCase();

  const isInternational = isTruthy(
    data.payment_method?.card?.international ||
    payload.is_international ||
    false
  );

  // Determine rate based on payment channel
  if (channel === 'wallet' || channel === 'easypaisa' || channel === 'jazzcash' || channel === 'mobile_wallet') {
    gatewayRate = 0.015;
    gatewayFlat = 0;   // Wallets: no flat fee
    applyGst = false;  // Wallets: no GST component
  } else if (channel === 'bank' || channel === 'raast' || channel === 'direct_debit' || channel === 'bank_account') {
    gatewayRate = 0.015;
    gatewayFlat = 0;
    applyGst = false;
  } else if (channel === 'card') {
    gatewayRate = isInternational ? 0.032 : 0.029;
    gatewayFlat = isProduction ? 30 : 0;
    applyGst = true;
  }

  // Allow manual overrides via env variables (e.g. for negotiated rates)
  const envRate = parseFloat(process.env.SAFEPAY_GATEWAY_RATE);
  const envFlat = parseFloat(process.env.SAFEPAY_GATEWAY_FLAT);
  const envGst  = parseFloat(process.env.SAFEPAY_GST_RATE);
  if (!isNaN(envRate)) gatewayRate = envRate;
  if (!isNaN(envFlat)) gatewayFlat = envFlat; // explicit override wins over auto-detection
  if (!isNaN(envGst))  gstRate = envGst;

  // Formula: (% of amount + flat fee) + GST on that total
  // Sandbox:    (290 + 0)   × (1 + 13%) = 327.70  ✅ matches dashboard
  // Production: (290 + 30)  × (1 + 13%) = 361.60
  const processingFee = parseFloat((grossAmount * gatewayRate + gatewayFlat).toFixed(2));
  const safepayGst    = applyGst ? parseFloat((processingFee * gstRate).toFixed(2)) : 0;
  const safepayFee    = parseFloat((processingFee + safepayGst).toFixed(2));

  const afterGateway = parseFloat((grossAmount - safepayFee).toFixed(2));
  const platformFee  = parseFloat((afterGateway * 0.07).toFixed(2));
  const netAmount    = parseFloat((afterGateway - platformFee).toFixed(2));

  return { safepayFee, safepayGst, platformFee, netAmount };
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

/**
 * Reusable helper to activate a subscription and record therapist earnings.
 *
 * @param {string} basketId - Unique basket/order ID
 * @param {string} transactionId - SafePay transaction tracker ID or fallback
 * @param {string} source - Verification source ('success_redirect', 'failure_redirect_doublecheck', 'webhook', 'status_check')
 * @param {object} additionalPayload - Extra data returned by the payment gateway
 * @returns {Promise<boolean>} Whether activation succeeded
 */
async function activateSubscription(basketId, transactionId, source, additionalPayload = {}) {
  const subscriptionDoc = await findSubscriptionByBasketId(basketId);
  if (!subscriptionDoc) {
    console.warn(`activateSubscription: no subscription found for basket ${basketId}.`);
    return false;
  }

  const subscription = subscriptionDoc.data() || {};
  const subscriptionUserId = normalizeValue(subscription.userId);
  const therapistId = normalizeValue(subscription.therapistId);
  const amount = parseAmount(subscription.amount);

  // If already active, return early (avoid double processing/duplicate entries)
  if (subscription.status === 'active' && subscription.isActive === true) {
    console.log(`activateSubscription: subscription for basket ${basketId} is already active.`);
    return true;
  }

  // Prevent duplicate processing of the same event
  const eventKey = `${source}:${basketId}`;
  const eventId = crypto.createHash('sha256').update(eventKey).digest('hex');
  const wasInserted = await markPaymentEventProcessed(eventId, { ...additionalPayload, source });
  if (!wasInserted) {
    console.log(`activateSubscription: event ${eventId} already processed, skipping.`);
    return true;
  }

  const { safepayFee, platformFee, netAmount } = calculateFees(amount, additionalPayload);
  const batch = db.batch();

  batch.set(subscriptionDoc.ref, {
    provider: 'safepay',
    providerTransactionId: transactionId || basketId,
    lastPaymentRef: transactionId || basketId,
    status: 'active',
    isActive: true,
    cancelAtPeriodEnd: false,
    currentPeriodEnd: admin.firestore.Timestamp.fromDate(addDays(new Date(), 30)),
    verification: {
      verifiedByHmac: source === 'webhook',
      verifiedBySuccessRedirect: source === 'success_redirect',
      verifiedByFailureRedirectDoubleCheck: source === 'failure_redirect_doublecheck',
      verifiedByGateway: source === 'status_check',
      status: source,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Record earnings if therapist exists
  if (therapistId && amount > 0) {
    const userSnap = await db.collection('users').doc(subscriptionUserId).get();
    const parentName = userSnap.exists ? (userSnap.data().displayName || userSnap.data().email || 'Parent') : 'Parent';
    const earningsId = `earn_${basketId}`;
    batch.set(db.collection('therapist_earnings').doc(earningsId), {
      therapistId,
      userId: subscriptionUserId,
      parentName,
      subscriptionId: subscriptionDoc.id,
      type: 'subscription',
      grossAmount: amount,
      safepayFee,
      platformFee,
      netAmount,
      amount: netAmount,
      basketId,
      transactionId: transactionId || basketId,
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    batch.set(db.collection('therapist_profiles').doc(therapistId), {
      walletBalance: admin.firestore.FieldValue.increment(netAmount),
      totalEarnings: admin.firestore.FieldValue.increment(netAmount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    batch.set(db.collection('platform_revenue').doc('summary'), {
      totalRevenue: admin.firestore.FieldValue.increment(platformFee),
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();

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

  console.log(`activateSubscription: subscription activated successfully for basket ${basketId} via ${source}.`);
  return true;
}

async function verifyTransactionWithGateway(trackerToken) {
  if (!trackerToken) {
    return { verified: false, reason: 'Missing tracker token' };
  }

  try {
    ensureSafepayConfigured();

    const url = `${safepayConfig.baseUrl}/reporter/api/v1/payments/${trackerToken}`;
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'X-SFPY-MERCHANT-SECRET': safepayConfig.secretKey,
      },
    });

    if (!response.ok) {
      const text = await response.text();
      return { verified: false, reason: `Reporter API failed (${response.status}): ${text}` };
    }

    const payload = await response.json();
    const data = payload.data || {};
    const state = normalizeValue(data.state).toUpperCase();
    const verified = state === 'PAID';

    return {
      verified,
      state,
      payload,
      reason: verified ? '' : `Gateway status is ${state}`,
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

// Capture raw body bytes for SafePay HMAC webhook signature verification.
// Must be set up BEFORE express.json() so the verify callback fires.
let rawBodyStore = null;

app.use(express.urlencoded({ extended: false }));
app.use(
  express.json({
    verify: (req, _res, buf) => {
      rawBodyStore = buf.toString('utf8');
    },
  }),
);
// Expose rawBody on every request (webhook handler reads req.rawBody)
app.use((req, _res, next) => {
  req.rawBody = rawBodyStore;
  rawBodyStore = null;
  next();
});

app.get('/health', (_req, res) => {
  res.status(200).json({ ok: true, service: 'autiease-payment-backend', provider: 'safepay', mock: mockPaymentsEnabled, version: '1.1.1-safepay-test-endpoint' });
});

app.get('/api/v1/test-tracker/:tracker_token', async (req, res) => {
  const token = req.params.tracker_token;
  try {
    const gatewayVerification = await verifyTransactionWithGateway(token);
    res.status(200).json(gatewayVerification);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/v1/diagnose-keys', async (req, res) => {
  try {
    const mask = (str) => {
      if (!str) return 'not set';
      if (str.length <= 8) return '***';
      return `${str.slice(0, 6)}...${str.slice(-4)}`;
    };

    const diagnostics = {
      environment: safepayConfig.environment,
      apiKeyMasked: mask(safepayConfig.apiKey),
      secretKeyMasked: mask(safepayConfig.secretKey),
      webhookSecretMasked: mask(safepayConfig.webhookSecret),
      baseUrl: safepayConfig.baseUrl,
    };

    // Run a quick order init and status check to verify keys are matching
    let flowTest = { success: false, initStatus: null, reporterStatus: null, error: null };
    try {
      const initUrl = `${safepayConfig.baseUrl}/order/v1/init`;
      const initRes = await fetch(initUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${safepayConfig.secretKey}`
        },
        body: JSON.stringify({
          client: safepayConfig.apiKey,
          environment: 'sandbox',
          amount: 1000,
          currency: 'PKR',
          order_id: 'diagnose-' + Date.now(),
          source: 'app',
          cancel_url: 'https://example.com/cancel',
          redirect_url: 'https://example.com/success'
        })
      });

      flowTest.initStatus = initRes.status;
      const initData = await initRes.json();
      const token = initData?.data?.token || initData?.token;

      if (token) {
        const reporterUrl = `${safepayConfig.baseUrl}/reporter/api/v1/payments/${token}`;
        const reporterRes = await fetch(reporterUrl, {
          method: 'GET',
          headers: {
            'X-SFPY-MERCHANT-SECRET': safepayConfig.secretKey
          }
        });
        flowTest.reporterStatus = reporterRes.status;
        const reporterData = await reporterRes.json();
        flowTest.reporterResponse = reporterData;
        if (reporterRes.status === 200) {
          flowTest.success = true;
        }
      } else {
        flowTest.error = `Order init response did not return a token: ${JSON.stringify(initData)}`;
      }
    } catch (flowErr) {
      flowTest.error = flowErr.message || String(flowErr);
    }

    res.status(200).json({ diagnostics, flowTest });
  } catch (err) {
    res.status(500).json({ error: err.message });
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
      const { safepayFee, platformFee, netAmount } = calculateFees(amount, { channel: 'card', is_international: false });
      const mockTxnId = `mock_txn_${Date.now()}`;
      const batch = db.batch();

      batch.set(db.collection('subscriptions').doc(subscriptionId), {
        userId: uid,
        therapistId: normalizedTherapistId,
        productId: normalizedProductId,
        provider: 'safepay',
        providerTransactionId: mockTxnId,
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
      }, { merge: true });

      const earningsId = `earn_${basketId}`;
      batch.set(db.collection('therapist_earnings').doc(earningsId), {
        therapistId: normalizedTherapistId,
        userId: uid,
        parentName: user.displayName || user.email || 'Parent',
        subscriptionId,
        type: 'subscription',
        grossAmount: amount,
        safepayFee,
        platformFee,
        netAmount,
        amount: netAmount,
        basketId,
        transactionId: mockTxnId,
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.set(db.collection('therapist_profiles').doc(normalizedTherapistId), {
        walletBalance: admin.firestore.FieldValue.increment(netAmount),
        totalEarnings: admin.firestore.FieldValue.increment(netAmount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Track platform revenue
      batch.set(db.collection('platform_revenue').doc('summary'), {
        totalRevenue: admin.firestore.FieldValue.increment(platformFee),
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      await batch.commit();
      await updateTherapistThreadAccess(uid, normalizedTherapistId, true);
      await syncUserSubscriptionEntitlements(uid);

      const baseUrl = resolveCheckoutBaseUrl(req);
      return res.status(200).json({
        sessionId: subscriptionId,
        url: `${baseUrl}/api/v1/payment/return/success?mock=1&basket_id=${encodeURIComponent(basketId)}`,
        mock: true,
      });
    }

    ensureSafepayConfigured();

    const baseUrl = resolveCheckoutBaseUrl(req);

    // Create SafePay order via REST API
    const safepayOrderRes = await fetch(`${safepayConfig.baseUrl}/order/v1/init`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${safepayConfig.secretKey}`,
      },
      body: JSON.stringify({
        client: safepayConfig.apiKey,
        environment: safepayConfig.environment,
        amount: Math.round(amount), // SafePay expects amount in PKR (Rupees)
        currency: 'PKR',
        order_id: basketId,
        source: 'app',
        cancel_url: `${baseUrl}/api/v1/payment/return/failure/${encodeURIComponent(basketId)}`,
        redirect_url: `${baseUrl}/api/v1/payment/return/success/${encodeURIComponent(basketId)}`,
      }),
    });

    if (!safepayOrderRes.ok) {
      const errText = await safepayOrderRes.text();
      console.error('SafePay /order/v1/init failed:', safepayOrderRes.status, errText);
      return jsonError(res, 502, `SafePay Error (${safepayOrderRes.status}): ${errText}`);
    }

    const safepayOrder = await safepayOrderRes.json();
    const beacon = safepayOrder?.data?.token || safepayOrder?.token;
    if (!beacon) {
      console.error('SafePay /order/v1/init response missing token:', JSON.stringify(safepayOrder));
      return jsonError(res, 502, 'SafePay did not return a checkout token.');
    }

    const successRedirectUrl = `${baseUrl}/api/v1/payment/return/success/${encodeURIComponent(basketId)}`;
    const cancelRedirectUrl = `${baseUrl}/api/v1/payment/return/failure/${encodeURIComponent(basketId)}`;

    const checkoutUrl = `${safepayConfig.checkoutBaseUrl}/checkout/pay?` +
      `env=${safepayConfig.environment}` +
      `&beacon=${encodeURIComponent(beacon)}` +
      `&client=${safepayConfig.apiKey}` +
      `&order_id=${basketId}` +
      `&redirect_url=${encodeURIComponent(successRedirectUrl)}` +
      `&cancel_url=${encodeURIComponent(cancelRedirectUrl)}` +
      `&source=custom`;

    // Save checkout session to Firestore
    await db.collection('checkout_sessions').doc(basketId).set({
      userId: uid,
      therapistId: normalizedTherapistId,
      productId: normalizedProductId,
      subscriptionId,
      basketId,
      amount,
      status: 'pending',
      provider: 'safepay',
      safepayBeacon: beacon,
      successUrl,
      cancelUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Create pending subscription
    await db.collection('subscriptions').doc(subscriptionId).set({
      userId: uid,
      therapistId: normalizedTherapistId,
      productId: normalizedProductId,
      provider: 'safepay',
      status: 'pending',
      isActive: false,
      cancelAtPeriodEnd: false,
      basketId,
      amount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return res.status(200).json({
      sessionId: subscriptionId,
      url: checkoutUrl,
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

    let trackerToken = basketId;
    try {
      const checkoutSessionDoc = await db.collection('checkout_sessions').doc(basketId).get();
      if (checkoutSessionDoc.exists) {
        const checkoutSession = checkoutSessionDoc.data() || {};
        if (checkoutSession.safepayBeacon) {
          trackerToken = checkoutSession.safepayBeacon;
        }
      }
    } catch (dbError) {
      console.warn(`Failed to retrieve checkout session for basket ${basketId}:`, dbError.message);
    }

    let gatewayVerification = { verified: false, reason: 'Gateway inquiry not attempted' };
    try {
      // Attempt gateway verification but don't crash if it fails (UAT may be unreliable)
      gatewayVerification = await verifyTransactionWithGateway(trackerToken);
    } catch (verifyError) {
      console.warn(`Gateway verification threw for tracker ${trackerToken}: ${verifyError?.message}`);
      gatewayVerification = { verified: false, reason: verifyError?.message || 'Gateway inquiry error' };
    }

    if (gatewayVerification.verified) {
      const transactionId = gatewayVerification.payload?.data?.token || trackerToken;
      await activateSubscription(basketId, transactionId, 'status_check', gatewayVerification.payload);
      return res.status(200).json({ status: 'active', message: 'Payment verified successfully.' });
    } else {
      // Gateway verification failed or not yet confirmed — return current Firestore status.
      // Do NOT mark the subscription as failed here — the webhook may arrive
      // asynchronously and activate it. Only report what Firestore currently shows.
      const currentStatus = normalizeValue(subscription.status) || 'pending';
      console.log(`Gateway verification not confirmed for tracker ${trackerToken}: ${gatewayVerification.reason}. Current Firestore status: ${currentStatus}`);
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

  // Determine payment success from SafePay event data
  const webhookEvent = normalized.raw;
  const eventType = normalizeValue(webhookEvent.type || webhookEvent.event || webhookEvent.status || normalized.status);
  const isSuccess = [
    'payment.captured',
    'payment.success',
    'payment.completed',
    'tracker.completed',
    'tracker.ended',
    'success',
    'completed',
    'paid'
  ].includes(eventType.toLowerCase());

  if (isSuccess) {
    // Re-use activateSubscription to safely update the status and record metrics
    await activateSubscription(normalized.basketId, normalized.transactionId, 'webhook', normalized.raw);
    return { received: true, status: 'active' };
  }

  await subscriptionDoc.ref.set({
    status: 'payment_failed',
    isActive: false,
    cancelAtPeriodEnd: true,
    verification: {
      verifiedByHmac: false,
      reason: 'SafePay event did not indicate success',
      status: normalized.status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
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

  return { received: true, status: 'failed', reason: 'SafePay event did not indicate success' };
}

app.post('/api/v1/payment/webhook', async (req, res) => {
  try {
    // Verify SafePay HMAC signature before processing
    const sigResult = verifySafepayWebhook(req);
    if (!sigResult.verified) {
      console.warn('Webhook HMAC verification failed:', sigResult.reason, 'IP:', req.ip);
      return jsonError(res, 401, 'Webhook signature invalid');
    }

    const body = req.body || {};
    // SafePay webhook: extract basket_id / order_id from the event payload
    const rawPayload = {
      basket_id: body.order_id || body.basket_id || body.data?.order_id || '',
      transaction_id: body.transaction_id || body.data?.transaction_id || '',
      status: body.status || body.type || '',
      ...body,
    };
    const result = await processTransactionResult(rawPayload);
    return res.status(200).json(result);
  } catch (error) {
    console.error('Payment webhook processing failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to process payment webhook');
  }
});

app.get('/api/v1/payment/return/success/:basket_id?', async (req, res) => {
  const payload = req.query || {};
  const basketId = normalizeValue(req.params.basket_id || payload.basket_id || payload.BASKET_ID);

  if (basketId) {
    try {
      const transactionId = normalizeValue(payload.tracker || payload.transaction_id || payload.order_ref || '');
      await activateSubscription(basketId, transactionId, 'success_redirect', payload);
    } catch (error) {
      console.warn('Success redirect processing failed:', error?.message || error);
    }
  }

  // Chrome on Android ignores server-side redirects to custom schemes (autiease://).
  // Must serve an HTML page that uses JavaScript window.location.href to trigger the deep link.
  const deepLink = `autiease://payment-result?status=success&basket_id=${encodeURIComponent(basketId || '')}`;
  res.send(buildDeepLinkPage(true, deepLink,
    'Your payment was successful! Returning you to AutiEase now...',
    'Payment Successful'));
});

app.get('/api/v1/payment/return/failure/:basket_id?', async (req, res) => {
  const payload = req.query || {};
  const basketId = normalizeValue(req.params.basket_id || payload.basket_id || payload.BASKET_ID);

  if (basketId) {
    try {
      // SafePay sandbox has a redirect bug: once payment is captured, reloading the checkout
      // widget fails with "session is no longer valid" and redirects the user to the failure/cancel URL.
      // We must double-check with SafePay's API first to verify if it was actually PAID.
      let trackerToken;
      const checkoutSessionDoc = await db.collection('checkout_sessions').doc(basketId).get();
      if (checkoutSessionDoc.exists) {
        const checkoutSession = checkoutSessionDoc.data() || {};
        trackerToken = checkoutSession.safepayBeacon;
      }

      if (trackerToken) {
        const gatewayVerification = await verifyTransactionWithGateway(trackerToken);
        if (gatewayVerification.verified) {
          console.log(`Failure redirect intercepted for basket ${basketId}: SafePay reports PAID! Treating as successful payment.`);
          const transactionId = gatewayVerification.payload?.data?.token || trackerToken;
          await activateSubscription(basketId, transactionId, 'failure_redirect_doublecheck', gatewayVerification.payload);

          // Return success HTML page since the payment was actually successful
          const deepLink = `autiease://payment-result?status=success&basket_id=${encodeURIComponent(basketId)}`;
          return res.send(buildDeepLinkPage(true, deepLink,
            'Your payment was successful! Returning you to AutiEase now...',
            'Payment Successful'));
        } else {
          console.log(`Failure redirect verified for basket ${basketId}: SafePay reports status as not PAID.`);
        }
      }

      // If gateway check did not confirm success, proceed with failure marking
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

  // Chrome on Android ignores server-side redirects to custom schemes (autiease://).
  // Must serve an HTML page that uses JavaScript window.location.href to trigger the deep link.
  const deepLink = `autiease://payment-result?status=failure&basket_id=${encodeURIComponent(basketId || '')}`;
  res.send(buildDeepLinkPage(false, deepLink,
    'Your payment was not completed. Tap below to return to AutiEase.',
    'Payment Not Completed'));
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
// Enforces: Rs.500 minimum, 3-day cooldown, sufficient balance — all in a Firestore transaction
app.post('/api/v1/therapist/withdraw', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { amount, paymentMethod, accountDetails } = req.body || {};

    if (!amount || !paymentMethod || !accountDetails) {
      return jsonError(res, 400, 'amount, paymentMethod, and accountDetails are required');
    }

    const parsedWithdrawAmount = parseAmount(amount);
    if (parsedWithdrawAmount < 500) {
      return jsonError(res, 400, 'Minimum withdrawal amount is Rs. 500');
    }

    // Enforce 3-day cooldown: check for any non-rejected withdrawal in the past 3 days
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
    const recentWithdrawals = await db
      .collection('withdrawal_requests')
      .where('therapistId', '==', uid)
      .where('status', 'in', ['pending', 'paid'])
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(threeDaysAgo))
      .limit(1)
      .get();
    if (!recentWithdrawals.empty) {
      return jsonError(res, 429, 'You must wait 3 days between withdrawal requests. Please wait for your current request to be processed.');
    }

    const therapistRef = db.collection('therapist_profiles').doc(uid);

    // Use Firestore transaction to atomically check balance and deduct
    const txnResult = await db.runTransaction(async (txn) => {
      const therapistSnap = await txn.get(therapistRef);
      if (!therapistSnap.exists) {
        throw new Error('Therapist profile not found');
      }
      const therapistData = therapistSnap.data() || {};
      const walletBalance = parseAmount(therapistData.walletBalance);

      if (walletBalance < parsedWithdrawAmount) {
        throw new Error(`Insufficient balance. Available: Rs. ${walletBalance.toFixed(0)}`);
      }

      const txnId = `withdraw_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;
      const withdrawalRef = db.collection('withdrawal_requests').doc(txnId);
      const earningsRef = db.collection('therapist_earnings').doc(txnId);

      txn.set(withdrawalRef, {
        therapistId: uid,
        therapistName: therapistData.displayName || 'Therapist',
        amount: parsedWithdrawAmount,
        paymentMethod,
        accountDetails,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      txn.set(earningsRef, {
        therapistId: uid,
        amount: parsedWithdrawAmount,
        type: 'withdrawal',
        paymentMethod,
        accountDetails,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      txn.set(therapistRef, {
        walletBalance: admin.firestore.FieldValue.increment(-parsedWithdrawAmount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return { txnId, remainingBalance: walletBalance - parsedWithdrawAmount };
    });

    return res.status(200).json({ success: true, remainingBalance: txnResult.remainingBalance });
  } catch (error) {
    const errMsg = error?.message || String(error);
    console.error('Withdrawal failed:', errMsg);
    // Surface friendly messages for balance/profile errors
    if (errMsg.includes('Insufficient') || errMsg.includes('not found') || errMsg.includes('Rs.')) {
      return jsonError(res, 400, errMsg);
    }
    return jsonError(res, 500, 'Unable to request withdrawal');
  }
});

// Admin resolve withdrawal request endpoint
// Requires admin Firebase Auth token with admin custom claim (role==='admin')
app.post('/api/v1/admin/withdraw/resolve', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { requestId, status, adminNotes } = req.body || {};

    if (!requestId || !status) {
      return jsonError(res, 400, 'requestId and status are required');
    }
    if (!['paid', 'rejected'].includes(status)) {
      return jsonError(res, 400, 'status must be either paid or rejected');
    }

    // Verify admin role from Firestore (since custom claims may not always be set)
    const adminDoc = await db.collection('users').doc(uid).get();
    const adminData = adminDoc.data() || {};
    if (!adminDoc.exists || adminData.role !== 'admin') {
      return jsonError(res, 403, 'Admin access required');
    }

    const requestRef = db.collection('withdrawal_requests').doc(requestId);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) {
      return jsonError(res, 404, 'Withdrawal request not found');
    }
    const requestData = requestSnap.data() || {};
    if (requestData.status !== 'pending') {
      return jsonError(res, 409, `Withdrawal request is already ${requestData.status}`);
    }

    const therapistId = normalizeValue(requestData.therapistId);
    const amount = parseAmount(requestData.amount);

    await db.runTransaction(async (txn) => {
      // Perform all reads first (Firestore transactions require all reads to precede writes)
      const earningsSnap = await txn.get(db.collection('therapist_earnings').doc(requestId));

      // Update withdrawal request
      txn.set(requestRef, {
        status,
        adminNotes: adminNotes || null,
        resolvedBy: uid,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Update therapist_earnings matching document if it exists
      if (earningsSnap.exists) {
        txn.set(earningsSnap.ref, {
          status,
          adminNotes: adminNotes || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // If rejected, refund balance back to therapist wallet
      if (status === 'rejected' && therapistId && amount > 0) {
        const therapistRef = db.collection('therapist_profiles').doc(therapistId);
        txn.set(therapistRef, {
          walletBalance: admin.firestore.FieldValue.increment(amount),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // Write admin audit log
      txn.set(db.collection('admin_audit_logs').doc(), {
        action: `withdrawal_${status}`,
        adminId: uid,
        targetId: requestId,
        targetType: 'withdrawal_request',
        metadata: { amount, therapistId, adminNotes: adminNotes || null },
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return res.status(200).json({ success: true, status });
  } catch (error) {
    console.error('Resolve withdrawal failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to resolve withdrawal request');
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
  console.log(`AutiEase SafePay payment backend running on port ${port} [${safepayConfig.environment}]`);
});
