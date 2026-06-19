import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/responsive.dart';

/// Bottom wave + accent shapes matching [FigmaModuleScaffold] (Learn tab and modules).
///
/// Place with [Positioned] `left: 0, right: 0, bottom: 0` in a [Stack], or at the bottom
/// of a full-width parent. Hides when the keyboard is open.
class ModuleBottomWaveLayer extends StatelessWidget {
  const ModuleBottomWaveLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ClipPath(
            clipper: ModuleBottomWaveClipper(),
            child: Container(
              height: r.h(150),
              width: double.infinity,
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
              painter: ModuleBottomWaveTrianglePainter(color: AppColors.red),
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
    );
  }
}

class ModuleBottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, 60);

    final firstControlPoint = Offset(size.width / 4, 0);
    final firstEndPoint = Offset(size.width / 2, 40);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    final secondControlPoint = Offset(size.width * 3 / 4, 80);
    final secondEndPoint = Offset(size.width, 30);
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

class ModuleBottomWaveTrianglePainter extends CustomPainter {
  const ModuleBottomWaveTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
