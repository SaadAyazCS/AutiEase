import 'package:flutter/material.dart';

class FigmaHomeShell extends StatelessWidget {
  const FigmaHomeShell({
    super.key,
    required this.title,
    required this.avatar,
    required this.onLogout,
    required this.child,
  });

  final String title;
  final Widget avatar;
  final VoidCallback onLogout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF66CAF5))),
          Positioned(
            top: 96,
            left: 0,
            right: 0,
            bottom: 126,
            child: ClipPath(
              clipper: _HomeMainPanelClipper(),
              child: const ColoredBox(color: Color(0xFFF2F2F2)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 170,
            child: ClipPath(
              clipper: _HomeBottomClipper(),
              child: const ColoredBox(color: Color(0xFF57C1F3)),
            ),
          ),
          const Positioned(
            left: 18,
            bottom: 78,
            child: _DecorSquare(color: Color(0xFFF6E72F), size: 20),
          ),
          const Positioned(
            left: 76,
            bottom: 92,
            child: Icon(Icons.star, size: 20, color: Color(0xFFFF4081)),
          ),
          const Positioned(
            left: 108,
            bottom: 54,
            child: _DecorTriangle(color: Color(0xFFFF5722)),
          ),
          const Positioned(
            right: 32,
            bottom: 50,
            child: _DecorCircle(color: Color(0xFF4CAF50), size: 15),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: onLogout,
                          icon: const Icon(
                            Icons.logout,
                            color: Color(0xFF152748),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            avatar,
                            const SizedBox(height: 6),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 29 / 1.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF223651),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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

class _HomeMainPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 30);
    path.quadraticBezierTo(size.width * 0.18, 4, size.width * 0.42, 28);
    path.quadraticBezierTo(size.width * 0.66, 52, size.width, 14);
    path.lineTo(size.width, size.height - 64);
    path.quadraticBezierTo(
      size.width * 0.88,
      size.height - 6,
      size.width * 0.66,
      size.height - 16,
    );
    path.quadraticBezierTo(
      size.width * 0.40,
      size.height - 24,
      size.width * 0.21,
      size.height - 54,
    );
    path.quadraticBezierTo(0, size.height - 84, 0, size.height - 66);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _HomeBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 56);
    path.quadraticBezierTo(size.width * 0.22, 20, size.width * 0.45, 50);
    path.quadraticBezierTo(size.width * 0.70, 86, size.width, 40);
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
    return CustomPaint(
      size: const Size(18, 18),
      painter: _TrianglePainter(color),
    );
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
