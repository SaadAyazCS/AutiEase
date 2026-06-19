import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';

class ChildModeLockController {
  ChildModeLockController._();

  static final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  static bool get isLocked => isLockedNotifier.value;

  static String _pin = '';

  static String get pin => _pin;

  static bool hasPin() => _pin.isNotEmpty;

  static bool verifyPin(String enteredPin) {
    return _pin.isNotEmpty && enteredPin == _pin;
  }

  static Future<void> initialize() async {
    final user = AppRepositories.authClient.currentUser;
    if (user == null) {
      isLockedNotifier.value = false;
      _pin = '';
      return;
    }

    try {
      final doc = await AppRepositories.firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final profile = UserProfile.fromMap(doc.id, doc.data()!);
        isLockedNotifier.value = profile.isChildModeLocked;
        _pin = profile.childModePin;
      }
    } catch (_) {
      // Offline fallback: keep default state (unlocked/no PIN)
    }
  }

  static Future<void> setLocked(bool locked) async {
    isLockedNotifier.value = locked;
    final user = AppRepositories.authClient.currentUser;
    if (user == null) return;

    try {
      await AppRepositories.firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .update({
        'isChildModeLocked': locked,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort database update; will sync when online.
    }
  }

  static Future<void> setPin(String newPin) async {
    _pin = newPin;
    final user = AppRepositories.authClient.currentUser;
    if (user == null) return;

    try {
      await AppRepositories.firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .update({
        'childModePin': newPin,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort database update; will sync when online.
    }
  }

  static Future<bool> validatePassword(String password) async {
    final user = AppRepositories.authClient.currentUser;
    if (user == null || user.email == null) return false;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> validateGoogleCredential() async {
    final user = AppRepositories.authClient.currentUser;
    if (user == null) return false;

    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return false;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isGoogleOnlyUser() async {
    final user = AppRepositories.authClient.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toList();
    return providers.contains('google.com') && !providers.contains('password');
  }
}
