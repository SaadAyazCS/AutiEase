import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/child_mode_lock_controller.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../widgets/wave_background.dart';
import '../widgets/custom_widgets.dart';
import '../services/firebase_service.dart';
import 'forgot_password_screen.dart';
import 'role_selection_screen.dart';
import 'therapist_home_screen.dart';
import 'email_verification_screen.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _showError = false;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
    );
    return emailRegex.hasMatch(email);
  }

  ///  Internet check
  Future<bool> _hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();

      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }

      final lookup = await InternetAddress.lookup('google.com');
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleLogin() async {
    //  Internet check FIRST
    final hasInternet = await _hasInternetConnection();
    if (!mounted) return;

    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please check your network.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _showError = true);
      return;
    }

    if (!_isValidEmail(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The email address is badly formatted')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _showError = false;
    });

    final result = await _firebaseService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      await ChildModeLockController.initialize();
      final session = await AppRepositories.auth.resolveSession();
      if (!mounted) return;
      _navigateForSession(session);
    } else {
      String message = (result['message'] ?? 'Login failed').toString();
      if (result['needsVerification'] == true) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                EmailVerificationScreen(email: _emailController.text.trim()),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.errorRed),
      );
    }
  }

  void _navigateForSession(AppSession session) {
    Navigator.pushReplacement(
      context,
      fadeSessionRoute(
        destinationForSession(
          session,
          emailFallback: _emailController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _handleGoogleLogin() async {
    //  Internet check FIRST
    final hasInternet = await _hasInternetConnection();
    if (!mounted) return;

    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please check your network.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _firebaseService.signInWithGoogle();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      await ChildModeLockController.initialize();
      if (!mounted) return;
      final bool isNewUser = result['isNewUser'] == true;
      final String? userRole = result['role'];

      if (isNewUser || userRole == null) {
        final user = result['user'];
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                RoleSelectionScreen(
                  firstName: user?.displayName?.split(' ').first ?? '',
                  lastName:
                      user?.displayName?.split(' ').skip(1).join(' ') ?? '',
                  email: user?.email ?? '',
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else if (userRole == 'parent') {
        final session = await AppRepositories.auth.resolveSession();
        if (!mounted) return;
        _navigateForSession(session);
      } else if (userRole == 'therapist') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const TherapistHomeScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else {
        final user = result['user'];
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                RoleSelectionScreen(
                  firstName: user?.displayName?.split(' ').first ?? '',
                  lastName:
                      user?.displayName?.split(' ').skip(1).join(' ') ?? '',
                  email: user?.email ?? '',
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result['message'] ?? 'Google sign-in failed').toString(),
          ),
          backgroundColor: const Color.fromARGB(255, 114, 114, 114),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFC6E9FF),
      body: WaveBackground(
        showTopWave: false,
        showBottomWave: false,
        showDecorations: false,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        SizedBox(height: r.h(36)),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: LogoWidget(
                            size: isKeyboardOpen ? r.w(150) : r.w(210),
                          ),
                        ),
                        
                        // This Expanded pushes the blue container to the bottom.
                        // It collapses if there is not enough vertical space.
                        Expanded(child: SizedBox(height: r.h(40))),

                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: double.infinity,
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.only(
                          left: r.w(28),
                          right: r.w(28),
                          top: r.h(34),
                          bottom: isKeyboardOpen
                              ? r.h(20) + bottomInset
                              : r.h(28),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF80CFFF),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(r.w(48)),
                            topRight: Radius.circular(r.w(48)),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_showError)
                                Container(
                                  margin: EdgeInsets.only(bottom: r.h(11)),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: r.w(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Invalid Details!',
                                        style: TextStyle(
                                          color: AppColors.errorRed,
                                          fontSize: r.sp(22, min: 18, max: 24),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: r.h(4)),
                                      Text(
                                        'ReEnter your Credentials',
                                        style: TextStyle(
                                          color: Color(0xFF0E1C33),
                                          fontSize: r.sp(18, min: 14, max: 20),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              CustomTextField(
                                hintText: 'Email',
                                prefixIcon: Icons.account_circle_outlined,
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 16),

                              CustomTextField(
                                hintText: 'Password',
                                prefixIcon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                controller: _passwordController,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppColors.textGrey,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder:
                                            (
                                              context,
                                              animation,
                                              secondaryAnimation,
                                            ) => const ForgotPasswordScreen(),
                                        transitionsBuilder:
                                            (
                                              context,
                                              animation,
                                              secondaryAnimation,
                                              child,
                                            ) {
                                              return SlideTransition(
                                                position:
                                                    Tween<Offset>(
                                                      begin: const Offset(1, 0),
                                                      end: Offset.zero,
                                                    ).animate(
                                                      CurvedAnimation(
                                                        parent: animation,
                                                        curve:
                                                            Curves.easeOutCubic,
                                                      ),
                                                    ),
                                                child: child,
                                              );
                                            },
                                        transitionDuration: const Duration(
                                          milliseconds: 400,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: Color(0xFF0D1425),
                                      fontWeight: FontWeight.w700,
                                      fontSize: r.sp(17, min: 14, max: 20),
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: r.h(10)),

                              CustomButton(
                                text: 'Login',
                                onPressed: _handleLogin,
                                isLoading: _isLoading,
                                backgroundColor: const Color(0xFFFFA96D),
                                textColor: const Color(0xFF0B1421),
                              ),

                              SizedBox(height: r.h(16)),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Don’t have an account? ",
                                    style: TextStyle(
                                      color: Color(0xFF0F1A2F),
                                      fontSize: r.sp(18, min: 14, max: 20),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder:
                                              (
                                                context,
                                                animation,
                                                secondaryAnimation,
                                              ) => const RoleSelectionScreen(),
                                          transitionsBuilder:
                                              (
                                                context,
                                                animation,
                                                secondaryAnimation,
                                                child,
                                              ) {
                                                return SlideTransition(
                                                  position:
                                                      Tween<Offset>(
                                                        begin: const Offset(
                                                          1,
                                                          0,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(
                                                        CurvedAnimation(
                                                          parent: animation,
                                                          curve: Curves
                                                              .easeOutCubic,
                                                        ),
                                                      ),
                                                  child: child,
                                                );
                                              },
                                          transitionDuration: const Duration(
                                            milliseconds: 400,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Signup',
                                      style: TextStyle(
                                        color: Color(0xFF2F89FC),
                                        fontWeight: FontWeight.w600,
                                        fontSize: r.sp(18, min: 14, max: 20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: r.h(24)),

                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(
                                        0xFF0F1A2F,
                                      ).withValues(alpha: 0.48),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: r.w(16),
                                    ),
                                    child: Text(
                                      'Or',
                                      style: TextStyle(
                                        color: Color(0xFF1B1D21),
                                        fontSize: r.sp(26, min: 20, max: 30),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(
                                        0xFF0F1A2F,
                                      ).withValues(alpha: 0.48),
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: r.h(22)),

                              Container(
                                width: double.infinity,
                                height: r.h(50),
                                decoration: BoxDecoration(
                                  color: const Color(0x05FFFFFF),
                                  borderRadius: BorderRadius.circular(r.w(10)),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.40),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: const Color.fromARGB(0, 0, 0, 0),
                                  child: InkWell(
                                    onTap: _isLoading
                                        ? null
                                        : _handleGoogleLogin,
                                    borderRadius: BorderRadius.circular(
                                      r.w(10),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: r.w(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Image.asset(
                                            'assets/images/google_logo.png',
                                            width: r.w(26),
                                            height: r.w(26),
                                            fit: BoxFit.contain,
                                          ),
                                          Expanded(
                                            child: Center(
                                              child: Text(
                                                'Login with Google',
                                                style: TextStyle(
                                                  color: Color.fromRGBO(
                                                    11,
                                                    20,
                                                    33,
                                                    0.60,
                                                  ),
                                                  fontSize: r.sp(
                                                    16,
                                                    min: 14,
                                                    max: 18,
                                                  ),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: r.w(26)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
),
);
}
}
