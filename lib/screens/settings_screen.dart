import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/child_mode_lock_controller.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/responsive.dart';
import '../widgets/child_mode_lock_widgets.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'about_application_screen.dart';
import 'child_profile_home_screen.dart';
import 'feedback_screen.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'notification_settings_screen.dart';
import 'professional_support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  UserProfile? _profile;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _toggleChildModeLock(bool targetValue) async {
    if (targetValue) {
      if (!ChildModeLockController.hasPin()) {
        final success = await ChildModeLockWidgets.showSetupDialog(context);
        if (success && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            fadeSessionRoute(const ChildProfileHomeScreen()),
            (route) => false,
          );
        }
      } else {
        await ChildModeLockController.setLocked(true);
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            fadeSessionRoute(const ChildProfileHomeScreen()),
            (route) => false,
          );
        }
      }
    } else {
      await ChildModeLockWidgets.showUnlockDialog(context);
    }
  }

  Future<void> _loadProfile() async {
    final profile = await AppRepositories.users.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 26),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout? You will need to sign in again to access your account.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Color(0xFF475569),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _firebaseService.logout();
    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    var checkboxChecked = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Delete your account',
            style: TextStyle(color: Color(0xFFFF3040)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is permanent. If you continue, you will not be able to recover your parent account or the information we keep for you in AutiEase, including:',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 10),
                const Text(
                  '• Your parent profile (name, phone, and email on file)',
                ),
                const Text(
                  "• Your child's profile and learning preferences saved here",
                ),
                const Text(
                  '• Activity progress and planner choices tied to this account',
                ),
                const Text(
                  '• Your Professional Support conversations with therapists',
                ),
                const Text(
                  '• Feedback and notification preferences stored in the app',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your sign-in will stop working for this account. If you use AutiEase again later, you will need to register as a new user.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: checkboxChecked,
                      onChanged: (value) {
                        setDialogState(() => checkboxChecked = value ?? false);
                      },
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'I understand that this cannot be undone and I want to permanently delete my account',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checkboxChecked
                  ? () => Navigator.pop(context, true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3040),
              ),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);

    Map<String, dynamic> outcome = {};
    try {
      outcome = await _firebaseService.deleteParentAccount();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }

    if (!mounted) {
      return;
    }

    final firestoreDeleted = outcome['firestoreDeleted'] == true;
    final authDeleted = outcome['authDeleted'] == true;
    final authError = (outcome['authError'] ?? '').toString();

    if (!firestoreDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not remove all stored information. This is often a '
            'permissions or network issue. We will still try to remove your sign-in.',
          ),
          backgroundColor: Color(0xFFFF4D4D),
          duration: Duration(seconds: 4),
        ),
      );
    }

    if (authDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            firestoreDeleted
                ? 'Your account and associated data were deleted.'
                : 'Your sign-in was removed. Some stored data may remain until support finishes cleanup.',
          ),
          backgroundColor: firestoreDeleted
              ? const Color(0xFF2ECC71)
              : const Color(0xFFFFA500),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      var errorMessage = 'We could not finish deleting your account.';
      if (authError.contains('requires-recent-login')) {
        errorMessage =
            'For your security, sign out and sign back in, then try deleting again.';
      } else if (authError.contains('network-request-failed')) {
        errorMessage = 'Network problem. Check your connection and try again.';
      } else if (authError.contains('too-many-requests')) {
        errorMessage = 'Too many attempts. Please wait and try again.';
      } else if (authError.contains('user-not-found')) {
        errorMessage = 'Session expired. Please sign in again.';
      } else if (authError.isNotEmpty) {
        errorMessage =
            'Deletion could not be completed. Your account may be limited until support helps remove it fully.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: const Color(0xFFFF4D4D),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    try {
      await _firebaseService.logout();
    } catch (_) {}

    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  bool get _isParent => _profile?.role == 'parent';

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: Stack(
        children: [
          FigmaModuleScaffold(
            title: 'Settings',
            onBack: () => Navigator.pop(context),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(r.w(38)),
                ),
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  r.w(14),
                  r.h(26),
                  r.w(14),
                  r.h(24),
                ),
                children: [
                  _SettingsRow(
                    icon: Icons.person_outline_rounded,
                    title: 'My Profile',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyProfileScreen(),
                        ),
                      );
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.child_care_rounded,
                    title: 'Child Mode Lock',
                    trailing: ValueListenableBuilder<bool>(
                      valueListenable: ChildModeLockController.isLockedNotifier,
                      builder: (context, isLocked, _) {
                        return Switch(
                          value: isLocked,
                          onChanged: (value) => _toggleChildModeLock(value),
                          activeThumbColor: const Color(0xFF4EA9E3),
                        );
                      },
                    ),
                    onTap: () {
                      final current = ChildModeLockController.isLocked;
                      _toggleChildModeLock(!current);
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.feedback_outlined,
                    title: 'Feedback',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FeedbackScreen(),
                        ),
                      );
                    },
                  ),
                  _SettingsRow(
                    icon: Icons.article_outlined,
                    title: 'About Application',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AboutApplicationScreen(),
                        ),
                      );
                    },
                  ),
                  if (_isParent) ...[
                    _SettingsRow(
                      icon: Icons.receipt_long_rounded,
                      title: 'Subscriptions & Payments',
                      trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ParentSubscriptionsHistoryScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                  _SettingsRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Logout',
                    trailing: const Icon(Icons.logout_rounded, size: 22),
                    onTap: _logout,
                  ),
                  if (_isParent) ...[
                    _SettingsRow(
                      icon: Icons.delete_forever_outlined,
                      title: 'Delete account',
                      titleColor: const Color(0xFFFF3040),
                      iconColor: const Color(0xFFFF3040),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 24,
                        color: Color(0xFFFF3040),
                      ),
                      onTap: _isDeleting ? () {} : _showDeleteAccountDialog,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_isDeleting)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? iconColor;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final primaryColor = widget.iconColor ?? const Color(0xFF4EA9E3);
    final bgColor = primaryColor.withValues(alpha: 0.1);

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Padding(
        padding: EdgeInsets.only(bottom: r.h(12)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(r.w(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(r.w(16)),
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: r.w(16), vertical: r.h(16)),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(r.w(10)),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(r.w(12)),
                      ),
                      child: Icon(
                        widget.icon,
                        size: r.sp(24),
                        color: primaryColor,
                      ),
                    ),
                    SizedBox(width: r.w(16)),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: r.sp(18),
                          fontWeight: FontWeight.w600,
                          color: widget.titleColor ?? const Color(0xFF1E293B),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    widget.trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
