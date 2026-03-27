# External Stripe Backend (No Firebase Functions)

Use this setup when Firebase project is on Spark and you still need payments.

## Why
- Firebase Functions deploy requires Blaze.
- Stripe secrets must stay on a backend (never in Flutter app).
- This backend keeps Firebase Auth + Firestore on Spark while moving Stripe logic out.

## Backend Location
- Code: `stripe-backend/`
- Entry: `stripe-backend/server.js`
- Deployment presets:
  - `stripe-backend/render.yaml`
  - `stripe-backend/railway.json`
  - `stripe-backend/fly.toml`
  - `stripe-backend/Dockerfile`

## API Endpoints (App-facing)
- `POST /api/v1/checkout/session`
- `POST /api/v1/subscription/cancel`
- `POST /api/v1/subscription/reactivate`
- `POST /api/v1/stripe/webhook` (Stripe only)
- `GET /health`

All app-facing endpoints require:
- `Authorization: Bearer <Firebase ID token>`

## Environment Variables
- `PORT=8080`
- `FIREBASE_PROJECT_ID=autiease-fyp-2026`
- `STRIPE_SECRET_KEY=sk_...`
- `STRIPE_WEBHOOK_SECRET=whsec_...`
- `MOCK_PAYMENTS=true|false` (set `true` to bypass Stripe and simulate successful subscription)
- `ALLOWED_ORIGINS=https://your-web-origin.example.com` (optional)
- One Firebase Admin auth mode:
  - `GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json`
  - or `FIREBASE_SERVICE_ACCOUNT_JSON={...service account json...}`

## Local Run
From `stripe-backend/`:

1. `npm install`
2. Set env vars.
3. `npm start`

Health check:
- `http://localhost:8080/health`

## Mock Payments Mode (No Stripe Account)
Use this when Stripe account is not available in your country yet.

Backend terminal:

```powershell
cd D:\Programming\Personal\autiease\stripe-backend
$env:FIREBASE_PROJECT_ID="autiease-fyp-2026"
$env:GCLOUD_PROJECT="autiease-fyp-2026"
$env:GOOGLE_CLOUD_PROJECT="autiease-fyp-2026"
$env:MOCK_PAYMENTS="true"
$env:STRIPE_SECRET_KEY="sk_test_localdev"
$env:STRIPE_WEBHOOK_SECRET="whsec_localdev"
npm start
```

In mock mode:
- `Start subscription` activates a Firestore subscription directly.
- `Cancel` / `Reactivate` are handled without Stripe.

## Deploy (Render / Railway / Fly)
1. Create a new Node.js web service from `stripe-backend/`.
2. Build command: `npm install`
3. Start command: `npm start`
4. Set all env vars listed above.
5. Copy service URL, for example:
   - `https://autiease-stripe-backend.onrender.com`

## Stripe Webhook Setup
In Stripe Dashboard:
1. Add endpoint:
   - `https://<your-backend-domain>/api/v1/stripe/webhook`
2. Listen to events:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
3. Copy signing secret to `STRIPE_WEBHOOK_SECRET`.

## Flutter App Wiring
Run app with backend URL:

```powershell
flutter run `
  --dart-define=STRIPE_BACKEND_BASE_URL=https://<your-backend-domain> `
  --dart-define=STRIPE_SUCCESS_URL=https://<your-success-page> `
  --dart-define=STRIPE_CANCEL_URL=https://<your-cancel-page>
```

Release build:

```powershell
flutter build apk --release `
  --dart-define=STRIPE_BACKEND_BASE_URL=https://<your-backend-domain> `
  --dart-define=STRIPE_SUCCESS_URL=https://<your-success-page> `
  --dart-define=STRIPE_CANCEL_URL=https://<your-cancel-page>
```

## Firestore Requirements
Keep these collections in Firestore:
- `subscription_products` (must include `stripePriceId`)
- `subscriptions` (managed by webhook/backend)
- `users` (contains `stripeCustomerId`, entitlements)
