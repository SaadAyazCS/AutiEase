import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'about_application_screen.dart';
import 'feedback_screen.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseService().logout();
    if (!context.mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'This will permanently delete your account. Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }
      await user.delete();
      await FirebaseService().logout();
      if (!context.mounted) {
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) {
        return;
      }
      final message = error.code == 'requires-recent-login'
          ? 'Please login again, then try deleting your account.'
          : 'Unable to delete account right now.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete account right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Settings',
        onBack: () => Navigator.pop(context),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 26, 14, 170),
            children: [
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                trailing: const Icon(Icons.chevron_right_rounded, size: 24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyProfileScreen()),
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
                    MaterialPageRoute(builder: (_) => const FeedbackScreen()),
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
                onTap: () => _logout(context),
              ),
              const SizedBox(height: 26),
              Center(
                child: OutlinedButton(
                  onPressed: () => _deleteAccount(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Delete Account',
                    style: TextStyle(
                      fontSize: 34 / 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 27, color: Colors.black87),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 39 / 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101010),
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
