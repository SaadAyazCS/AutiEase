import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/child_mode_lock_controller.dart';

import '../utils/responsive.dart';

class ChildModeLockWidgets {
  ChildModeLockWidgets._();

  static int _failedAttempts = 0;
  static DateTime? _lockoutEndTime;

  static bool get isLockedOut {
    if (_lockoutEndTime == null) return false;
    if (DateTime.now().isAfter(_lockoutEndTime!)) {
      _failedAttempts = 0;
      _lockoutEndTime = null;
      return false;
    }
    return true;
  }

  static int get lockoutSecondsRemaining {
    if (_lockoutEndTime == null) return 0;
    final diff = _lockoutEndTime!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  static Future<bool> showUnlockDialog(BuildContext context) async {
    // If no PIN is configured, direct to setup instead.
    if (!ChildModeLockController.hasPin()) {
      final success = await showSetupDialog(context);
      return success;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _UnlockDialog(),
    );

    return result ?? false;
  }

  static Future<bool> showSetupDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _SetupDialog(),
    );

    return result ?? false;
  }
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _pinController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _forgotMode = false;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _lockoutTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    if (ChildModeLockWidgets.isLockedOut) {
      _startLockoutTimer();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _secondsLeft = ChildModeLockWidgets.lockoutSecondsRemaining;
      _errorMessage = 'Too many attempts. Try again in $_secondsLeft seconds.';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _secondsLeft = ChildModeLockWidgets.lockoutSecondsRemaining;
        if (_secondsLeft <= 0) {
          timer.cancel();
          _errorMessage = null;
        } else {
          _errorMessage = 'Too many attempts. Try again in $_secondsLeft seconds.';
        }
      });
    });
  }

  Future<void> _handleUnlock() async {
    if (ChildModeLockWidgets.isLockedOut) return;

    final enteredPin = _pinController.text;
    if (enteredPin.length < 4) {
      setState(() => _errorMessage = 'Please enter a 4-digit PIN.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Artificially delay slightly for smooth premium feedback
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (ChildModeLockController.verifyPin(enteredPin)) {
      await ChildModeLockController.setLocked(false);
      ChildModeLockWidgets._failedAttempts = 0;
      ChildModeLockWidgets._lockoutEndTime = null;
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      ChildModeLockWidgets._failedAttempts++;
      if (ChildModeLockWidgets._failedAttempts >= 5) {
        ChildModeLockWidgets._lockoutEndTime =
            DateTime.now().add(const Duration(seconds: 60));
        setState(() {
          _isLoading = false;
        });
        _startLockoutTimer();
      } else {
        setState(() {
          _isLoading = false;
          _pinController.clear();
          final remaining = 5 - ChildModeLockWidgets._failedAttempts;
          _errorMessage = 'Incorrect PIN. $remaining attempts remaining.';
        });
      }
    }
  }

  Future<void> _handleReset() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isGoogle = await ChildModeLockController.isGoogleOnlyUser();
    bool success = false;

    if (isGoogle) {
      success = await ChildModeLockController.validateGoogleCredential();
    } else {
      success = await ChildModeLockController.validatePassword(password);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (success) {
      await ChildModeLockController.setLocked(false);
      await ChildModeLockController.setPin('');
      ChildModeLockWidgets._failedAttempts = 0;
      ChildModeLockWidgets._lockoutEndTime = null;
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN successfully reset and Child Mode disabled.'),
            backgroundColor: Color(0xFF2ECC71),
          ),
        );
      }
    } else {
      setState(() {
        _errorMessage = isGoogle
            ? 'Google re-authentication failed.'
            : 'Incorrect account password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(maxWidth: r.w(320)),
        padding: EdgeInsets.all(r.w(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _forgotMode ? Icons.vpn_key_rounded : Icons.lock_outline_rounded,
                  color: const Color(0xFF4EA9E3),
                  size: 26,
                ),
                SizedBox(width: r.w(10)),
                Expanded(
                  child: Text(
                    _forgotMode ? 'Reset PIN' : 'Child Mode Locked',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: r.sp(18),
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: r.h(12)),
            Text(
              _forgotMode
                  ? 'Enter your parent password to reset the PIN and unlock access.'
                  : 'Enter your 4-digit PIN to exit Child Mode.',
              style: TextStyle(
                fontSize: r.sp(14),
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            SizedBox(height: r.h(16)),
            if (!_forgotMode)
              TextField(
                controller: _pinController,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                enabled: !ChildModeLockWidgets.isLockedOut && !_isLoading,
                style: TextStyle(
                  fontSize: r.sp(22),
                  fontWeight: FontWeight.bold,
                  letterSpacing: r.w(12),
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  hintStyle: TextStyle(
                    color: const Color(0xFFCBD5E1),
                    letterSpacing: r.w(12),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: r.h(8)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4EA9E3), width: 1.5),
                  ),
                ),
              )
            else ...[
              FutureBuilder<bool>(
                future: ChildModeLockController.isGoogleOnlyUser(),
                builder: (context, snapshot) {
                  final isGoogle = snapshot.data == true;
                  if (isGoogle) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: r.h(8)),
                      child: Text(
                        'This account is registered via Google. Tap Reset to re-authenticate with Google.',
                        style: TextStyle(
                          fontSize: r.sp(13.5),
                          color: const Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return TextField(
                    controller: _passwordController,
                    obscureText: true,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      contentPadding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(12)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4EA9E3), width: 1.5),
                      ),
                    ),
                  );
                },
              ),
            ],
            if (_errorMessage != null) ...[
              SizedBox(height: r.h(12)),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFEF4444),
                  fontSize: r.sp(13),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            SizedBox(height: r.h(16)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_forgotMode) {
                            setState(() {
                              _forgotMode = false;
                              _errorMessage = null;
                            });
                          } else {
                            Navigator.pop(context, false);
                          }
                        },
                  child: Text(
                    _forgotMode ? 'Back' : 'Cancel',
                    style: TextStyle(
                      color: const Color(0xFF64748B),
                      fontSize: r.sp(15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: r.w(8)),
                _isLoading
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: r.w(16)),
                        child: SizedBox(
                          width: r.w(20),
                          height: r.w(20),
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton(
                        onPressed: ChildModeLockWidgets.isLockedOut ? null : (_forgotMode ? _handleReset : _handleUnlock),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4EA9E3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(10)),
                        ),
                        child: Text(
                          _forgotMode ? 'Reset' : 'Unlock',
                          style: TextStyle(
                            fontSize: r.sp(15),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ],
            ),
            if (!_forgotMode && !ChildModeLockWidgets.isLockedOut) ...[
              SizedBox(height: r.h(10)),
              Center(
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _forgotMode = true;
                            _errorMessage = null;
                          }),
                  child: Text(
                    'Forgot PIN?',
                    style: TextStyle(
                      color: const Color(0xFF4EA9E3),
                      fontWeight: FontWeight.w700,
                      fontSize: r.sp(13.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog();

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  final _pin1Controller = TextEditingController();
  final _pin2Controller = TextEditingController();
  
  bool _confirmMode = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pin1Controller.dispose();
    _pin2Controller.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final pin = _pin1Controller.text;
    if (pin.length < 4) {
      setState(() => _errorMessage = 'Please enter a 4-digit PIN.');
      return;
    }

    setState(() {
      _confirmMode = true;
      _errorMessage = null;
    });
  }

  Future<void> _handleSave() async {
    final pin1 = _pin1Controller.text;
    final pin2 = _pin2Controller.text;

    if (pin2.length < 4) {
      setState(() => _errorMessage = 'Please confirm your 4-digit PIN.');
      return;
    }

    if (pin1 != pin2) {
      setState(() {
        _pin2Controller.clear();
        _errorMessage = 'PINs do not match. Try again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await ChildModeLockController.setPin(pin1);
    await ChildModeLockController.setLocked(true);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(maxWidth: r.w(320)),
        padding: EdgeInsets.all(r.w(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFF4EA9E3),
                  size: 26,
                ),
                SizedBox(width: r.w(10)),
                Expanded(
                  child: Text(
                    _confirmMode ? 'Confirm PIN' : 'Set Child Mode PIN',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: r.sp(18),
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: r.h(12)),
            Text(
              _confirmMode
                  ? 'Please confirm the 4-digit PIN you just entered.'
                  : 'Choose a 4-digit PIN to secure parent settings and controls.',
              style: TextStyle(
                fontSize: r.sp(14),
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            SizedBox(height: r.h(16)),
            TextField(
              controller: _confirmMode ? _pin2Controller : _pin1Controller,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              enabled: !_isLoading,
              style: TextStyle(
                fontSize: r.sp(22),
                fontWeight: FontWeight.bold,
                letterSpacing: r.w(12),
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                hintStyle: TextStyle(
                  color: const Color(0xFFCBD5E1),
                  letterSpacing: r.w(12),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: r.h(8)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4EA9E3), width: 1.5),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              SizedBox(height: r.h(12)),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFEF4444),
                  fontSize: r.sp(13),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            SizedBox(height: r.h(16)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_confirmMode) {
                            setState(() {
                              _confirmMode = false;
                              _pin2Controller.clear();
                              _errorMessage = null;
                            });
                          } else {
                            Navigator.pop(context, false);
                          }
                        },
                  child: Text(
                    _confirmMode ? 'Back' : 'Cancel',
                    style: TextStyle(
                      color: const Color(0xFF64748B),
                      fontSize: r.sp(15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: r.w(8)),
                _isLoading
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: r.w(16)),
                        child: SizedBox(
                          width: r.w(20),
                          height: r.w(20),
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton(
                        onPressed: _confirmMode ? _handleSave : _handleNext,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4EA9E3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(10)),
                        ),
                        child: Text(
                          _confirmMode ? 'Save & Lock' : 'Next',
                          style: TextStyle(
                            fontSize: r.sp(15),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
