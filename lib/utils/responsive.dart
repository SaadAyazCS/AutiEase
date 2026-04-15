import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class AppResponsive {
  AppResponsive._(this._size);

  final Size _size;

  static const Size designSize = Size(393, 852);

  factory AppResponsive.of(BuildContext context) {
    return AppResponsive._(MediaQuery.sizeOf(context));
  }

  double get screenWidth => _size.width;
  double get screenHeight => _size.height;

  double get widthScale =>
      (screenWidth / designSize.width).clamp(0.82, 1.35).toDouble();

  double get heightScale =>
      (screenHeight / designSize.height).clamp(0.82, 1.35).toDouble();

  double get fontScale => math.min(widthScale, heightScale);

  double w(num value) => value.toDouble() * widthScale;
  double h(num value) => value.toDouble() * heightScale;

  double sp(num value, {double min = 0, double max = double.infinity}) {
    return (value.toDouble() * fontScale).clamp(min, max).toDouble();
  }

  bool get isTablet => screenWidth >= 700;
}

extension ResponsiveBuildContext on BuildContext {
  AppResponsive get responsive => AppResponsive.of(this);
}
