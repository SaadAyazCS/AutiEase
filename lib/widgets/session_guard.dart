import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/child_mode_lock_controller.dart';
import '../navigation/session_navigation.dart';
import '../repositories/app_repositories.dart';
import '../screens/parent_home_screen.dart';

enum SessionGuardRole { parent, therapist, authenticated, admin }

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

  // ─── Real-time moderation status listener ─────────────────────────────────
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;

  @override
  void initState() {
    super.initState();
    _sessionFuture = AppRepositories.auth.resolveSession();
    _startModerationStatusListener();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  /// Listens to the current user's Firestore document for status changes.
  /// If the admin suspends or bans the account while the user is logged in,
  /// this stream fires immediately and forces a sign-out + redirect.
  void _startModerationStatusListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _statusSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? {};
      final status = (data['status'] ?? '').toString();
      if (status == 'suspended' || status == 'banned') {
        _handleForcedSignOut(status);
      }
    });
  }

  Future<void> _handleForcedSignOut(String status) async {
    if (_isRedirecting) return;
    _isRedirecting = true;

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    final message = status == 'banned'
        ? 'Your account has been permanently banned due to serious violations of '
            'platform policies. Contact autieasefyp@gmail.com if you believe this is an error.'
        : 'Your account has been suspended by the administration. '
            'Contact autieasefyp@gmail.com if you believe this is an error.';

    final session = const AppSession(state: AppSessionState.unauthenticated);
    final target = destinationForSession(session);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        fadeSessionRoute(target),
        (route) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      });
    });
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
            if (isRestricted) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  fadeSessionRoute(const ParentHomeScreen()),
                  (route) => false,
                );
              }
            } else {
              final target = destinationForSession(session);
              Navigator.of(
                context,
              ).pushAndRemoveUntil(fadeSessionRoute(target), (route) => false);
            }
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
      case SessionGuardRole.admin:
        return session.state == AppSessionState.admin;
      case SessionGuardRole.authenticated:
        return session.state == AppSessionState.parent ||
            session.state == AppSessionState.therapist ||
            session.state == AppSessionState.admin;
    }
  }
}
