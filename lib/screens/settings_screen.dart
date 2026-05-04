import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/responsive.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'about_application_screen.dart';
import 'feedback_screen.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'notifications_screen.dart';

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

  Future<void> _loadProfile() async {
    final profile = await AppRepositories.users.getCurrentUserProfile();
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  Future<void> _logout() async {
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
                const Text('• Your parent profile (name, phone, and email on file)'),
                const Text(
                  "• Your child's profile and learning preferences saved here",
                ),
                const Text('• Activity progress and planner choices tied to this account'),
                const Text('• Your Professional Support conversations with therapists'),
                const Text('• Feedback and notification preferences stored in the app'),
                const SizedBox(height: 12),
                const Text(
                  'Your sign-in will stop working for this account. If you use AutiEase again later, you will need to register as a new user.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
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
          backgroundColor:
              firestoreDeleted ? const Color(0xFF2ECC71) : const Color(0xFFFFA500),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      var errorMessage = 'We could not finish deleting your account.';
      if (authError.contains('requires-recent-login')) {
        errorMessage =
            'For your security, sign out and sign back in, then try deleting again.';
      } else if (authError.contains('network-request-failed')) {
        errorMessage =
            'Network problem. Check your connection and try again.';
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
                padding: EdgeInsets.fromLTRB(r.w(14), r.h(26), r.w(14), r.h(24)),
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
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
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
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Padding(
      padding: EdgeInsets.only(bottom: r.h(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(r.w(10)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: r.w(6), vertical: r.h(8)),
          child: Row(
            children: [
              Icon(
                icon,
                size: r.sp(27, min: 20, max: 30),
                color: iconColor ?? Colors.black87,
              ),
              SizedBox(width: r.w(14)),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: r.sp(39 / 1.5, min: 18, max: 29),
                    fontWeight: FontWeight.w600,
                    color: titleColor ?? const Color(0xFF101010),
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
