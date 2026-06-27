import 'dart:async';
import 'package:flutter/foundation.dart';

/// Represents the result delivered by the autiease://payment-result deep link.
class PaymentDeepLinkResult {
  const PaymentDeepLinkResult({
    required this.status,
    required this.basketId,
  });

  /// 'success' or 'failure'
  final String status;
  final String basketId;

  bool get isSuccess => status.toLowerCase() == 'success';
}

/// A singleton that receives payment deep link events from the app router
/// (via [onUnknownRoute] in MaterialApp) and broadcasts them to listeners.
///
/// The deep link scheme is:
///   autiease://payment-result?status=success&basket_id=...
/// which Android delivers to Flutter as a route push:
///   /?status=success&basket_id=...
/// (because Android treats "payment-result" as the hostname of the custom URI).
class PaymentDeepLinkService {
  PaymentDeepLinkService._();
  static final PaymentDeepLinkService instance = PaymentDeepLinkService._();

  final StreamController<PaymentDeepLinkResult> _controller =
      StreamController<PaymentDeepLinkResult>.broadcast();

  /// Subscribe to payment deep link results.
  Stream<PaymentDeepLinkResult> get results => _controller.stream;

  /// Called from the app's [onUnknownRoute] handler in [MaterialApp].
  /// Returns true if the route was a payment deep link and was handled.
  bool tryHandleRoute(String routeName) {
    // Android delivers autiease://payment-result?status=X&basket_id=Y as
    // the Flutter route "/?status=X&basket_id=Y" (host becomes invisible,
    // path "/" is the root, query string carries the params).
    Uri uri;
    try {
      // Routes arrive without a scheme — prepend one so Uri.parse works.
      uri = Uri.parse('autiease:$routeName');
    } catch (_) {
      return false;
    }

    final status = uri.queryParameters['status'];
    final basketId = uri.queryParameters['basket_id'] ?? '';

    if (status == null || (status != 'success' && status != 'failure')) {
      return false;
    }

    debugPrint(
      'PaymentDeepLinkService: received payment result '
      'status=$status basket_id=$basketId',
    );
    _controller.add(PaymentDeepLinkResult(status: status, basketId: basketId));
    return true;
  }

  void dispose() {
    _controller.close();
  }
}
