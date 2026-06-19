import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/responsive.dart';
import 'module_bottom_wave_overlay.dart';

class FigmaModuleScaffold extends StatelessWidget {
  const FigmaModuleScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final media = MediaQuery.of(context);
    final isKeyboardOpen = media.viewInsets.bottom > 0;
    final contentBottomInset = isKeyboardOpen ? r.h(16) : r.h(112);
    final headerHeight = isKeyboardOpen ? r.h(68) : r.h(112);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFF67C9F4),
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      height: headerHeight,
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        r.w(8),
                        r.h(8),
                        r.w(16),
                        r.h(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: onBack,
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              size: r.sp(22, min: 18, max: 26),
                              color: const Color(0xFF0F1E38),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: r.sp(34 / 1.5, min: 18, max: 28),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF12213D),
                              ),
                            ),
                          ),
                          trailing ?? SizedBox(width: r.w(34)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.fromLTRB(
                      r.w(16),
                      r.h(12),
                      r.w(16),
                      contentBottomInset,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: r.isTablet ? 460 : double.infinity,
                        ),
                        child: ClipRect(child: child),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!isKeyboardOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: const ModuleBottomWaveLayer(),
              ),
          ],
        ),
      ),
    );
  }
}
