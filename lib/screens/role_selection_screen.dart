import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/responsive.dart';
import '../widgets/custom_widgets.dart';
import 'login_screen.dart';
import 'parent_signup_screen.dart';
import 'therapist_signup_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    this.firstName,
    this.lastName,
    this.email,
  });

  final String? firstName;
  final String? lastName;
  final String? email;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final String _resolvedFirstName;
  late final String _resolvedLastName;
  late final String _resolvedEmail;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    final currentUser = FirebaseService().currentUser;
    _resolvedFirstName =
        widget.firstName ?? currentUser?.displayName?.split(' ').first ?? '';
    _resolvedLastName =
        widget.lastName ??
        currentUser?.displayName?.split(' ').skip(1).join(' ') ??
        '';
    _resolvedEmail = widget.email ?? currentUser?.email ?? '';
    _animationController.forward();
    _enforceSessionRouting();
  }

  Future<void> _enforceSessionRouting() async {
    final session = await AppRepositories.auth.resolveSession();
    if (!mounted) {
      return;
    }
    if (session.state == AppSessionState.parent ||
        session.state == AppSessionState.therapist ||
        session.state == AppSessionState.emailVerificationPending) {
      Navigator.pushReplacement(
        context,
        fadeSessionRoute(
          destinationForSession(session, emailFallback: _resolvedEmail),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _selectRole(String role) {
    if (role == 'parent') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ParentSignupScreen(
            firstName: _resolvedFirstName,
            lastName: _resolvedLastName,
            email: _resolvedEmail,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TherapistSignupScreen(
          firstName: _resolvedFirstName,
          lastName: _resolvedLastName,
          email: _resolvedEmail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF66CAF5)),
              ),
              Positioned(
                top: r.h(38),
                left: 0,
                right: 0,
                bottom: r.h(122),
                child: ClipPath(
                  clipper: _RoleMainPanelClipper(),
                  child: const ColoredBox(color: Color(0xFFF2F2F2)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: r.h(170),
                child: ClipPath(
                  clipper: _RoleBottomClipper(),
                  child: const ColoredBox(color: Color(0xFF57C1F3)),
                ),
              ),
              Positioned(
                left: r.w(44),
                bottom: r.h(34),
                child: _DecorSquare(
                  color: const Color(0xFFF6E72F),
                  size: r.w(20),
                ),
              ),
              Positioned(
                left: r.w(100),
                bottom: r.h(54),
                child: Icon(
                  Icons.star,
                  size: r.sp(20, min: 16, max: 24),
                  color: const Color(0xFFFF4081),
                ),
              ),
              Positioned(
                left: r.w(188),
                bottom: r.h(20),
                child: _DecorTriangle(
                  color: const Color(0xFFFF5722),
                  size: r.w(18),
                ),
              ),
              Positioned(
                right: r.w(44),
                bottom: r.h(10),
                child: _DecorCircle(
                  color: const Color(0xFF4CAF50),
                  size: r.w(15),
                ),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: r.h(2),
                      left: r.w(2),
                      child: IconButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.arrow_back,
                          color: Color(0xFF152748),
                          size: r.sp(26, min: 20, max: 30),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      top: r.h(56),
                      bottom: r.h(176),
                      child: LayoutBuilder(
                        builder: (context, contentBox) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: contentBox.maxHeight,
                              ),
                              child: Center(
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LogoWidget(size: r.w(148)),
                                      SizedBox(height: r.h(20)),
                                      Text(
                                        'Welcome! I am',
                                        style: TextStyle(
                                          fontSize: r.sp(34, min: 24, max: 38),
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF223651),
                                        ),
                                      ),
                                      SizedBox(height: r.h(20)),
                                      _RoleChoiceCard(
                                        title: 'Parent & Child',
                                        subtitle: 'Monitor and Guide',
                                        color: const Color(0xFFC6BCDE),
                                        imageAsset:
                                            'assets/images/parent_child.png',
                                        onTap: () => _selectRole('parent'),
                                      ),
                                      SizedBox(height: r.h(16)),
                                      _RoleChoiceCard(
                                        title: 'Therapist',
                                        subtitle: 'Connect and Support',
                                        color: const Color(0xFF91D650),
                                        imageAsset:
                                            'assets/images/therapist.png',
                                        onTap: () => _selectRole('therapist'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.imageAsset,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final String imageAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - r.w(96))
        .clamp(r.w(220), r.w(290))
        .toDouble();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(r.w(12)),
      child: Container(
        width: cardWidth,
        padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(12)),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(r.w(12)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: r.sp(18.5, min: 14, max: 22),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF243656),
              ),
            ),
            SizedBox(height: r.h(7)),
            SizedBox(
              width: r.w(44),
              height: r.w(44),
              child: Image.asset(imageAsset, fit: BoxFit.contain),
            ),
            SizedBox(height: r.h(7)),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: r.sp(14.2, min: 12, max: 18),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2D4B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleMainPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 34);
    path.quadraticBezierTo(size.width * 0.18, 8, size.width * 0.42, 32);
    path.quadraticBezierTo(size.width * 0.66, 56, size.width, 18);
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

class _RoleBottomClipper extends CustomClipper<Path> {
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
  const _DecorTriangle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
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
