# Auth Regression Checklist

Use this checklist before release and after any auth/profile code change.

## Preconditions
- Firebase project is `autiease-fyp-2026`.
- App is installed fresh (`pm clear` or uninstall/reinstall).
- Use **new** test emails for each run.

## Therapist Flow (Strict Verification)
1. Signup therapist with email/password.
2. Confirm app opens `Verify Your Email` screen.
3. Tap `Resend` once.
4. Open the **latest** verification email only.
5. Click verification link and wait for success page.
6. Return to app and tap `I've Verified My Email`.
7. Confirm app redirects to `Login` screen.
8. Login with therapist credentials.
9. Confirm user lands on therapist home.

Pass criteria:
- Unverified therapist cannot pass login.
- Verified therapist can login and access therapist home.

## Parent Flow (Strict Verification)
1. Signup parent with email/password and child profile.
2. Confirm app opens `Verify Your Email` screen.
3. Repeat resend + latest-link verification sequence.
4. Tap `I've Verified My Email`.
5. Confirm app redirects to `Login`.
6. Login with parent credentials.
7. Confirm user lands on parent home.

Pass criteria:
- Unverified parent cannot pass login.
- Verified parent can login and access parent home.

## Backend Data Integrity
For each test account, verify:
- Exactly one Firebase Auth user for the email.
- Exactly one Firestore `users/{uid}` document with matching `uid`.
- `role` matches selected role.
- `status` is `verified` after successful verification/login.
- Therapist has `therapist_profiles/{uid}`.

## Cleanup Rules
- Delete test users from Auth and Firestore together.
- Never rely on email-only Firestore cleanup; always clean by `uid`.

## Backend Cleanup Validation
Run these from `functions/`:

Prerequisites:
- `gcloud auth application-default login`
- PowerShell: `$env:FIREBASE_PROJECT_ID='autiease-fyp-2026'`

1. Cleanup a user by email:
`npm run cleanup:user -- --email <test-email@example.com>`
2. Cleanup a user by uid:
`npm run cleanup:user -- --uid <firebase-auth-uid>`
3. Confirm all checks are true:
- Auth user no longer exists.
- Firestore `users/{uid}` no longer exists.
- Firestore `therapist_profiles/{uid}` no longer exists (if therapist).
- Parent-linked data removed: `child_profiles`, `child_assignments`, `dashboard_snapshots`, `mood_logs`, `activity_progress`.
- Thread data removed: `therapist_threads` and nested `messages`.

## Auth Deletion Bidirectional Trigger Check
1. Delete only `users/{uid}` in Firestore:
- Expected: matching Auth user is removed, plus dependent docs cleanup.
2. Delete only Auth user in Firebase Auth:
- Expected: `users/{uid}` is removed automatically, plus dependent docs cleanup.
