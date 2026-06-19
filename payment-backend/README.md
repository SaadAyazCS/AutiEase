# AutiEase Payment Backend (SafePay)

External payment backend for AutiEase subscription billing, utilizing the SafePay payment gateway (Pakistan).

## Endpoints
- `GET /health`
- `POST /api/v1/checkout/session` (Creates SafePay order, returns checkout URL)
- `POST /api/v1/checkout/status` (Returns current subscription status for a therapist)
- `POST /api/v1/payment/webhook` (Handles SafePay webhook events — HMAC verified)
- `POST /api/v1/subscription/cancel` (Sets subscription cancelScheduled)
- `POST /api/v1/subscription/reactivate` (Re-enables active billing status)
- `POST /api/v1/subscription/reconcile-expired` (Triggers expiry sweep manually)
- `POST /api/v1/therapist/withdraw` (Therapist wallet withdrawal request — 3-day cooldown enforced)
- `POST /api/v1/admin/withdraw/resolve` (Admin: mark withdrawal as paid or rejected)
- `GET /api/v1/payment/return/success` (Landing success page)
- `GET /api/v1/payment/return/failure` (Landing failure page)

## Configuration Env Vars
- `PORT`: Port to run the server on (default: `8080`)
- `FIREBASE_PROJECT_ID`: Firebase project ID
- `SAFEPAY_ENVIRONMENT`: `sandbox` (testing) or `production` (live)
- `SAFEPAY_API_KEY`: API key from SafePay Dashboard → Credentials
- `SAFEPAY_SECRET_KEY`: Secret key from SafePay Dashboard → Credentials
- `SAFEPAY_WEBHOOK_SECRET`: Base64-encoded webhook secret from SafePay Dashboard → Webhooks
- `BACKEND_PUBLIC_BASE_URL`: Full public URL of this backend (e.g. `https://autiease.onrender.com`)
- `PAYMENTS_MOCK_MODE`: If `true`, bypasses SafePay API calls and activates subscription in Firestore instantly

## Fee Structure
- **Dynamic SafePay fee**: 2.9% + Rs.30 (credit/debit cards / international)
- **Platform revenue**: 7% of (gross - SafePay fee)
- **Therapist net**: gross - SafePay fee - 7% platform fee

## Local Run
1. `npm install`
2. Copy `.env.example` → `.env` and fill in your credentials
3. `npm start`
