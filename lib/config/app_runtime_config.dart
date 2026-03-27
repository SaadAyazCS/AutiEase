class AppRuntimeConfig {
  AppRuntimeConfig._();

  static const stripeBackendBaseUrl = String.fromEnvironment(
    'STRIPE_BACKEND_BASE_URL',
    defaultValue: '',
  );

  static const stripeSuccessUrl = String.fromEnvironment(
    'STRIPE_SUCCESS_URL',
    defaultValue: 'https://autiease.app/success',
  );

  static const stripeCancelUrl = String.fromEnvironment(
    'STRIPE_CANCEL_URL',
    defaultValue: 'https://autiease.app/cancel',
  );

  static const bypassProSupportPaywall = bool.fromEnvironment(
    'BYPASS_PRO_SUPPORT_PAYWALL',
    defaultValue: false,
  );
}
