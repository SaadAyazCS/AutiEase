import 'package:flutter/material.dart';

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
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFFA9DCF5)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 165,
            child: ClipPath(
              clipper: _FooterWaveClipper(),
              child: const ColoredBox(color: Color(0xFF59BFEF)),
            ),
          ),
          const Positioned(
            left: 50,
            bottom: 138,
            child: _DecorSquare(color: Color(0xFFF6E72F), size: 18),
          ),
          const Positioned(
            left: 105,
            bottom: 150,
            child: Icon(Icons.star, size: 22, color: Color(0xFFFF4081)),
          ),
          const Positioned(
            right: 106,
            bottom: 118,
            child: _DecorTriangle(color: Color(0xFFFF5722)),
          ),
          const Positioned(
            right: 48,
            bottom: 114,
            child: _DecorCircle(color: Color(0xFF4CAF50), size: 16),
          ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  height: 112,
                  width: double.infinity,
                  color: const Color(0xFF67C9F4),
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 22,
                          color: Color(0xFF0F1E38),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 34 / 1.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF12213D),
                          ),
                        ),
                      ),
                      trailing ?? const SizedBox(width: 34),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 76);
    path.quadraticBezierTo(size.width * 0.22, 22, size.width * 0.48, 64);
    path.quadraticBezierTo(size.width * 0.70, 104, size.width, 54);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DecorSquare extends StatelessWidget {
  const _DecorSquare({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, color: color);
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DecorTriangle extends StatelessWidget {
  const _DecorTriangle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(18, 18), painter: _TrianglePainter(color));
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
