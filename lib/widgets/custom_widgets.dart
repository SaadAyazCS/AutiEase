import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';

class CustomTextField extends StatelessWidget {
  final String hintText;
  final IconData prefixIcon;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const CustomTextField({
    super.key,
    required this.hintText,
    required this.prefixIcon,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(r.w(30)),
        border: Border.all(color: AppColors.textGrey.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: r.w(10),
            offset: Offset(0, r.h(2)),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(
          color: AppColors.textDark,
          fontSize: r.sp(16, min: 14, max: 18),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: r.sp(16, min: 14, max: 18),
          ),
          prefixIcon: Icon(prefixIcon, color: AppColors.darkBlue),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: r.w(20),
            vertical: r.h(16),
          ),
        ),
      ),
    );
  }
}

class CustomButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      width: double.infinity,
      height: r.h(55),
      decoration: BoxDecoration(
        gradient: widget.backgroundColor == null
            ? const LinearGradient(
                colors: [AppColors.orange, AppColors.orangeDark],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(r.w(30)),
        boxShadow: [
          BoxShadow(
            color: (widget.backgroundColor ?? AppColors.orangeDark).withValues(
              alpha: 0.4,
            ),
            blurRadius: r.w(12),
            offset: Offset(0, r.h(6)),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: widget.isLoading
            ? null
            : () {
                final now = DateTime.now();
                if (_lastTapTime == null ||
                    now.difference(_lastTapTime!).inMilliseconds > 1000) {
                  _lastTapTime = now;
                  widget.onPressed();
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r.w(30)),
          ),
        ),
        child: widget.isLoading
            ? SizedBox(
                width: r.w(24),
                height: r.w(24),
                child: const CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                widget.text,
                style: TextStyle(
                  color: widget.textColor ?? AppColors.white,
                  fontSize: r.sp(18, min: 16, max: 20),
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class LogoWidget extends StatelessWidget {
  final double size;

  const LogoWidget({super.key, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppColors.white.withValues(alpha: 0.9),
            AppColors.skyBlue.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            blurRadius: r.w(20),
            offset: Offset(0, r.h(10)),
          ),
        ],
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(size * 0.08),
          child: Image.asset(
            'assets/images/autiease.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppColors.skyBlue.withValues(alpha: 0.3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.child_care,
                      size: size * 0.4,
                      color: AppColors.darkBlue,
                    ),
                    SizedBox(height: r.h(8)),
                    Text(
                      'AutiEase',
                      style: TextStyle(
                        color: AppColors.darkBlue,
                        fontSize: size * 0.12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'PLAY. LEARN. GROW.',
                      style: TextStyle(
                        color: AppColors.darkBlue,
                        fontSize: size * 0.06,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
