class AppRuntimeConfig {
  AppRuntimeConfig._();

  static const paymentBackendBaseUrl = String.fromEnvironment(
    'PAYMENT_BACKEND_BASE_URL',
    defaultValue: '',
  );

  static const paymentSuccessUrl = String.fromEnvironment(
    'PAYMENT_SUCCESS_URL',
    defaultValue: 'https://autiease.app/payment/success',
  );

  static const paymentCancelUrl = String.fromEnvironment(
    'PAYMENT_CANCEL_URL',
    defaultValue: 'https://autiease.app/payment/cancel',
  );

  static const bypassProSupportPaywall = bool.fromEnvironment(
    'BYPASS_PRO_SUPPORT_PAYWALL',
    defaultValue: false,
  );
}
