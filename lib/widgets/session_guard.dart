import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/child_mode_lock_controller.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../screens/child_profile_home_screen.dart';

enum SessionGuardRole { parent, therapist, authenticated }

class SessionGuard extends StatefulWidget {
  const SessionGuard({super.key, required this.role, required this.child});

  final SessionGuardRole role;
  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  late final Future<AppSession> _sessionFuture;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    _sessionFuture = AppRepositories.auth.resolveSession();
  }

  bool _isRestrictedByChildMode() {
    if (!ChildModeLockController.isLocked) return false;

    if (widget.role != SessionGuardRole.parent &&
        widget.role != SessionGuardRole.authenticated) {
      return false;
    }

    final childType = widget.child.runtimeType.toString();
    final restrictedTypes = {
      'DashboardScreen',
      'SettingsScreen',
      'LearningPlannerScreen',
      'ProfessionalSupportScreen',
      'MyProfileScreen',
      'FeedbackScreen',
      'NotificationsScreen',
      'AboutApplicationScreen',
    };

    return restrictedTypes.contains(childType);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session =
            snapshot.data ??
            const AppSession(state: AppSessionState.unauthenticated);

        final isAllowed = _isAllowed(session);
        final isRestricted = _isRestrictedByChildMode();

        if (isAllowed && !isRestricted) {
          return widget.child;
        }

        if (!_isRedirecting) {
          _isRedirecting = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            final target = ChildModeLockController.isLocked
                ? const ChildProfileHomeScreen()
                : destinationForSession(session);
            Navigator.of(
              context,
            ).pushAndRemoveUntil(fadeSessionRoute(target), (route) => false);
          });
        }

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }

  bool _isAllowed(AppSession session) {
    switch (widget.role) {
      case SessionGuardRole.parent:
        return session.state == AppSessionState.parent;
      case SessionGuardRole.therapist:
        return session.state == AppSessionState.therapist;
      case SessionGuardRole.authenticated:
        return session.state == AppSessionState.parent ||
            session.state == AppSessionState.therapist;
    }
  }
}
