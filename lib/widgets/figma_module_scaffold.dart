import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive.dart';
import '../utils/app_colors.dart';

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
    final contentBottomInset = r.h(96);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
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
                      height: r.h(112),
                      width: double.infinity,
                      padding:
                          EdgeInsets.fromLTRB(r.w(8), r.h(8), r.w(16), r.h(8)),
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
                  child: Padding(
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
            // Wave and decor shapes moved to the end of Stack to appear ON TOP of content
            Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  ClipPath(
                    clipper: _BottomWaveClipper(),
                    child: Container(
                      height: r.h(150),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.lightBlue, AppColors.primaryBlue],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: r.h(34),
                    left: r.w(44),
                    child: Container(
                      width: r.w(20),
                      height: r.w(20),
                      color: AppColors.yellow,
                    ),
                  ),
                  Positioned(
                    bottom: r.h(54),
                    left: r.w(100),
                    child: Icon(
                      Icons.star,
                      color: AppColors.pink,
                      size: r.sp(24, min: 18, max: 28),
                    ),
                  ),
                  Positioned(
                    bottom: r.h(20),
                    right: r.w(152),
                    child: CustomPaint(
                      size: Size(r.w(20), r.w(20)),
                      painter: _TrianglePainter(color: AppColors.red),
                    ),
                  ),
                  Positioned(
                    bottom: r.h(10),
                    right: r.w(44),
                    child: Container(
                      width: r.w(16),
                      height: r.w(16),
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.moveTo(0, 60);

    var firstControlPoint = Offset(size.width / 4, 0);
    var firstEndPoint = Offset(size.width / 2, 40);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 3 / 4, 80);
    var secondEndPoint = Offset(size.width, 30);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    var paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
