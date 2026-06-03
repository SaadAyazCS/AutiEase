import 'package:flutter/material.dart';

import '../utils/responsive.dart';

/// Password strength level.
enum PasswordStrength { empty, weak, medium, strong }

extension PasswordStrengthX on PasswordStrength {
  Color get color {
    return switch (this) {
      PasswordStrength.empty => const Color(0xFFE2E8F0),
      PasswordStrength.weak => const Color(0xFFEF4444),
      PasswordStrength.medium => const Color(0xFFFF8D20),
      PasswordStrength.strong => const Color(0xFF22C55E),
    };
  }

  String get label {
    return switch (this) {
      PasswordStrength.empty => '',
      PasswordStrength.weak => 'Weak',
      PasswordStrength.medium => 'Medium',
      PasswordStrength.strong => 'Strong',
    };
  }
}

/// Returns the strength of the given password.
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.empty;
  if (password.length < 6) return PasswordStrength.weak;
  final hasUpper = password.contains(RegExp(r'[A-Z]'));
  final hasLower = password.contains(RegExp(r'[a-z]'));
  final hasDigit = password.contains(RegExp(r'[0-9]'));
  final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  final metCriteria = [hasUpper, hasLower, hasDigit, hasSpecial]
      .where((v) => v)
      .length;
  if (metCriteria >= 3) return PasswordStrength.strong;
  if (metCriteria >= 2) return PasswordStrength.medium;
  return PasswordStrength.weak;
}

/// A reusable password input field with:
/// - Eye-icon toggle (show/hide)
/// - Real-time strength indicator bar (when [showStrength] is true)
/// - Criteria checklist (when [showStrength] is true)
/// - Confirm-password match feedback (when [matchController] is provided)
class PasswordInputField extends StatefulWidget {
  const PasswordInputField({
    super.key,
    required this.controller,
    this.hintText = 'Password',
    this.labelText,
    this.showStrength = false,
    this.matchController,
    this.fieldDecoration,
    this.onChanged,
  });

  final TextEditingController controller;

  /// Hint shown inside the field.
  final String hintText;

  /// Optional label above the field (used in signup forms).
  final String? labelText;

  /// Show the strength bar + checklist.
  final bool showStrength;

  /// If provided, this field acts as "Confirm Password" and shows
  /// a match/mismatch indicator comparing against [matchController].
  final TextEditingController? matchController;

  /// Optional box decoration override.
  final BoxDecoration? fieldDecoration;

  final ValueChanged<String>? onChanged;

  @override
  State<PasswordInputField> createState() => _PasswordInputFieldState();
}

class _PasswordInputFieldState extends State<PasswordInputField> {
  bool _obscure = true;
  PasswordStrength _strength = PasswordStrength.empty;

  bool get _isConfirmMode => widget.matchController != null;

  void _onChanged(String value) {
    if (widget.showStrength) {
      setState(() => _strength = evaluatePasswordStrength(value));
    } else {
      setState(() {});
    }
    widget.onChanged?.call(value);
  }

  bool get _matches =>
      widget.matchController != null &&
      widget.controller.text == widget.matchController!.text;

  bool get _confirmNotEmpty => widget.controller.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Field ──────────────────────────────────────────────────────────
        Container(
          decoration: widget.fieldDecoration ??
              BoxDecoration(
                color: const Color(0xFFF4F7FB),
                borderRadius: BorderRadius.circular(r.w(16)),
                border: Border.all(
                  color: _isConfirmMode && _confirmNotEmpty
                      ? (_matches
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444))
                      : const Color(0xFFD2DCE6),
                  width: _isConfirmMode && _confirmNotEmpty ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB0C4DE).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
          child: TextField(
            controller: widget.controller,
            obscureText: _obscure,
            onChanged: _onChanged,
            style: TextStyle(
              fontSize: r.sp(16, min: 14, max: 20),
              color: const Color(0xFF1A2543),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: const Color(0xFFA0AEC0),
                fontSize: r.sp(14, min: 12, max: 16),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: r.w(18),
                vertical: r.h(15),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF888888),
                  size: r.sp(20, min: 18, max: 24),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),

        // ── Confirm match indicator ────────────────────────────────────────
        if (_isConfirmMode && _confirmNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: r.h(6), left: r.w(4)),
            child: Row(
              children: [
                Icon(
                  _matches ? Icons.check_circle : Icons.cancel,
                  color: _matches
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  size: r.sp(14, min: 12, max: 16),
                ),
                SizedBox(width: r.w(4)),
                Text(
                  _matches ? 'Passwords match' : 'Passwords do not match',
                  style: TextStyle(
                    fontSize: r.sp(11, min: 10, max: 13),
                    color: _matches
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        // ── Strength bar + checklist ───────────────────────────────────────
        if (widget.showStrength && !_isConfirmMode) ...[
          SizedBox(height: r.h(8)),
          _StrengthBar(strength: _strength),
          SizedBox(height: r.h(6)),
          _CriteriaChecklist(password: widget.controller.text),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});

  final PasswordStrength strength;

  int get _filledSegments => switch (strength) {
    PasswordStrength.empty => 0,
    PasswordStrength.weak => 1,
    PasswordStrength.medium => 2,
    PasswordStrength.strong => 3,
  };

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Row(
      children: [
        ...List.generate(3, (i) {
          final filled = i < _filledSegments;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: r.h(5),
              margin: EdgeInsets.only(right: i < 2 ? r.w(4) : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: filled ? strength.color : const Color(0xFFE2E8F0),
              ),
            ),
          );
        }),
        if (strength != PasswordStrength.empty) ...[
          SizedBox(width: r.w(8)),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: r.sp(11, min: 10, max: 13),
              fontWeight: FontWeight.w600,
              color: strength.color,
            ),
            child: Text(strength.label),
          ),
        ],
      ],
    );
  }
}

class _CriteriaChecklist extends StatelessWidget {
  const _CriteriaChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final criteria = [
      (
        'At least 6 characters',
        password.length >= 6,
      ),
      (
        'Has uppercase letter',
        password.contains(RegExp(r'[A-Z]')),
      ),
      (
        'Has lowercase letter',
        password.contains(RegExp(r'[a-z]')),
      ),
      (
        'Has a number',
        password.contains(RegExp(r'[0-9]')),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: criteria
          .map(
            (c) => Padding(
              padding: EdgeInsets.only(bottom: r.h(2)),
              child: Row(
                children: [
                  Icon(
                    c.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: r.sp(13, min: 11, max: 15),
                    color: c.$2
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFB0B8C8),
                  ),
                  SizedBox(width: r.w(4)),
                  Text(
                    c.$1,
                    style: TextStyle(
                      fontSize: r.sp(11, min: 10, max: 13),
                      color: c.$2
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
