import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'about_application_screen.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<SettingsEntry> _parentFallbackEntries = [
    SettingsEntry(
      id: 'profile',
      title: 'My Profile',
      subtitle: 'Manage parent and child profile fields',
      routeKey: 'profile',
      targetRole: 'parent',
      sortOrder: 1,
      isActive: true,
    ),
    SettingsEntry(
      id: 'notifications',
      title: 'Notifications',
      subtitle: 'Notification preferences stored in Firestore',
      routeKey: 'notifications',
      targetRole: 'parent',
      sortOrder: 2,
      isActive: true,
    ),
    SettingsEntry(
      id: 'about',
      title: 'About Application',
      subtitle: 'About, mission, and support information from the DB',
      routeKey: 'about',
      targetRole: 'parent',
      sortOrder: 3,
      isActive: true,
    ),
  ];

  static const List<SettingsEntry> _therapistFallbackEntries = [
    SettingsEntry(
      id: 'therapist-profile',
      title: 'My Profile',
      subtitle: 'Manage therapist profile fields',
      routeKey: 'profile',
      targetRole: 'therapist',
      sortOrder: 1,
      isActive: true,
    ),
    SettingsEntry(
      id: 'therapist-notifications',
      title: 'Notifications',
      subtitle: 'Notification preferences stored in Firestore',
      routeKey: 'notifications',
      targetRole: 'therapist',
      sortOrder: 2,
      isActive: true,
    ),
    SettingsEntry(
      id: 'therapist-about',
      title: 'About Application',
      subtitle: 'About, mission, and support information from the DB',
      routeKey: 'about',
      targetRole: 'therapist',
      sortOrder: 3,
      isActive: true,
    ),
  ];

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

  Widget _screenForRoute(String routeKey) {
    switch (routeKey) {
      case 'profile':
      case 'therapist_profile':
        return const MyProfileScreen();
      case 'notifications':
        return const NotificationsScreen();
      case 'about':
        return const AboutApplicationScreen();
      default:
        return _SettingsPlaceholder(routeKey: routeKey);
    }
  }

  Future<List<SettingsEntry>> _loadSettingsEntries() async {
    final session = await AppRepositories.auth.resolveSession();
    final role = session.role == 'therapist' ? 'therapist' : 'parent';
    final entries = await AppRepositories.content.getSettingsEntries(role);
    if (entries.isNotEmpty) {
      return entries;
    }
    return role == 'therapist'
        ? _therapistFallbackEntries
        : _parentFallbackEntries;
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Settings',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<SettingsEntry>>(
          future: _loadSettingsEntries(),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              children: [
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: _SettingsCard(
                      child: Text(
                        'The settings_entries collection is empty. Seed Firestore to configure this screen.',
                      ),
                    ),
                  ),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SettingsCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.title),
                        subtitle: Text(entry.subtitle),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _screenForRoute(entry.routeKey),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                _SettingsCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Logout'),
                    subtitle: const Text(
                      'Sign out from Firebase and return to login',
                    ),
                    trailing: const Icon(Icons.logout),
                    onTap: () => _logout(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder({required this.routeKey});

  final String routeKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(routeKey)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The Firestore settings route "$routeKey" does not have a Flutter screen mapping yet.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
