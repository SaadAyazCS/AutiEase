import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/custom_widgets.dart';
import '../widgets/wave_background.dart' as wb;
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
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: wb.WaveClipper(),
              child: Container(
                height: screenHeight * 0.35,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryBlue, AppColors.lightBlue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // Bottom wave
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: wb.BottomWaveClipper(),
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.lightBlue, AppColors.primaryBlue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // Decorative shapes
          Positioned(
            bottom: 34,
            left: 44,
            child: Container(width: 20, height: 20, color: AppColors.yellow),
          ),
          Positioned(
            bottom: 54,
            left: 100,
            child: const Icon(Icons.star, color: AppColors.pink, size: 24),
          ),
          Positioned(
            bottom: 20,
            right: 152,
            child: CustomPaint(
              size: const Size(20, 20),
              painter: wb.TrianglePainter(color: AppColors.red),
            ),
          ),
          Positioned(
            bottom: 10,
            right: 44,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: r.h(12),
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
                      color: const Color(0xFF152748),
                      size: r.sp(26, min: 20, max: 30),
                    ),
                  ),
                ),
                Positioned.fill(
                  top: r.h(26),
                  child: LayoutBuilder(
                    builder: (context, contentBox) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: contentBox.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Center(
                              child: FadeTransition(
                                opacity: _fadeAnimation,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    LogoWidget(size: r.w(148)),
                                    SizedBox(height: r.h(80)),
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
                                    Expanded(child: SizedBox(height: r.h(40))),
                                  ],
                                ),
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


