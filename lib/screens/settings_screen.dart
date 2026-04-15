import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../utils/responsive.dart';
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

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
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
                color: Colors.black87,
              ),
              SizedBox(width: r.w(14)),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: r.sp(39 / 1.5, min: 18, max: 29),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF101010),
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
