import 'package:flutter/material.dart';

import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isSaving = false;
  Map<String, bool> _preferences = {
    'therapistsUpdate': false,
    'levelProgressNotification': false,
    'subscription': false,
    'routineReminders': false,
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final profile = await AppRepositories.users.getCurrentUserProfile();
    if (profile == null || !mounted) {
      return;
    }
    final saved = profile.notificationPreferences;
    setState(() {
      _preferences = {
        'therapistsUpdate':
            saved['therapistsUpdate'] ?? saved['pushNotifications'] ?? false,
        'levelProgressNotification':
            saved['levelProgressNotification'] ??
            saved['progressUpdates'] ??
            false,
        'subscription':
            saved['subscription'] ?? saved['emailNotifications'] ?? false,
        'routineReminders':
            saved['routineReminders'] ?? saved['dailyReminders'] ?? false,
      };
    });
  }

  void _toggle(String key) {
    setState(() => _preferences[key] = !(_preferences[key] ?? false));
  }

  Future<void> _savePreferences() async {
    if (_isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await AppRepositories.users.updateNotificationPreferences(_preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save notification preferences.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Notifications',
        onBack: () => Navigator.pop(context),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 170),
            children: [
              _NotificationRow(
                title: 'Therapists Update',
                subtitle:
                    'Ensure smooth communication between parents and therapists',
                value: _preferences['therapistsUpdate'] ?? false,
                onToggle: () => _toggle('therapistsUpdate'),
              ),
              _NotificationRow(
                title: 'Level Progess Notification',
                subtitle: 'Motivates the child by celebrating achievements.',
                value: _preferences['levelProgressNotification'] ?? false,
                onToggle: () => _toggle('levelProgressNotification'),
              ),
              _NotificationRow(
                title: 'Subscription',
                subtitle: 'Notifies users about payments',
                value: _preferences['subscription'] ?? false,
                onToggle: () => _toggle('subscription'),
              ),
              _NotificationRow(
                title: 'Routine Reminders',
                subtitle: 'Helps children follow a structured schedule',
                value: _preferences['routineReminders'] ?? false,
                onToggle: () => _toggle('routineReminders'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _savePreferences,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4EA9E3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700),
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

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 37 / 1.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 18 / 1.2,
                      color: Color(0xFF242424),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF9A9A9A)),
                  color: value ? const Color(0xFF2D7CF6) : Colors.white,
                ),
                child: value
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
