import 'package:flutter/material.dart';

import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Map<String, bool> _preferences = {
    'pushNotifications': true,
    'emailNotifications': false,
    'dailyReminders': true,
    'activityAlerts': true,
    'progressUpdates': false,
  };
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final profile = await AppRepositories.users.getCurrentUserProfile();
    if (profile == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _preferences = {..._preferences, ...profile.notificationPreferences};
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await AppRepositories.users.updateNotificationPreferences(_preferences);
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification preferences saved to Firestore'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Notifications',
        onBack: () => Navigator.pop(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These switches are stored in Firestore under the current user profile.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  for (final entry in _notificationDefinitions)
                    SwitchListTile(
                      value: _preferences[entry.key] ?? false,
                      onChanged: (value) {
                        setState(() => _preferences[entry.key] = value);
                      },
                      title: Text(entry.title),
                      subtitle: Text(entry.subtitle),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save preferences'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDefinition {
  const _NotificationDefinition({
    required this.key,
    required this.title,
    required this.subtitle,
  });

  final String key;
  final String title;
  final String subtitle;
}

const List<_NotificationDefinition> _notificationDefinitions = [
  _NotificationDefinition(
    key: 'pushNotifications',
    title: 'Push Notifications',
    subtitle: 'Receive push notifications on your device',
  ),
  _NotificationDefinition(
    key: 'emailNotifications',
    title: 'Email Notifications',
    subtitle: 'Receive updates via email',
  ),
  _NotificationDefinition(
    key: 'dailyReminders',
    title: 'Daily Reminders',
    subtitle: 'Get reminder nudges for assigned activities',
  ),
  _NotificationDefinition(
    key: 'activityAlerts',
    title: 'Activity Alerts',
    subtitle: 'Notify when assigned items are completed',
  ),
  _NotificationDefinition(
    key: 'progressUpdates',
    title: 'Progress Updates',
    subtitle: 'Receive progress summary updates',
  ),
];
