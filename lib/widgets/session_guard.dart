import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';

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

        if (_isAllowed(session)) {
          return widget.child;
        }

        if (!_isRedirecting) {
          _isRedirecting = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            final target = destinationForSession(session);
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
