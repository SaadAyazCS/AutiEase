import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import 'auth_verification_policy.dart';

class FirebaseService {
  FirebaseService()
    : _auth = FirebaseAuth.instance,
      _firestore = FirebaseFirestore.instance,
      _googleSignIn = GoogleSignIn(
        serverClientId:
            '373824401794-dhrdq1p62q1lrcgmp3q3cv2vu5iuunfk.apps.googleusercontent.com',
      );

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestoreCollections.users);

  CollectionReference<Map<String, dynamic>> get _children =>
      _firestore.collection(FirestoreCollections.childProfiles);

  CollectionReference<Map<String, dynamic>> get _therapists =>
      _firestore.collection(FirestoreCollections.therapistProfiles);

  String get _authApiKey => DefaultFirebaseOptions.currentPlatform.apiKey;

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<bool?> _hasUserProfileForEmail(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final candidates = <String>{normalized, email.trim()};

      for (final candidate in candidates) {
        if (candidate.isEmpty) {
          continue;
        }
        final snapshot = await _users
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          return true;
        }
      }
      return false;
    } on FirebaseException catch (error) {
      debugPrint('Profile lookup by email failed: ${error.code}');
      return null;
    } catch (error) {
      debugPrint('Profile lookup by email failed: $error');
      return null;
    }
  }

  Future<bool?> _hasAccountViaFunction(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized.isEmpty) {
      return false;
    }
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkAccountExistsByEmail',
      );
      final result = await callable.call({'email': normalized});
      final data = result.data;
      debugPrint('checkAccountExistsByEmail result: $data');
      if (data is Map) {
        final exists = data['exists'];
        if (exists is bool) {
          return exists;
        }
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud function lookup by email failed with FirebaseFunctionsException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Cloud function lookup by email failed: $e');
      return null;
    }
  }

  String _friendlyAuthMessage(
    FirebaseAuthException error, {
    required String fallback,
  }) {
    switch (error.code) {
      case 'too-many-requests':
        return 'Please wait 30-60 seconds, then try once.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      case 'email-already-in-use':
        return 'This email is already registered. Please log in instead.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'operation-not-allowed':
        return 'This sign-in method is currently disabled. Please contact support.';
      case 'account-exists-with-different-credential':
        return 'This email is already linked with another sign-in method. Use your previous method first.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return error.message ?? fallback;
    }
  }

  String _friendlyGoogleSignInError(Object error) {
    if (error is PlatformException) {
      final payload =
          '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
              .toLowerCase();

      if (payload.contains('sign_in_canceled') ||
          payload.contains('12501') ||
          payload.contains('canceled')) {
        return 'Google sign-in cancelled';
      }

      if (payload.contains('network')) {
        return 'Network error. Check your internet connection and try again.';
      }

      if (payload.contains('10') ||
          payload.contains('12500') ||
          payload.contains('developer_error') ||
          payload.contains('sign_in_failed') ||
          payload.contains('configuration')) {
        return 'Google Sign-In is not configured for this APK yet. Add SHA-1 and SHA-256 for this app key in Firebase, then download and replace android/app/google-services.json.';
      }
    }

    final lowered = error.toString().toLowerCase();
    if (lowered.contains('10') ||
        lowered.contains('12500') ||
        lowered.contains('developer_error')) {
      return 'Google Sign-In is not configured for this APK yet. Add SHA-1 and SHA-256 for this app key in Firebase, then download and replace android/app/google-services.json.';
    }

    return 'Google sign-in failed. Please try again.';
  }

  Future<void> _rollbackAuthUser(User? user) async {
    if (user == null) {
      return;
    }
    try {
      await user.delete();
    } catch (_) {
      // If deletion fails, at least remove the local session so the user is
      // not left inside a half-created account flow.
      try {
        await _auth.signOut();
      } catch (_) {}
    }
  }

  Future<User?> _refreshCurrentUser() async {
    var user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    await user.getIdToken(true);
    await user.reload();
    return _auth.currentUser;
  }

  Future<void> _markCurrentUserVerified() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await _users.doc(user.uid).set({
      'status': 'verified',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> _isCurrentUserEmailVerified() async {
    final user = await _refreshCurrentUser();
    if (user == null) {
      return false;
    }

    var verified = user.emailVerified;

    // Fallback to a direct server check in case local SDK state is stale.
    if (!verified) {
      try {
        final idToken = await user.getIdToken(true);
        final response = await http.post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$_authApiKey',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': idToken}),
        );

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final users = (payload['users'] as List?) ?? const [];
          if (users.isNotEmpty) {
            verified =
                (users.first as Map<String, dynamic>)['emailVerified'] == true;
          }
        }
      } catch (error) {
        debugPrint('Email verification lookup fallback failed: $error');
      }
    }

    if (!verified) {
      return false;
    }

    try {
      await _markCurrentUserVerified();
    } catch (error) {
      debugPrint('Unable to sync verified status to Firestore: $error');
    }
    return true;
  }

  Future<Map<String, dynamic>> registerParentWithChild({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String childName,
    required List<String> supportArea,
  }) async {
    final normalizedFirstName = firstName.trim();
    final normalizedLastName = lastName.trim();
    final normalizedEmail = _normalizeEmail(email);
    final normalizedPhone = phone.trim();
    final normalizedFullName = '$normalizedFirstName $normalizedLastName'
        .trim();
    User? resolvedUser;
    var createdPasswordUser = false;
    var isExistingGoogleUser = false;

    try {
      final existingUser = _auth.currentUser;
      final existingEmail = existingUser?.email?.trim().toLowerCase();
      final requestedEmail = normalizedEmail;
      final hasGoogleProvider =
          existingUser?.providerData.any(
            (provider) => provider.providerId == 'google.com',
          ) ??
          false;
      isExistingGoogleUser =
          existingUser != null &&
          hasGoogleProvider &&
          existingEmail == requestedEmail;

      if (isExistingGoogleUser) {
        resolvedUser = existingUser;
        if (password.isNotEmpty) {
          try {
            final emailCredential = EmailAuthProvider.credential(
              email: normalizedEmail,
              password: password,
            );
            await existingUser.linkWithCredential(emailCredential);
          } on FirebaseAuthException catch (error) {
            if (error.code != 'provider-already-linked') {
              return {
                'success': false,
                'message': error.message ?? 'Unable to link credentials',
              };
            }
          }
        }
      } else {
        // Do not reuse non-Google sessions for signup role flows.
        if (existingUser != null) {
          await _auth.signOut();
        }
        try {
          final credential = await _auth.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
          resolvedUser = credential.user;
          createdPasswordUser = resolvedUser != null;
        } on FirebaseAuthException catch (error) {
          return {
            'success': false,
            'message': _friendlyAuthMessage(
              error,
              fallback: 'Registration failed',
            ),
          };
        }
      }

      final user = resolvedUser;
      if (user == null) {
        return {
          'success': false,
          'message': 'Unable to create or resolve the parent account',
        };
      }

      if (normalizedFullName.isNotEmpty &&
          user.displayName?.trim() != normalizedFullName) {
        try {
          await user.updateDisplayName(normalizedFullName);
        } catch (_) {
          // Keep signup resilient if Auth profile update fails.
        }
      }

      final childRef = _children.doc();
      final childProfile = ChildProfile(
        id: childRef.id,
        parentId: user.uid,
        name: childName,
        avatar: '',
        supportAreas: supportArea,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final profile = UserProfile(
        uid: user.uid,
        email: normalizedEmail,
        firstName: normalizedFirstName,
        lastName: normalizedLastName,
        role: 'parent',
        status: user.emailVerified || isExistingGoogleUser
            ? 'verified'
            : 'unverified',
        phone: normalizedPhone,
        photoUrl: user.photoURL ?? '',
        subscriptionTier: 'free',
        entitlements: const {'professionalSupport': false, 'chatAccess': false},
        playSettings: const {
          'difficulty': 'normal',
          'lowStimulationMode': false,
        },
        notificationPreferences: const {
          'therapistsUpdate': true,
          'levelProgressNotification': true,
          'subscription': true,
          'routineReminders': true,
        },
        activeChildId: childProfile.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // --- Step A: Load default content (non-fatal; fall back to empty) ------
      final wantsCommunication = supportArea.any(
        (entry) => entry.toLowerCase().contains('communication'),
      );
      final wantsLearning = supportArea.any(
        (entry) => entry.toLowerCase().contains('learning'),
      );

      List<LearningModuleModel> defaultModules = const [];
      List<dynamic> defaultActivities = const [];
      List<String> defaultCommunicationIds = const [];
      try {
        defaultModules = wantsLearning
            ? await AppRepositories.content.getAllLearningModules()
            : const <LearningModuleModel>[];
        defaultActivities =
            await AppRepositories.content.getAllActivityTemplates();
        defaultCommunicationIds = wantsCommunication
            ? List<String>.from(CommunicationFigmaCatalog.homeBoardOrder)
            : const <String>[];
      } catch (e) {
        // Content loading is non-fatal; signup continues with empty defaults.
        debugPrint('[Signup/Parent] Content load failed (non-fatal): $e');
      }

      // --- Step B: Write user document first --------------------------------
      // Security rules use get(users/uid) to check role, so this must be
      // committed BEFORE the child-profile batch (Phase C).
      try {
        final userRef = _users.doc(user.uid);
        final userMap = profile.toMap()
          ..remove('createdAt')
          ..remove('updatedAt');
        await userRef.set({
          ...userMap,
          'authProvider': isExistingGoogleUser ? 'google' : 'password',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[Signup/Parent] Step B (user doc) OK — uid=${user.uid}');
      } catch (e, st) {
        final code = e is FirebaseException ? e.code : 'unknown';
        final msg = e is FirebaseException ? (e.message ?? e.toString()) : e.toString();
        debugPrint('[Signup/Parent] Step B FAILED — code=$code msg=$msg\n$st');
        if (createdPasswordUser) await _rollbackAuthUser(user);
        return {
          'success': false,
          'message': 'Account setup failed (user profile). code=$code: $msg',
        };
      }

      // --- Step C: Batch-write child profile, assignment & snapshot ---------
      try {
        final batch = _firestore.batch();

        final childRef = _children.doc(childProfile.id);
        final childMap = childProfile.toMap()
          ..remove('createdAt')
          ..remove('updatedAt');
        batch.set(childRef, {
          ...childMap,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final assignmentRef = _firestore
            .collection(FirestoreCollections.childAssignments)
            .doc(childProfile.id);
        final assignmentMap = ChildAssignment(
          id: childProfile.id,
          childId: childProfile.id,
          parentId: user.uid,
          assignedCategoryIds: defaultCommunicationIds,
          assignedModuleIds:
              defaultModules.map((module) => module.id).toList(),
          assignedActivityTemplateIds: defaultActivities
              .map((a) => (a as dynamic).id as String)
              .toList(),
          status: 'active',
          effectiveFrom: DateTime.now(),
        ).toMap();
        batch.set(assignmentRef, {
          ...assignmentMap,
          'effectiveFrom': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        batch.set(
          _firestore
              .collection(FirestoreCollections.dashboardSnapshots)
              .doc(childProfile.id),
          {
            'completedTasks': 0,
            'weeklyMinutes': 0,
            'streakDays': 0,
            'moodEntries': 0,
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );

        await batch.commit();
        debugPrint('[Signup/Parent] Step C (child batch) OK');
      } catch (e, st) {
        final code = e is FirebaseException ? e.code : 'unknown';
        final msg = e is FirebaseException ? (e.message ?? e.toString()) : e.toString();
        debugPrint('[Signup/Parent] Step C FAILED — code=$code msg=$msg\n$st');
        if (createdPasswordUser) await _rollbackAuthUser(user);
        return {
          'success': false,
          'message': 'Account setup failed (child data). code=$code: $msg',
        };
      }

      var message = user.emailVerified || isExistingGoogleUser
          ? 'Signup completed'
          : 'Verification email sent';
      if (createdPasswordUser && !user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (_) {
          message =
              'Account created. Please use Resend on the verification screen.';
        }
      }

      return {
        'success': true,
        'message': message,
        'uid': user.uid,
        'childId': childProfile.id,
      };
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> registerTherapist({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    String? specialization,
    String? licenseNumber,
  }) async {
    final normalizedFirstName = firstName.trim();
    final normalizedLastName = lastName.trim();
    final normalizedEmail = _normalizeEmail(email);
    final normalizedPhone = phone.trim();
    final normalizedFullName = '$normalizedFirstName $normalizedLastName'
        .trim();
    User? resolvedUser;
    var createdPasswordUser = false;
    var isExistingGoogleUser = false;

    try {
      final existingUser = _auth.currentUser;
      final existingEmail = existingUser?.email?.trim().toLowerCase();
      final requestedEmail = normalizedEmail;
      final hasGoogleProvider =
          existingUser?.providerData.any(
            (provider) => provider.providerId == 'google.com',
          ) ??
          false;
      isExistingGoogleUser =
          existingUser != null &&
          hasGoogleProvider &&
          existingEmail == requestedEmail;

      if (isExistingGoogleUser) {
        resolvedUser = existingUser;
        if (password.isNotEmpty) {
          try {
            final emailCredential = EmailAuthProvider.credential(
              email: normalizedEmail,
              password: password,
            );
            await existingUser.linkWithCredential(emailCredential);
          } on FirebaseAuthException catch (error) {
            if (error.code != 'provider-already-linked') {
              return {
                'success': false,
                'message': error.message ?? 'Unable to link credentials',
              };
            }
          }
        }
      } else {
        // Do not reuse non-Google sessions for signup role flows.
        if (existingUser != null) {
          await _auth.signOut();
        }
        try {
          final credential = await _auth.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
          resolvedUser = credential.user;
          createdPasswordUser = resolvedUser != null;
        } on FirebaseAuthException catch (error) {
          return {
            'success': false,
            'message': _friendlyAuthMessage(
              error,
              fallback: 'Registration failed',
            ),
          };
        }
      }

      final user = resolvedUser;
      if (user == null) {
        return {
          'success': false,
          'message': 'Unable to create or resolve the therapist account',
        };
      }

      if (normalizedFullName.isNotEmpty &&
          user.displayName?.trim() != normalizedFullName) {
        try {
          await user.updateDisplayName(normalizedFullName);
        } catch (_) {
          // Keep signup resilient if Auth profile update fails.
        }
      }

      final profile = UserProfile(
        uid: user.uid,
        email: normalizedEmail,
        firstName: normalizedFirstName,
        lastName: normalizedLastName,
        role: 'therapist',
        status: user.emailVerified || isExistingGoogleUser
            ? 'verified'
            : 'unverified',
        phone: normalizedPhone,
        photoUrl: user.photoURL ?? '',
        subscriptionTier: 'provider',
        entitlements: const {'professionalSupport': true, 'chatAccess': true},
        playSettings: const {
          'difficulty': 'normal',
          'lowStimulationMode': false,
        },
        notificationPreferences: const {
          'pushNotifications': true,
          'emailNotifications': true,
          'dailyReminders': false,
          'activityAlerts': true,
          'progressUpdates': true,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      try {
        // Phase 1: Write user document first so that security rules using
        // get(users/uid) can resolve the user's role in subsequent writes.
        final userRef = _users.doc(user.uid);
        final therapistUserMap = profile.toMap()
          ..remove('createdAt')
          ..remove('updatedAt');
        await userRef.set({
          ...therapistUserMap,
          'authProvider': isExistingGoogleUser ? 'google' : 'password',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Phase 2: Write therapist profile. The user doc is already committed
        // so rules can verify the therapist role via get(users/uid).
        final therapistRef = _therapists.doc(user.uid);
        await therapistRef.set({
          'displayName': normalizedFullName,
          'bio': '',
          'specializations': [
            if (specialization != null && specialization.isNotEmpty)
              specialization,
          ],
          'pricing': '',
          'languages': const ['English'],
          'rating': 0,
          'availability': 'Contact for availability',
          'photoUrl': user.photoURL ?? '',
          'isActive': true,
          'verificationStatus': 'pending',
          'experience_years': 0,
          'experience_months': 0,
          'isAcceptingClients': true,
          'licenseNumber': licenseNumber ?? '',
          'contactEmail': normalizedEmail,
          'contactPhone': normalizedPhone,
        }, SetOptions(merge: true));
      } catch (e, stackTrace) {
        final code = e is FirebaseException ? e.code : 'unknown';
        final msg = e is FirebaseException ? e.message : e.toString();
        debugPrint(
          '[Signup/Therapist] FAILED — code=$code message=$msg\n$stackTrace',
        );
        if (createdPasswordUser) {
          await _rollbackAuthUser(user);
        }
        return {
          'success': false,
          'message':
              'We could not finish setting up the account. Please try again.',
        };
      }

      var message = user.emailVerified || isExistingGoogleUser
          ? 'Signup completed'
          : 'Verification email sent';
      if (createdPasswordUser && !user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (_) {
          message =
              'Account created. Please use Resend on the verification screen.';
        }
      }

      return {'success': true, 'message': message, 'uid': user.uid};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  /// Predefined admin credentials — the account is auto-created on first login.
  static const _adminCredentials = <String, String>{
    'admin@autiease.com': 'AutiEaseAdmin1',
  };

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      // ── Auto-bootstrap admin account on first login ─────────────────
      // If this is a predefined admin email with the correct password,
      // and the Firebase Auth account doesn't exist yet, create it.
      if (_adminCredentials.containsKey(normalizedEmail) &&
          _adminCredentials[normalizedEmail] == password) {
        try {
          await _auth.signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
            // Account doesn't exist yet — create it automatically
            try {
              await _auth.createUserWithEmailAndPassword(
                email: normalizedEmail,
                password: password,
              );
            } on FirebaseAuthException catch (createError) {
              if (createError.code == 'email-already-in-use') {
                rethrow; // original error (meaning password entered is incorrect for existing user)
              } else {
                rethrow;
              }
            }
          } else {
            rethrow;
          }
        }
      } else {
        // ── Normal login for non-admin users ──────────────────────────
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = await _refreshCurrentUser() ?? _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Login failed'};
      }

      // Skip email verification for predefined admin emails
      final isAdminEmail = _adminCredentials.containsKey(
        user.email?.toLowerCase().trim() ?? '',
      );

      final userDoc = await _users.doc(user.uid).get();
      final data = userDoc.data() ?? <String, dynamic>{};

      if (!isAdminEmail) {
        final isVerified = await _isCurrentUserEmailVerified();
        final isGoogleUser = user.providerData.any(
          (provider) => provider.providerId == 'google.com',
        );
        if (requiresEmailVerification(
          isGoogleUser: isGoogleUser,
          isEmailVerified: isVerified,
        )) {
          return {
            'success': false,
            'message': 'Please verify your email first. Check your inbox.',
            'needsVerification': true,
          };
        }

        if (isVerified) {
          await _markCurrentUserVerified();
        }
      }

      return {
        'success': true,
        'user': user,
        'userData': data,
        'emailVerified': true,
      };
    } on FirebaseAuthException catch (error) {
      return {
        'success': false,
        'message': _friendlyAuthMessage(error, fallback: 'Login failed'),
      };
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> resendVerificationEmail() async {
    try {
      final user = await _refreshCurrentUser();
      if (user == null) {
        return {
          'success': false,
          'message': 'Please log in again to resend the verification email.',
        };
      }

      final isVerified = user.emailVerified;
      if (isVerified) {
        try {
          await _markCurrentUserVerified();
        } catch (error) {
          debugPrint('Unable to sync verified status to Firestore: $error');
        }
        return {
          'success': true,
          'message': 'Email is already verified.',
          'alreadyVerified': true,
        };
      }

      await user.sendEmailVerification();
      return {'success': true, 'message': 'Verification email sent'};
    } on FirebaseAuthException catch (error) {
      return {
        'success': false,
        'message': _friendlyAuthMessage(
          error,
          fallback: 'Failed to resend verification email.',
        ),
      };
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) {
      return {
        'success': false,
        'message': 'Please enter a valid email address.',
      };
    }

    try {
      // Known-account gate:
      // 1) Cloud Function (if available)
      // 2) Users profile lookup fallback
      final existsViaFunction = await _hasAccountViaFunction(normalizedEmail);
      final profileExists = existsViaFunction == null
          ? await _hasUserProfileForEmail(normalizedEmail)
          : null;
      final accountExists = existsViaFunction ?? profileExists;
      if (accountExists != true) {
        return {
          'success': false,
          'message': 'This email is not registered. Please register first.',
        };
      }

      await _auth.sendPasswordResetEmail(email: normalizedEmail);
      return {
        'success': true,
        'message': 'Password reset email sent',
      };
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') {
        return {
          'success': false,
          'message': 'This email is not registered. Please register first.',
        };
      }
      return {
        'success': false,
        'message': _friendlyAuthMessage(
          error,
          fallback: 'Failed to send password reset email.',
        ),
      };
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<bool> checkEmailVerified() async {
    try {
      return await _isCurrentUserEmailVerified();
    } catch (error) {
      debugPrint('Email verification refresh failed: $error');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore: user may not have used Google sign-in.
    }
    await AppRepositories.auth.signOut();
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Ignore sign-out failures and continue with a fresh sign-in attempt.
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'message': 'Google sign-in cancelled'};
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if ((idToken == null || idToken.isEmpty) &&
          (accessToken == null || accessToken.isEmpty)) {
        return {
          'success': false,
          'message':
              'Google Sign-In token is missing. Check Firebase Google auth setup for this app and try again.',
        };
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        return {'success': false, 'message': 'Failed to sign in with Google'};
      }

      final doc = await _users.doc(user.uid).get();
      if (!doc.exists) {
        await _users.doc(user.uid).set({
          'uid': user.uid,
          'email': _normalizeEmail(user.email ?? ''),
          'firstName': user.displayName?.split(' ').first ?? '',
          'lastName': user.displayName?.split(' ').skip(1).join(' ') ?? '',
          'fullName': user.displayName ?? '',
          'phone': user.phoneNumber ?? '',
          'photoUrl': user.photoURL ?? '',
          'role': '',
          'status': 'verified',
          'subscriptionTier': 'free',
          'entitlements': {'professionalSupport': false, 'chatAccess': false},
          'notificationPreferences': {
            'pushNotifications': true,
            'emailNotifications': false,
            'dailyReminders': true,
            'activityAlerts': true,
            'progressUpdates': false,
          },
          'authProvider': 'google',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _users.doc(user.uid).set({
          'email': _normalizeEmail(user.email ?? ''),
          'firstName': user.displayName?.split(' ').first ?? '',
          'lastName': user.displayName?.split(' ').skip(1).join(' ') ?? '',
          'fullName': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'status': 'verified',
          'authProvider': 'google',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final refreshed = await _users.doc(user.uid).get();
      final rawRole = refreshed
          .data()?['role']
          ?.toString()
          .trim()
          .toLowerCase();
      final role = (rawRole == 'parent' || rawRole == 'therapist')
          ? rawRole
          : null;

      return {
        'success': true,
        'user': user,
        'isNewUser': !doc.exists,
        'role': role,
      };
    } on PlatformException catch (error) {
      return {'success': false, 'message': _friendlyGoogleSignInError(error)};
    } on FirebaseAuthException catch (error) {
      return {
        'success': false,
        'message': _friendlyAuthMessage(
          error,
          fallback: 'Google sign-in failed',
        ),
      };
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final userDoc = await _users.doc(uid).get();
      if (!userDoc.exists || userDoc.data() == null) {
        return null;
      }
      final userData = Map<String, dynamic>.from(userDoc.data()!);
      final activeChildId = userData['activeChildId']?.toString();
      if (activeChildId != null && activeChildId.isNotEmpty) {
        final childDoc = await _children.doc(activeChildId).get();
        if (childDoc.exists && childDoc.data() != null) {
          final childData = childDoc.data()!;
          userData['childName'] = childData['name'];
          userData['supportAreas'] = childData['supportAreas'];
          userData['childProfile'] = childData;
        }
      }
      return userData;
    } catch (error) {
      debugPrint('Error getting user data: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return getUserData(user.uid);
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user logged in');
    }

    final childName = data.remove('childName');
    final communicationEnabled = data.remove('communicationEnabled');
    final learningPlayEnabled = data.remove('learningPlayEnabled');

    if (data.isNotEmpty) {
      await _users.doc(user.uid).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (childName != null ||
        communicationEnabled != null ||
        learningPlayEnabled != null) {
      final currentData = await getCurrentUserData();
      final activeChildId = currentData?['activeChildId']?.toString();
      if (activeChildId == null || activeChildId.isEmpty) {
        throw Exception('No child profile found for this account');
      }

      final childDoc = await _children.doc(activeChildId).get();
      final supportAreas = <String>[
        if (communicationEnabled == true) 'Communication',
        if (learningPlayEnabled == true) 'Learning & Play',
      ];
      await _children.doc(activeChildId).set({
        'parentId': user.uid,
        'name': childName ?? childDoc.data()?['name'] ?? '',
        if (supportAreas.isNotEmpty) 'supportAreas': supportAreas,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> submitFeedback({
    required String name,
    required String email,
    required String feedback,
  }) async {
    await _firestore.collection(FirestoreCollections.feedback).add({
      'userId': _auth.currentUser?.uid,
      'name': name,
      'email': email,
      'feedback': feedback,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> updateCurrentUserPassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return {
        'success': false,
        'message': 'No authenticated user found. Please log in again.',
      };
    }

    try {
      if (currentPassword != null &&
          currentPassword.isNotEmpty &&
          user.email != null) {
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
      }

      await user.updatePassword(newPassword);
      await _users.doc(user.uid).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return {'success': true, 'message': 'Password updated successfully.'};
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'wrong-password':
          return {
            'success': false,
            'message': 'The current password you entered is incorrect.',
          };
        case 'requires-recent-login':
          return {
            'success': false,
            'message':
                'For security, please log out and log in again before changing your password.',
          };
        case 'weak-password':
          return {
            'success': false,
            'message':
                'Password is too weak. Please choose a stronger password.',
          };
        default:
          return {
            'success': false,
            'message': _friendlyAuthMessage(
              error,
              fallback: 'Failed to update password.',
            ),
          };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<void> signOut() => logout();

  /// Deletes parent-owned Firestore data, the user document, then the Firebase Auth user,
  /// using the same recovery steps as the therapist account deletion flow.
  Future<Map<String, dynamic>> deleteParentAccount() async {
    final currentUser = _auth.currentUser;
    final uid = currentUser?.uid;
    if (uid == null || currentUser == null) {
      return {
        'firestoreDeleted': false,
        'authDeleted': false,
        'authError': '',
        'message': 'No authenticated user found.',
      };
    }

    final lastSignIn = currentUser.metadata.lastSignInTime;
    if (lastSignIn != null && DateTime.now().difference(lastSignIn).inMinutes > 5) {
      return {
        'firestoreDeleted': false,
        'authDeleted': false,
        'authError': 'requires-recent-login',
        'message': 'For security, please sign out and sign back in before deleting your account.',
      };
    }

    var firestoreDeleted = false;
    try {
      await _deleteParentOwnedFirestoreData(uid);
      firestoreDeleted = true;
    } catch (firestoreError) {
      debugPrint('deleteParentAccount Firestore error: $firestoreError');
    }

    var authDeleted = false;
    var authError = '';

    try {
      await currentUser.delete();
      authDeleted = true;
    } catch (authError1) {
      authError = authError1.toString();

      try {
        if (currentUser.email != null) {
          throw Exception('Re-auth not possible without password');
        }
      } catch (_) {
        try {
          await _users.doc(uid).update({
            'markedForDeletion': true,
            'deletionTimestamp': FieldValue.serverTimestamp(),
            'deletionReason': 'User requested account deletion',
          });
          authDeleted = true;
        } catch (markError) {
          try {
            await _users.doc(uid).update({
              'status': 'disabled',
              'disabledByUser': true,
              'disabledTimestamp': FieldValue.serverTimestamp(),
            });
            authDeleted = true;
          } catch (disableError) {
            // Preserve the original authError
          }
        }
      }
    }

    return {
      'firestoreDeleted': firestoreDeleted,
      'authDeleted': authDeleted,
      'authError': authError,
    };
  }

  Future<void> _deleteParentOwnedFirestoreData(String uid) async {
    final threads = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('parentId', isEqualTo: uid)
        .get();
    for (final doc in threads.docs) {
      try {
        await doc.reference.delete();
      } catch (_) {}
    }

    final children = await _children.where('parentId', isEqualTo: uid).get();
    for (final doc in children.docs) {
      final childId = doc.id;
      final progress = await _firestore
          .collection(FirestoreCollections.activityProgress)
          .where('childId', isEqualTo: childId)
          .get();
      for (final p in progress.docs) {
        try {
          await p.reference.delete();
        } catch (_) {}
      }
      final moods = await _firestore
          .collection(FirestoreCollections.moodLogs)
          .where('childId', isEqualTo: childId)
          .get();
      for (final m in moods.docs) {
        try {
          await m.reference.delete();
        } catch (_) {}
      }
      try {
        await _firestore
            .collection(FirestoreCollections.childAssignments)
            .doc(childId)
            .delete();
      } catch (_) {}
      try {
        await _firestore
            .collection(FirestoreCollections.dashboardSnapshots)
            .doc(childId)
            .delete();
      } catch (_) {}
      try {
        await doc.reference.delete();
      } catch (_) {}
    }

    try {
      final subs = await _firestore
          .collection(FirestoreCollections.subscriptions)
          .where('userId', isEqualTo: uid)
          .get();
      for (final s in subs.docs) {
        try {
          await s.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final feedbackSnap = await _firestore
          .collection(FirestoreCollections.feedback)
          .where('userId', isEqualTo: uid)
          .get();
      for (final f in feedbackSnap.docs) {
        try {
          await f.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}

    await _users.doc(uid).delete();
  }
}
