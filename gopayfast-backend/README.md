# AutiEase Payment Backend (GoPayFast)

External payment backend for AutiEase subscription billing, utilizing the Pakistani GoPayFast payment gateway.

## Endpoints
- `GET /health`
- `POST /api/v1/checkout/session` (Initiates session and returns redirect endpoint)
- `GET /api/v1/checkout/redirect/:checkoutId` (Renders automatic POST form to PayFast)
- `POST /api/v1/payment/webhook` (Handles IPN callbacks, hash checking, and updates Firestore)
- `POST /api/v1/subscription/cancel` (Sets subscription cancelScheduled)
- `POST /api/v1/subscription/reactivate` (Re-enables active billing status)
- `POST /api/v1/subscription/reconcile-expired` (Triggers expiry sweep manually)
- `POST /api/v1/therapist/withdraw` (Allows therapists to request a withdrawal from their wallet balance)
- `GET /api/v1/payment/return/success` (Landing success page)
- `GET /api/v1/payment/return/failure` (Landing failure page)

## Configuration Env Vars
- `PORT`: Port to run the server on (default: `8080`)
- `FIREBASE_PROJECT_ID`: Firebase project ID
- `PAYFAST_BASE_URL`: PayFast transaction API endpoint
- `PAYFAST_MERCHANT_ID`: Merchant ID (UAT default: `103`)
- `PAYFAST_SECURED_KEY`: Secured Key provided by PayFast (UAT default: `PzPx6ut-SVay7tCUMqG`)
- `PAYFAST_STRICT_WEBHOOK_VERIFICATION`: Whether to query Inquiry API and verify signature validation hashes
- `PAYMENTS_MOCK_MODE`: If `true`, bypasses UAT redirection and activates subscription in Firestore instantly

## Local Run
1. `npm install`
2. Configure `.env`
3. `npm start`
