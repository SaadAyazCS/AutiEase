import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/wave_background.dart';
import '../services/firebase_service.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/password_input_field.dart';
import 'therapist_terms_screen.dart';
import 'login_screen.dart';
import 'email_verification_screen.dart';
import 'therapist_home_screen.dart';

class TherapistSignupScreen extends StatefulWidget {
  final String? firstName;
  final String? lastName;
  final String? email;

  const TherapistSignupScreen({
    super.key,
    this.firstName,
    this.lastName,
    this.email,
  });

  @override
  State<TherapistSignupScreen> createState() => _TherapistSignupScreenState();
}

class _TherapistSignupScreenState extends State<TherapistSignupScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  PhoneCountry _selectedCountry = kSupportedCountries.first;

  bool _agreeTerms = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.firstName ?? '');
    _lastNameController = TextEditingController(text: widget.lastName ?? '');
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// ✅ Internet check
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

    final fullPhone = buildFullPhoneNumber(_selectedCountry, _phoneController.text.trim());

    // Basic empty validation
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
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

    // Validate phone number format (validating fullPhone which has dial code + local part)
    if (!_isValidPhoneNumber(fullPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Validate password strength
    final String passwordError = _validatePassword(_passwordController.text);
    if (passwordError.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passwordError),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Confirm password check
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (!_agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to Terms and Conditions'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _firebaseService.registerTherapist(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: fullPhone,
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final currentUser = _firebaseService.currentUser;
        final bool isGoogleProvider =
            currentUser != null &&
            currentUser.providerData.any((p) => p.providerId == 'google.com');

        if (isGoogleProvider) {
          Navigator.pushAndRemoveUntil(
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
            content: Text(
              result['message'] ?? 'Registration failed. Please try again.',
            ),
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
    if (password.length > 100) {
      return 'Password must not exceed 100 characters';
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
    if (!password.contains(RegExp(r'[^a-zA-Z0-9]'))) {
      return 'Password must contain at least one special character (e.g. !@#\$%^&*)';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final bool isEmailReadOnly =
        _firebaseService.currentUser?.providerData.any(
          (provider) => provider.providerId == 'google.com',
        ) ??
        false;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top blue curved header (small bar — same as Parent Signup)
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
          if (!isKeyboardOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: BottomWaveClipper(),
                child: Container(
                  height: 130,
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
          if (!isKeyboardOpen) ...[
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
          ],

          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.08),

                  // Form container
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: r.w(24)),
                    padding: EdgeInsets.symmetric(
                      horizontal: r.w(24),
                      vertical: r.h(10),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(r.w(24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Therapist First Name'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(_firstNameController),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Therapist Last Name'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(_lastNameController),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Therapist Email'),
                        SizedBox(height: r.h(8)),
                        _buildTextField(
                          _emailController,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: isEmailReadOnly,
                        ),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Therapist Phone Number'),
                        SizedBox(height: r.h(8)),
                        PhoneInputField(
                          localController: _phoneController,
                          initialCountry: _selectedCountry,
                          onCountryChanged: (country) {
                            setState(() => _selectedCountry = country);
                          },
                        ),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Password'),
                        SizedBox(height: r.h(8)),
                        PasswordInputField(
                          controller: _passwordController,
                          showStrength: true,
                        ),
                        SizedBox(height: r.h(16)),

                        _buildLabel('Confirm Password'),
                        SizedBox(height: r.h(8)),
                        PasswordInputField(
                          controller: _confirmPasswordController,
                          hintText: 'Confirm Password',
                          matchController: _passwordController,
                        ),
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
                                      color: const Color(0xFF2A364E),
                                      fontSize: r.sp(15, min: 13, max: 18),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const TherapistTermsScreen(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Terms and Conditions',
                                      style: TextStyle(
                                        color: const Color(0xFF2F89FC),
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
                                    child: const CircularProgressIndicator(
                                      color: Color(0xFF0B1421),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Sign up',
                                    style: TextStyle(
                                      color: const Color(0xFF0B1421),
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
                                color: const Color(0xFF0F1A2F),
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
                                  color: const Color(0xFF2F89FC),
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

                  SizedBox(height: r.h(130)),
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
        fontSize: r.sp(18, min: 14, max: 22),
        fontWeight: FontWeight.w500,
        color: const Color(0xFF1A2543),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool readOnly = false,
  }) {
    final r = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? const Color(0xFFE8EDF3) : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(r.w(16)),
        border: Border.all(color: const Color(0xFFD2DCE6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB0C4DE).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
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
          color: const Color(0xFF1A2543),
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
    );
  }

}
