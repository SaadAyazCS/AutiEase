import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/wave_background.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_widgets.dart';
import 'login_screen.dart';
import 'admin_dashboard_screen.dart';
import '../navigation/session_navigation.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isResending = false;
  bool _isCheckingVerification = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _checkAdminBypass();
  }

  Future<void> _checkAdminBypass() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = user.email?.toLowerCase().trim() ?? '';
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final role = doc.data()?['role']?.toString();
      if (email.contains('admin') || role == 'admin') {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            fadeSessionRoute(const AdminDashboardScreen()),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendEmail() async {
    if (!_canResend) return;

    setState(() => _isResending = true);

    final result = await _firebaseService.resendVerificationEmail();
    if (!mounted) {
      return;
    }

    setState(() => _isResending = false);

    if (result['success']) {
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (result['message'] ?? 'Verification email sent!').toString(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _continueAfterVerification() async {
    if (_firebaseService.currentUser == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please log in again.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      _goToLogin();
      return;
    }

    setState(() => _isCheckingVerification = true);

    final isVerified = await _firebaseService.checkEmailVerified();
    if (!mounted) {
      return;
    }

    if (!isVerified) {
      setState(() => _isCheckingVerification = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email is not verified yet. Check your inbox and spam.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isCheckingVerification = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email verified. Please log in to continue.'),
        backgroundColor: Colors.green,
      ),
    );
    await _goToLogin();
  }

  Future<void> _goToLogin() async {
    // Clear the verification session before returning to login.
    await _firebaseService.logout();
    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final r = context.responsive;

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
              clipper: WaveClipper(),
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
              clipper: BottomWaveClipper(),
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
              painter: TrianglePainter(color: AppColors.red),
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: Column(
                            children: [
                              SizedBox(height: r.h(10)),
                              // Logo at the top
                              const LogoWidget(size: 150),
                              
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                  // Email Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 50,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Title
                  const Text(
                    'Verify Your Email',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  const Text(
                    'We have sent a verification link to',
                    style: TextStyle(fontSize: 16, color: Color.fromARGB(255, 0, 0, 0)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.email,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color.fromARGB(255, 0, 0, 0),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please check your inbox/spam folder and click on the verification link to complete your registration.',
                    style: TextStyle(fontSize: 14, color: Color.fromARGB(255, 0, 0, 0)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed:
                          _isCheckingVerification ? null : _continueAfterVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: _isCheckingVerification
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryBlue,
                              ),
                            )
                          : const Text(
                              "I've Verified My Email",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Go to Login Button
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.orange, AppColors.orangeDark],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.orangeDark.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _goToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Go to Login',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Resend Email
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Didn't receive the email? ",
                        style: TextStyle(color: AppColors.textGrey),
                      ),
                      GestureDetector(
                        onTap: _canResend && !_isResending
                            ? _resendEmail
                            : null,
                        child: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryBlue,
                                ),
                              )
                            : Text(
                                _canResend
                                    ? 'Resend'
                                    : 'Resend in ${_resendCooldown}s',
                                style: TextStyle(
                                  color: _canResend
                                      ? AppColors.primaryBlue
                                      : AppColors.textGrey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                                  ],
                                ),
                              ),
                              SizedBox(height: r.h(100)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
