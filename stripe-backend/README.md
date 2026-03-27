# AutiEase Stripe Backend

External backend for Stripe billing when Firebase project runs on Spark.

## Endpoints
- `GET /health`
- `POST /api/v1/checkout/session`
- `POST /api/v1/subscription/cancel`
- `POST /api/v1/subscription/reactivate`
- `POST /api/v1/stripe/webhook`

## Required env vars
- `FIREBASE_PROJECT_ID=autiease-fyp-2026`
- `STRIPE_SECRET_KEY=...`
- `STRIPE_WEBHOOK_SECRET=...`
- One Firebase Admin auth mode:
  - `FIREBASE_SERVICE_ACCOUNT_JSON={...}`
  - or `GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json`

Optional:
- `ALLOWED_ORIGINS=https://your-web-origin.example.com`
- `MOCK_PAYMENTS=true` (simulate successful subscription without live Stripe)

## Local run
1. `npm install`
2. Set env vars
3. `npm start`

Health check:
- `http://localhost:8080/health`

## Deploy presets included
- `render.yaml`
- `railway.json`
- `fly.toml`
- `Dockerfile`
