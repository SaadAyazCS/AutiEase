import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../services/firebase_service.dart';
import 'parent_terms_screen.dart';
import 'login_screen.dart';
import 'child_profile_screen.dart';
import 'email_verification_screen.dart';
import 'parent_home_screen.dart';
import '../utils/responsive.dart';

class ParentSignupScreen extends StatefulWidget {
  final String? firstName;
  final String? lastName;
  final String? email;

  const ParentSignupScreen({
    super.key,
    this.firstName,
    this.lastName,
    this.email,
  });

  @override
  State<ParentSignupScreen> createState() => _ParentSignupScreenState();
}

class _ParentSignupScreenState extends State<ParentSignupScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  late bool _agreeTerms;
  late bool _isLoading;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.firstName ?? '');
    _lastNameController = TextEditingController(text: widget.lastName ?? '');
    _emailController = TextEditingController(text: widget.email ?? '');
    _agreeTerms = false;
    _isLoading = false;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();

      // No network at all
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }

      // Real internet check
      final lookup = await InternetAddress.lookup('google.com');
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleSignup() async {
    // ✅ Internet check FIRST
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

    // Basic empty validation
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Validate email format
    if (!_isValidEmail(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Validate phone format
    if (!_isValidPhoneNumber(_phoneController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number (10-15 digits)'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Validate password strength
    final passwordError = _validatePassword(_passwordController.text);
    if (passwordError.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passwordError),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Terms check
    if (!_agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to Terms and Conditions'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Collect child profile info (childName + supportAreas)
    final childProfileResult = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChildProfileScreen(
              firstName: _firstNameController.text.trim(),
              lastName: _lastNameController.text.trim(),
              email: _emailController.text.trim(),
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    if (!mounted) return;

    if (childProfileResult == null) {
      // user backed out
      return;
    }

    // ✅ MUST match ChildProfileScreen pop keys
    final String? childName = childProfileResult['childName'];
    final dynamic supportArea = childProfileResult['SupportArea'];

    if (childName == null || childName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Child name is missing'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (supportArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support areas are missing'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _firebaseService.registerParentWithChild(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        childName: childName.trim(),
        supportArea: List<String>.from(supportArea),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final currentUser = _firebaseService.currentUser;

        final bool isGoogleProvider =
            currentUser != null &&
            currentUser.providerData.any((p) => p.providerId == 'google.com');

        if (isGoogleProvider) {
          if (!mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const ParentHomeScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
              transitionDuration: const Duration(milliseconds: 500),
            ),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
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
            (route) => false,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Registration failed'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
    );
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhoneNumber(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 10 || digitsOnly.length > 15) return false;
    final phoneRegex = RegExp(r'^[+]?[\d\s\-()]+$');
    return phoneRegex.hasMatch(phone);
  }

  String _validatePassword(String password) {
    if (password.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number for strong password';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isEmailReadOnly =
        _firebaseService.currentUser?.providerData.any(
          (provider) => provider.providerId == 'google.com',
        ) ??
        false;

    return Scaffold(
      backgroundColor: const Color(0xFFA9DCF5),
      body: Stack(
        children: [
          // Top blue curved background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: screenHeight * 0.12,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryBlue, AppColors.lightBlue],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
            ),
          ),

          // Bottom wave
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomWave()),

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
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.08),

                  // White form container
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: r.w(24)),
                    padding: EdgeInsets.symmetric(
                      horizontal: r.w(24),
                      vertical: r.h(30),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(r.w(24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Parent First Name'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(_firstNameController),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Parent Last Name'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(_lastNameController),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Parent Email'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(
                          _emailController,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: isEmailReadOnly,
                        ),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Parent Phone Number'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(
                          _phoneController,
                          keyboardType: TextInputType.phone,
                        ),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Password'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(_passwordController, obscureText: true),
                        SizedBox(height: r.h(16)),

                        Row(
                          children: [
                            SizedBox(
                              width: r.w(24),
                              height: r.w(24),
                              child: Checkbox(
                                value: _agreeTerms,
                                onChanged: (value) {
                                  setState(() => _agreeTerms = value ?? false);
                                },
                                activeColor: AppColors.primaryBlue,
                                side: const BorderSide(
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ),
                            SizedBox(width: r.w(8)),
                            Flexible(
                              child: Wrap(
                                children: [
                                  Text(
                                    'Agree with ',
                                    style: TextStyle(
                                      color: Color(0xFF2A364E),
                                      fontSize: r.sp(15, min: 13, max: 18),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ParentTermsScreen(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Terms and Conditions',
                                      style: TextStyle(
                                        color: Color(0xFF2F89FC),
                                        fontSize: r.sp(15, min: 13, max: 18),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: r.h(24)),

                        Container(
                          width: double.infinity,
                          height: r.h(50),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8D20),
                            borderRadius: BorderRadius.circular(r.w(20)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.24),
                                blurRadius: r.w(6),
                                offset: Offset(0, r.h(4)),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(r.w(20)),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: r.w(24),
                                    height: r.w(24),
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF0B1421),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Sign up',
                                    style: TextStyle(
                                      color: Color(0xFF0B1421),
                                      fontSize: r.sp(24, min: 18, max: 28),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),

                        SizedBox(height: r.h(16)),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: TextStyle(
                                color: Color(0xFF0F1A2F),
                                fontSize: r.sp(16, min: 14, max: 18),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                  (route) => false,
                                );
                              },
                              child: Text(
                                'Login',
                                style: TextStyle(
                                  color: Color(0xFF2F89FC),
                                  fontWeight: FontWeight.w600,
                                  fontSize: r.sp(16, min: 14, max: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: r.h(150)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    final r = context.responsive;
    return Text(
      text,
      style: TextStyle(
        fontSize: r.sp(23, min: 18, max: 26),
        fontWeight: FontWeight.w500,
        color: const Color(0xFF1A2543),
      ),
    );
  }

  // ✅ UPDATED: readOnly now changes background properly (no fillColor bug)
  Widget _buildTextField(
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool readOnly = false,
  }) {
    final r = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? const Color(0xFFE8EDF3) : AppColors.white,
        borderRadius: BorderRadius.circular(r.w(16)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.18),
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        readOnly: readOnly,
        style: TextStyle(
          fontSize: r.sp(18, min: 14, max: 20),
          color: Color(0xFF1A2543),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: r.w(18),
            vertical: r.h(15),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomWave() {
    return ClipPath(
      clipper: BottomWaveClipper(),
      child: Container(
        height: context.responsive.h(120),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.lightBlue, AppColors.primaryBlue],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.moveTo(0, 50);

    var firstControlPoint = Offset(size.width / 4, 0);
    var firstEndPoint = Offset(size.width / 2, 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 3 / 4, 60);
    var secondEndPoint = Offset(size.width, 20);
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

class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

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
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
