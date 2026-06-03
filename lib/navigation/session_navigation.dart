import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../screens/child_profile_home_screen.dart';
import '../screens/email_verification_screen.dart';
import '../screens/login_screen.dart';
import '../screens/parent_home_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/therapist_home_screen.dart';
import 'child_mode_lock_controller.dart';

Widget destinationForSession(AppSession session, {String? emailFallback}) {
  switch (session.state) {
    case AppSessionState.parent:
      if (ChildModeLockController.isLocked) {
        return const ChildProfileHomeScreen();
      }
      return const ParentHomeScreen();
    case AppSessionState.therapist:
      return const TherapistHomeScreen();
    case AppSessionState.incompleteProfile:
      return const RoleSelectionScreen();
    case AppSessionState.emailVerificationPending:
      return EmailVerificationScreen(
        email: emailFallback ?? AppRepositories.auth.currentUser?.email ?? '',
      );
    case AppSessionState.unauthenticated:
      return const LoginScreen();
  }
}

Route<void> fadeSessionRoute(Widget target) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => target,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
