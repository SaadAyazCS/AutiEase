const express = require('express');
const cors = require('cors');
const stripe = require('stripe');
const admin = require('firebase-admin');

const app = express();

function isTruthy(value) {
  if (value == null) {
    return false;
  }
  const normalized = value.toString().trim().toLowerCase();
  return ['1', 'true', 'yes', 'on'].includes(normalized);
}

function parseAllowedOrigins() {
  const raw = (process.env.ALLOWED_ORIGINS || '').trim();
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

  if (projectId) {
    admin.initializeApp({ projectId });
    return;
  }

  admin.initializeApp();
}

function getStripeClient() {
  const secret = process.env.STRIPE_SECRET_KEY;
  if (!secret) {
    throw new Error('Missing STRIPE_SECRET_KEY');
  }
  return stripe(secret);
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

async function getUserDoc(db, uid) {
  const ref = db.collection('users').doc(uid);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    return null;
  }
  return { ref, data: snapshot.data() || {} };
}

async function getOrCreateCustomer(stripeClient, db, uid, email) {
  const userRef = db.collection('users').doc(uid);
  const userDoc = await userRef.get();
  const existingCustomerId = userDoc.data()?.stripeCustomerId;
  if (existingCustomerId) {
    return existingCustomerId;
  }

  const customer = await stripeClient.customers.create({
    email,
    metadata: { userId: uid },
  });

  await userRef.set(
    {
      stripeCustomerId: customer.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return customer.id;
}

async function setUserSubscriptionEntitlements(userId, active) {
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

initFirebaseAdmin();
const db = admin.firestore();
const allowedOrigins = parseAllowedOrigins();
const mockPaymentsEnabled = isTruthy(process.env.MOCK_PAYMENTS);
const stripeClient = mockPaymentsEnabled ? null : getStripeClient();

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

app.get('/health', (_req, res) => {
  res.status(200).json({ ok: true, service: 'autiease-stripe-backend' });
});

app.post(
  '/api/v1/stripe/webhook',
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    try {
      if (mockPaymentsEnabled) {
        return res.status(200).json({ received: true, mock: true });
      }

      const signature = req.headers['stripe-signature'];
      const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
      if (!webhookSecret) {
        return jsonError(res, 500, 'Missing STRIPE_WEBHOOK_SECRET');
      }

      const event = stripeClient.webhooks.constructEvent(req.body, signature, webhookSecret);

      if (event.type === 'checkout.session.completed') {
        const session = event.data.object;
        const userId = session.metadata?.userId;
        const productId = session.metadata?.productId;

        if (userId && productId && session.subscription) {
          await db.collection('subscriptions').doc(session.subscription).set(
            {
              userId,
              productId,
              stripeCustomerId: session.customer,
              stripeSubscriptionId: session.subscription,
              status: 'active',
              cancelAtPeriodEnd: false,
              currentPeriodEnd: null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          await db.collection('users').doc(userId).set(
            {
              subscriptionTier: 'professional-support',
              entitlements: {
                professionalSupport: true,
                chatAccess: true,
              },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      if (
        event.type === 'customer.subscription.updated' ||
        event.type === 'customer.subscription.deleted'
      ) {
        const subscription = event.data.object;
        const subscriptionRef = db.collection('subscriptions').doc(subscription.id);
        const existing = await subscriptionRef.get();
        const userId = existing.data()?.userId;

        await subscriptionRef.set(
          {
            status: subscription.status,
            cancelAtPeriodEnd: subscription.cancel_at_period_end,
            currentPeriodEnd: subscription.current_period_end
              ? admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000)
              : null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        if (userId) {
          const active = subscription.status === 'active' || subscription.status === 'trialing';
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
      }

      return res.status(200).json({ received: true });
    } catch (error) {
      console.error('Webhook processing failed:', error?.message || error);
      return jsonError(res, 400, error?.message || 'Invalid webhook payload');
    }
  },
);

app.use(express.json());

app.post('/api/v1/checkout/session', requireAuth, async (req, res) => {
  try {
    const uid = req.user.uid;
    const { productId, successUrl, cancelUrl } = req.body || {};

    if (!productId || !successUrl || !cancelUrl) {
      return jsonError(res, 400, 'Missing checkout parameters');
    }

    const productSnapshot = await db.collection('subscription_products').doc(productId).get();
    if (!productSnapshot.exists) {
      return jsonError(res, 404, 'Subscription product not found');
    }
    const product = productSnapshot.data() || {};
    if (product.isActive === false) {
      return jsonError(res, 400, 'Subscription product is not active');
    }

    const userDoc = await getUserDoc(db, uid);
    if (!userDoc) {
      return jsonError(res, 404, 'User profile not found');
    }
    const email = (userDoc.data.email || '').toString();
    if (!email) {
      return jsonError(res, 400, 'User email missing');
    }

    if (mockPaymentsEnabled) {
      const subscriptionId = `mock_${uid}`;
      await db.collection('subscriptions').doc(subscriptionId).set(
        {
          userId: uid,
          productId,
          stripeCustomerId: 'mock_customer',
          stripeSubscriptionId: subscriptionId,
          status: 'active',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isMock: true,
        },
        { merge: true },
      );
      await setUserSubscriptionEntitlements(uid, true);

      return res.status(200).json({
        sessionId: `mock_session_${Date.now()}`,
        url: `mock://checkout/success?subscriptionId=${encodeURIComponent(
          subscriptionId,
        )}`,
        mock: true,
      });
    }

    const stripePriceId = product.stripePriceId;
    if (!stripePriceId) {
      return jsonError(res, 400, 'Product missing stripePriceId');
    }

    const customerId = await getOrCreateCustomer(stripeClient, db, uid, email);

    const session = await stripeClient.checkout.sessions.create({
      mode: 'subscription',
      customer: customerId,
      success_url: successUrl,
      cancel_url: cancelUrl,
      line_items: [{ price: stripePriceId, quantity: 1 }],
      metadata: {
        userId: uid,
        productId,
      },
    });

    return res.status(200).json({
      sessionId: session.id,
      url: session.url,
    });
  } catch (error) {
    console.error('Checkout session failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to create checkout session');
  }
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
    if (subscription.userId !== uid) {
      return jsonError(res, 403, 'Cannot cancel another user subscription');
    }

    if (mockPaymentsEnabled || subscription.isMock === true) {
      await subscriptionRef.set(
        {
          cancelAtPeriodEnd: true,
          status: 'active',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          isMock: true,
        },
        { merge: true },
      );
      return res.status(200).json({ status: 'cancel_scheduled', mock: true });
    }

    await stripeClient.subscriptions.update(subscription.stripeSubscriptionId, {
      cancel_at_period_end: true,
    });

    await subscriptionRef.set(
      {
        cancelAtPeriodEnd: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({ status: 'cancel_scheduled' });
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
    if (subscription.userId !== uid) {
      return jsonError(res, 403, 'Cannot reactivate another user subscription');
    }

    if (mockPaymentsEnabled || subscription.isMock === true) {
      await subscriptionRef.set(
        {
          cancelAtPeriodEnd: false,
          status: 'active',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          isMock: true,
        },
        { merge: true },
      );
      await setUserSubscriptionEntitlements(uid, true);
      return res.status(200).json({ status: 'reactivated', mock: true });
    }

    await stripeClient.subscriptions.update(subscription.stripeSubscriptionId, {
      cancel_at_period_end: false,
    });

    await subscriptionRef.set(
      {
        cancelAtPeriodEnd: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({ status: 'reactivated' });
  } catch (error) {
    console.error('Reactivate subscription failed:', error?.message || error);
    return jsonError(res, 500, 'Unable to reactivate subscription');
  }
});

const port = Number.parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => {
  console.log(`AutiEase Stripe backend running on port ${port}`);
});
