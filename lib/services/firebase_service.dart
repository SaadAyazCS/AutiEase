import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
      _googleSignIn = GoogleSignIn();

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
      if (data is Map && data['exists'] is bool) {
        return data['exists'] as bool;
      }
      return null;
    } on FirebaseFunctionsException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _friendlyAuthMessage(
    FirebaseAuthException error, {
    required String fallback,
  }) {
    switch (error.code) {
      case 'too-many-requests':
        return 'Too many attempts from this device. Wait 30-60 minutes, then try once.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      case 'email-already-in-use':
        return 'This email is already registered. Please log in instead.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return error.message ?? fallback;
    }
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
    User? resolvedUser;
    var createdPasswordUser = false;
    var isExistingGoogleUser = false;

    try {
      final existingUser = _auth.currentUser;
      final existingEmail = existingUser?.email?.trim().toLowerCase();
      final requestedEmail = email.trim().toLowerCase();
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
              email: email,
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
            email: email,
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
        email: email,
        firstName: firstName,
        lastName: lastName,
        role: 'parent',
        status: user.emailVerified || isExistingGoogleUser
            ? 'verified'
            : 'unverified',
        phone: phone,
        photoUrl: user.photoURL ?? '',
        subscriptionTier: 'free',
        entitlements: const {'professionalSupport': false, 'chatAccess': false},
        notificationPreferences: const {
          'pushNotifications': true,
          'emailNotifications': false,
          'dailyReminders': true,
          'activityAlerts': true,
          'progressUpdates': false,
        },
        activeChildId: childProfile.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      try {
        final wantsCommunication = supportArea.any(
          (entry) => entry.toLowerCase().contains('communication'),
        );
        final wantsLearning = supportArea.any(
          (entry) => entry.toLowerCase().contains('learning'),
        );

        final defaultModules = wantsLearning
            ? await AppRepositories.content.getAllLearningModules()
            : const <LearningModuleModel>[];
        final defaultActivities = wantsLearning
            ? await AppRepositories.content.getAllActivityTemplates()
            : const <DailyActivityTemplate>[];
        final defaultCommunicationIds = wantsCommunication
            ? List<String>.from(CommunicationFigmaCatalog.homeBoardOrder)
            : const <String>[];

        await AppRepositories.users.upsertParentProfile(profile);
        await _users.doc(user.uid).set({
          'authProvider': isExistingGoogleUser ? 'google' : 'password',
        }, SetOptions(merge: true));
        await AppRepositories.users.upsertChildProfile(childProfile);
        await AppRepositories.planner.saveAssignment(
          ChildAssignment(
            id: childProfile.id,
            childId: childProfile.id,
            parentId: user.uid,
            assignedCategoryIds: defaultCommunicationIds,
            assignedModuleIds: defaultModules
                .map((module) => module.id)
                .toList(),
            assignedActivityTemplateIds: defaultActivities
                .map((activity) => activity.id)
                .toList(),
            status: 'active',
            effectiveFrom: DateTime.now(),
          ),
        );
        await _firestore
            .collection(FirestoreCollections.dashboardSnapshots)
            .doc(childProfile.id)
            .set({
              'completedTasks': 0,
              'weeklyMinutes': 0,
              'streakDays': 0,
              'moodEntries': 0,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (_) {
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
    User? resolvedUser;
    var createdPasswordUser = false;
    var isExistingGoogleUser = false;

    try {
      final existingUser = _auth.currentUser;
      final existingEmail = existingUser?.email?.trim().toLowerCase();
      final requestedEmail = email.trim().toLowerCase();
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
              email: email,
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
            email: email,
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

      final profile = UserProfile(
        uid: user.uid,
        email: email,
        firstName: firstName,
        lastName: lastName,
        role: 'therapist',
        status: user.emailVerified || isExistingGoogleUser
            ? 'verified'
            : 'unverified',
        phone: phone,
        photoUrl: user.photoURL ?? '',
        subscriptionTier: 'provider',
        entitlements: const {'professionalSupport': true, 'chatAccess': true},
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
        await AppRepositories.users.upsertParentProfile(profile);
        await _users.doc(user.uid).set({
          'authProvider': isExistingGoogleUser ? 'google' : 'password',
        }, SetOptions(merge: true));
        await AppRepositories.users.upsertTherapistProfile(
          TherapistProfile(
            id: user.uid,
            displayName: '$firstName $lastName'.trim(),
            bio: '',
            specializations: [
              if (specialization != null && specialization.isNotEmpty)
                specialization,
            ],
            pricing: '',
            languages: const ['English'],
            rating: 0,
            availability: 'Contact for availability',
            photoUrl: user.photoURL ?? '',
            isActive: true,
          ),
        );

        await _therapists.doc(user.uid).set({
          'licenseNumber': licenseNumber ?? '',
          'contactEmail': email,
          'contactPhone': phone,
        }, SetOptions(merge: true));
      } catch (_) {
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

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = await _refreshCurrentUser() ?? credential.user;
      if (user == null) {
        return {'success': false, 'message': 'Login failed'};
      }

      final userDoc = await _users.doc(user.uid).get();
      final data = userDoc.data() ?? <String, dynamic>{};

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

      return {
        'success': true,
        'user': user,
        'userData': data,
        'emailVerified': isVerified,
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
      if (accountExists == false) {
        return {
          'success': false,
          'message': 'No account found for this email.',
        };
      }

      await _auth.sendPasswordResetEmail(email: normalizedEmail);
      return {
        'success': true,
        'message': accountExists == null
            ? 'If an account exists for this email, a password reset link has been sent.'
            : 'Password reset email sent',
      };
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') {
        return {
          'success': false,
          'message': 'No account found for this email.',
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
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'message': 'Google sign-in cancelled'};
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        return {
          'success': false,
          'message': 'Google sign-in token is missing. Please try again.',
        };
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
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

  Future<void> signOut() => logout();
}
