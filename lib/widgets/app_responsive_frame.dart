import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppResponsiveFrame extends StatelessWidget {
  const AppResponsiveFrame({super.key, required this.child});

  final Widget child;

  static const double _designWidth = 393;
  static const double _tabletContentWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        if (maxWidth <= 0 ||
            maxHeight <= 0 ||
            maxWidth.isInfinite ||
            maxHeight.isInfinite) {
          return child;
        }

        if (maxWidth < _designWidth) {
          final scale = maxWidth / _designWidth;
          final virtualHeight = math.max(maxHeight, maxHeight / scale);
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Align(
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: _designWidth,
                    height: virtualHeight,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        }

        if (maxWidth >= 700) {
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _tabletContentWidth,
                ),
                child: child,
              ),
            ),
          );
        }

        return child;
      },
    );
  }
}
