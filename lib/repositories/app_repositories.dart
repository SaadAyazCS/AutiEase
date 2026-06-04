import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_runtime_config.dart';
import '../models/app_models.dart';
import '../services/auth_verification_policy.dart';
import '../services/dashboard_metrics_calculator.dart';
import '../services/stripe_backend_client.dart';

class FirestoreCollections {
  static const users = 'users';
  static const childProfiles = 'child_profiles';
  static const therapistProfiles = 'therapist_profiles';
  static const contentCategories = 'content_categories';
  static const contentItems = 'content_items';
  static const learningModules = 'learning_modules';
  static const dailyActivityTemplates = 'daily_activity_templates';
  static const childAssignments = 'child_assignments';
  static const activityProgress = 'activity_progress';
  static const moodLogs = 'mood_logs';
  static const dashboardSnapshots = 'dashboard_snapshots';
  static const therapistThreads = 'therapist_threads';
  static const subscriptionProducts = 'subscription_products';
  static const subscriptions = 'subscriptions';
  static const legalDocuments = 'legal_documents';
  static const appModules = 'app_modules';
  static const settingsEntries = 'settings_entries';
  static const feedback = 'feedback';
  static const learningMetrics = 'learning_metrics';
  static const communicationSentenceSettings =
      'communication_sentence_settings';
}

abstract class AuthRepository {
  User? get currentUser;
  Future<AppSession> resolveSession();
  Future<void> signOut();
}

abstract class UserRepository {
  Future<UserProfile?> getCurrentUserProfile();
  Future<UserProfile?> getUserProfile(String uid);
  Future<ChildProfile?> getActiveChildForCurrentParent();
  Future<List<ChildProfile>> getChildrenForParent(String parentId);
  Future<void> upsertParentProfile(UserProfile profile);
  Future<void> upsertChildProfile(ChildProfile profile);
  Future<void> upsertTherapistProfile(TherapistProfile profile);
  Future<void> updateNotificationPreferences(Map<String, bool> preferences);
  Future<void> updateCurrentUser(Map<String, dynamic> data);
}

abstract class ContentRepository {
  Stream<List<AppModule>> watchModules(String targetRole);
  Stream<ProfessionalSupportFeatureFlags>
  watchProfessionalSupportFeatureFlags();
  Future<ProfessionalSupportFeatureFlags> getProfessionalSupportFeatureFlags();
  Future<List<ContentCategory>> getAssignedCategories(
    String childId, {
    String? type,
  });
  Future<List<ContentItem>> getItemsForCategory(String categoryId);
  Future<List<LearningModuleModel>> getAssignedLearningModules(String childId);
  Future<List<DailyActivityTemplate>> getAssignedActivities(String childId);
  Future<List<ContentItem>> getAllContentItems();
  Future<List<SettingsEntry>> getSettingsEntries(String targetRole);
  Future<LegalDocument?> getLegalDocument(String audience, String documentId);
  Future<List<ContentCategory>> getAllCategories({String? type});
  Future<List<LearningModuleModel>> getAllLearningModules();
  Future<List<DailyActivityTemplate>> getAllActivityTemplates();
}

abstract class PlannerRepository {
  Future<ChildAssignment?> getAssignmentForChild(String childId);
  Future<void> saveAssignment(ChildAssignment assignment);
  Stream<DashboardSnapshot?> watchDashboard(String childId);
  Stream<DashboardMetrics?> watchDashboardMetrics(String childId);
  Future<void> recordMood({
    required String childId,
    required String emotion,
    String note,
  });
  Future<void> recordActivityCompletion({
    required String childId,
    required String itemId,
    String? moduleId,
    int score = 0,
    Map<String, dynamic>? metadata,
  });
  Future<void> undoActivityCompletion({
    required String childId,
    required String itemId,
  });
}

abstract class SupportRepository {
  Future<List<TherapistProfile>> listTherapists();
  Future<TherapistProfile?> getTherapistById(String therapistId);
  Stream<List<TherapistThread>> watchThreadsForRole(String role);
  Stream<TherapistThread?> watchThread(String threadId);
  Future<TherapistThread> ensureThread({
    required String therapistId,
    required String childId,
    required String subscriptionId,
  });
  Stream<List<TherapistMessage>> watchMessages(String threadId);
  Future<void> sendMessage({
    required String threadId,
    required String senderRole,
    required String body,
    List<String> attachments = const <String>[],
    String messageType = 'text',
  });
  Future<void> requestEmergency({
    required String threadId,
    required String requestedByRole,
  });
  Future<void> resolveEmergency({
    required String threadId,
    required String resolvedByRole,
  });

  // Reviews & Feedback
  Future<void> submitReview({
    required String therapistId,
    required int rating,
    required String feedback,
    String privateFeedback = '',
  });
  Stream<List<TherapistReview>> watchReviewsForTherapist(String therapistId);

  // User Reporting & Blocking
  Future<void> submitReport({
    required String reportedId,
    required String reason,
    required String comments,
    required List<Map<String, dynamic>> chatContext,
  });
  Future<void> blockUser({required String blockedId});
  Future<void> unblockUser({required String blockedId});
  Future<bool> isUserBlocked(String userId);

  // In-app Notifications
  Stream<List<NotificationInboxItem>> watchNotifications();
  Future<void> markNotificationAsRead(String notificationId);
  Future<void> markAllNotificationsAsRead();
  Future<int> getUnreadNotificationCount();
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String message,
    required String category,
    Map<String, dynamic> navigationTarget = const <String, dynamic>{},
  });

  // FCM Device Tokens
  Future<void> saveFcmToken(String token);
}

abstract class AdminRepository {
  Future<Map<String, dynamic>> getAnalyticsStats();
  Future<List<UserProfile>> listParents();
  Future<List<TherapistProfile>> listTherapistsByStatus(String status);
  Future<void> verifyTherapist({
    required String therapistId,
    required String status, // 'approved', 'rejected', 'pending', 'suspended'
    String adminFeedback = '',
    DateTime? licenseExpiryDate,
  });
  Stream<List<UserReport>> watchReports();
  Future<void> updateReportStatus(String reportId, String status);
  Future<void> executeModerationAction({
    required String reportedUserId,
    required String action, // 'warn', 'suspend', 'ban', 'dismiss'
    String reason = '',
  });
  Future<List<Map<String, dynamic>>> listAllFeedbackAndReviews();
  Future<List<AdminAuditLog>> listAuditLogs();
}

abstract class BillingRepository {
  Future<List<SubscriptionProduct>> listProducts();
  Future<UserSubscription?> getCurrentSubscription();
  Future<String?> createCheckoutSession({
    required String productId,
    required String successUrl,
    required String cancelUrl,
  });
  Future<void> cancelSubscription(String subscriptionId);
  Future<void> reactivateSubscription(String subscriptionId);
}

class AppRepositories {
  AppRepositories._();

  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseAuth authClient = FirebaseAuth.instance;
  static final StripeBackendClient stripeBackend = StripeBackendClient(
    authClient,
  );

  static final AuthRepository auth = FirebaseAuthRepository(
    authClient,
    firestore,
  );
  static final UserRepository users = FirebaseUserRepository(
    authClient,
    firestore,
  );
  static final ContentRepository content = FirebaseContentRepository(firestore);
  static final PlannerRepository planner = FirebasePlannerRepository(firestore);
  static final SupportRepository support = FirebaseSupportRepository(
    authClient,
    firestore,
  );
  static final AdminRepository admin = FirebaseAdminRepository(
    authClient,
    firestore,
  );
  static final BillingRepository billing = FirebaseBillingRepository(
    authClient,
    firestore,
    stripeBackend,
  );
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<AppSession> resolveSession() async {
    var user = currentUser;
    if (user == null) {
      return const AppSession(state: AppSessionState.unauthenticated);
    }

    try {
      await user.getIdToken(true);
      await user.reload();
      user = _auth.currentUser;
    } catch (_) {
      // If refresh fails, continue with the last known auth user and let the
      // downstream checks decide whether the session is usable.
    }

    if (user == null) {
      return const AppSession(state: AppSessionState.unauthenticated);
    }

    final isGoogleUser = user.providerData.any(
      (provider) => provider.providerId == 'google.com',
    );

    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .get();

    if (!doc.exists || doc.data() == null) {
      return AppSession(
        state: AppSessionState.incompleteProfile,
        uid: user.uid,
      );
    }

    final profile = UserProfile.fromMap(doc.id, doc.data()!);
    if (profile.role.isEmpty) {
      return AppSession(
        state: AppSessionState.incompleteProfile,
        uid: user.uid,
      );
    }

    if (requiresEmailVerification(
      isGoogleUser: isGoogleUser,
      isEmailVerified: user.emailVerified,
    )) {
      return AppSession(
        state: AppSessionState.emailVerificationPending,
        uid: user.uid,
      );
    }

    if (profile.role == 'parent') {
      final childSnapshot = await _firestore
          .collection(FirestoreCollections.childProfiles)
          .where('parentId', isEqualTo: profile.uid)
          .limit(1)
          .get();
      if (childSnapshot.docs.isEmpty) {
        return AppSession(
          state: AppSessionState.incompleteProfile,
          uid: profile.uid,
          role: profile.role,
        );
      }
      return AppSession(
        state: AppSessionState.parent,
        uid: profile.uid,
        role: profile.role,
        activeChildId: profile.activeChildId,
      );
    }

    if (profile.role == 'therapist') {
      return AppSession(
        state: AppSessionState.therapist,
        uid: profile.uid,
        role: profile.role,
      );
    }

    if (profile.role == 'admin') {
      return AppSession(
        state: AppSessionState.admin,
        uid: profile.uid,
        role: profile.role,
      );
    }

    return AppSession(
      state: AppSessionState.incompleteProfile,
      uid: profile.uid,
      role: profile.role,
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

class FirebaseUserRepository implements UserRepository {
  FirebaseUserRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestoreCollections.users);

  CollectionReference<Map<String, dynamic>> get _children =>
      _firestore.collection(FirestoreCollections.childProfiles);

  CollectionReference<Map<String, dynamic>> get _therapists =>
      _firestore.collection(FirestoreCollections.therapistProfiles);
  static const Set<String> _supportedParentNotificationKeys = <String>{
    'therapistsUpdate',
    'levelProgressNotification',
    'subscription',
    'routineReminders',
  };
  static const Set<String> _legacyParentNotificationKeys = <String>{
    'activityAlerts',
    'dailyReminder',
    'dailyReminders',
    'emailNotifications',
    'progressUpdates',
    'pushNotifications',
  };

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return getUserProfile(user.uid);
  }

  @override
  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return UserProfile.fromMap(doc.id, doc.data()!);
  }

  @override
  Future<List<ChildProfile>> getChildrenForParent(String parentId) async {
    final snapshot = await _children
        .where('parentId', isEqualTo: parentId)
        .orderBy('name')
        .get();
    return snapshot.docs
        .map((doc) => ChildProfile.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<ChildProfile?> getActiveChildForCurrentParent() async {
    final profile = await getCurrentUserProfile();
    if (profile == null) {
      return null;
    }
    if (profile.activeChildId != null && profile.activeChildId!.isNotEmpty) {
      final activeDoc = await _children.doc(profile.activeChildId).get();
      if (activeDoc.exists && activeDoc.data() != null) {
        return ChildProfile.fromMap(activeDoc.id, activeDoc.data()!);
      }
    }

    final children = await getChildrenForParent(profile.uid);
    if (children.isEmpty) {
      return null;
    }

    final activeChild = children.first;
    await _users.doc(profile.uid).set({
      'activeChildId': activeChild.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return activeChild;
  }

  @override
  Future<void> updateCurrentUser(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No logged in user');
    }
    await _users.doc(user.uid).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateNotificationPreferences(
    Map<String, bool> preferences,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No logged in user');
    }

    final profile = await getCurrentUserProfile();
    if (profile?.role != 'parent') {
      await updateCurrentUser({'notificationPreferences': preferences});
      return;
    }

    final sanitized = <String, bool>{
      for (final key in _supportedParentNotificationKeys)
        key: preferences[key] ?? false,
    };
    final existingKeys =
        profile?.notificationPreferences.keys.toSet() ?? <String>{};
    final nestedKeysToDelete = existingKeys
        .difference(_supportedParentNotificationKeys)
        .union(_legacyParentNotificationKeys);

    final payload = <String, dynamic>{
      for (final entry in sanitized.entries)
        'notificationPreferences.${entry.key}': entry.value,
      for (final key in nestedKeysToDelete)
        'notificationPreferences.$key': FieldValue.delete(),
      for (final key in _legacyParentNotificationKeys) key: FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _users.doc(user.uid).update(payload);
  }

  @override
  Future<void> upsertParentProfile(UserProfile profile) async {
    await _users.doc(profile.uid).set({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': profile.createdAt ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> upsertChildProfile(ChildProfile profile) async {
    await _children.doc(profile.id).set({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': profile.createdAt ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> upsertTherapistProfile(TherapistProfile profile) async {
    await _therapists.doc(profile.id).set({
      'displayName': profile.displayName,
      'bio': profile.bio,
      'specializations': profile.specializations,
      'pricing': profile.pricing,
      'languages': profile.languages,
      'rating': profile.rating,
      'availability': profile.availability,
      'photoUrl': profile.photoUrl,
      'isActive': profile.isActive,
      'experience_years': profile.yearsOfExperience,
      'experience_months': profile.experienceMonths,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class FirebaseContentRepository implements ContentRepository {
  FirebaseContentRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const _professionalSupportModuleId = 'professional_support';

  @override
  Stream<List<AppModule>> watchModules(String targetRole) {
    return _firestore
        .collection(FirestoreCollections.appModules)
        .where('targetRole', whereIn: [targetRole, 'all'])
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final modules = snapshot.docs
              .map((doc) => AppModule.fromMap(doc.id, doc.data()))
              .toList();
          modules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return modules;
        });
  }

  @override
  Stream<ProfessionalSupportFeatureFlags>
  watchProfessionalSupportFeatureFlags() {
    return _firestore
        .collection(FirestoreCollections.appModules)
        .doc(_professionalSupportModuleId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return ProfessionalSupportFeatureFlags.enabled;
          }
          return ProfessionalSupportFeatureFlags.fromAppModuleMap(
            mapFrom(snapshot.data()),
          );
        });
  }

  @override
  Future<ProfessionalSupportFeatureFlags>
  getProfessionalSupportFeatureFlags() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.appModules)
        .doc(_professionalSupportModuleId)
        .get();
    if (!snapshot.exists || snapshot.data() == null) {
      return ProfessionalSupportFeatureFlags.enabled;
    }
    return ProfessionalSupportFeatureFlags.fromAppModuleMap(
      mapFrom(snapshot.data()),
    );
  }

  @override
  Future<List<ContentCategory>> getAllCategories({String? type}) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestoreCollections.contentCategories)
        .where('isActive', isEqualTo: true);
    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type);
    }
    final snapshot = await query.get();
    final categories = snapshot.docs
        .map((doc) => ContentCategory.fromMap(doc.id, doc.data()))
        .toList();
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  @override
  Future<List<ContentCategory>> getAssignedCategories(
    String childId, {
    String? type,
  }) async {
    final assignmentDoc = await _firestore
        .collection(FirestoreCollections.childAssignments)
        .doc(childId)
        .get();
    if (!assignmentDoc.exists || assignmentDoc.data() == null) {
      return const [];
    }

    final assignment = ChildAssignment.fromMap(childId, assignmentDoc.data()!);
    if (assignment.assignedCategoryIds.isEmpty) {
      return const [];
    }

    final snapshot = await _firestore
        .collection(FirestoreCollections.contentCategories)
        .where(FieldPath.documentId, whereIn: assignment.assignedCategoryIds)
        .get();

    final categories = snapshot.docs
        .map((doc) => ContentCategory.fromMap(doc.id, doc.data()))
        .where((category) => category.isActive)
        .where((category) => type == null || category.type == type)
        .toList();
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  @override
  Future<List<ContentItem>> getItemsForCategory(String categoryId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.contentItems)
        .where('categoryId', isEqualTo: categoryId)
        .where('isActive', isEqualTo: true)
        .get();
    final items = snapshot.docs
        .map((doc) => ContentItem.fromMap(doc.id, doc.data()))
        .toList();
    items.sort((a, b) => a.level.compareTo(b.level));
    return items;
  }

  @override
  Future<List<ContentItem>> getAllContentItems() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.contentItems)
        .where('isActive', isEqualTo: true)
        .get();
    final items = snapshot.docs
        .map((doc) => ContentItem.fromMap(doc.id, doc.data()))
        .toList();
    items.sort((a, b) => a.title.compareTo(b.title));
    return items;
  }

  @override
  Future<List<LearningModuleModel>> getAllLearningModules() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.learningModules)
        .where('isActive', isEqualTo: true)
        .get();
    final modules = snapshot.docs
        .map((doc) => LearningModuleModel.fromMap(doc.id, doc.data()))
        .toList();
    modules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return modules;
  }

  @override
  Future<List<DailyActivityTemplate>> getAllActivityTemplates() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.dailyActivityTemplates)
        .where('isActive', isEqualTo: true)
        .get();
    final activities = snapshot.docs
        .map((doc) => DailyActivityTemplate.fromMap(doc.id, doc.data()))
        .toList();
    activities.sort((a, b) => a.title.compareTo(b.title));
    return activities;
  }

  @override
  Future<List<LearningModuleModel>> getAssignedLearningModules(
    String childId,
  ) async {
    final assignmentDoc = await _firestore
        .collection(FirestoreCollections.childAssignments)
        .doc(childId)
        .get();
    if (!assignmentDoc.exists || assignmentDoc.data() == null) {
      return const [];
    }
    final assignment = ChildAssignment.fromMap(childId, assignmentDoc.data()!);
    if (assignment.assignedModuleIds.isEmpty) {
      return const [];
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.learningModules)
        .where(FieldPath.documentId, whereIn: assignment.assignedModuleIds)
        .get();
    final modules = snapshot.docs
        .map((doc) => LearningModuleModel.fromMap(doc.id, doc.data()))
        .where((module) => module.isActive)
        .toList();
    modules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return modules;
  }

  @override
  Future<List<DailyActivityTemplate>> getAssignedActivities(
    String childId,
  ) async {
    final assignmentDoc = await _firestore
        .collection(FirestoreCollections.childAssignments)
        .doc(childId)
        .get();
    if (!assignmentDoc.exists || assignmentDoc.data() == null) {
      return const [];
    }
    final assignment = ChildAssignment.fromMap(childId, assignmentDoc.data()!);
    if (assignment.assignedActivityTemplateIds.isEmpty) {
      return const [];
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.dailyActivityTemplates)
        .where(
          FieldPath.documentId,
          whereIn: assignment.assignedActivityTemplateIds,
        )
        .get();
    return snapshot.docs
        .map((doc) => DailyActivityTemplate.fromMap(doc.id, doc.data()))
        .where((template) => template.isActive)
        .toList();
  }

  @override
  Future<LegalDocument?> getLegalDocument(
    String audience,
    String documentId,
  ) async {
    final doc = await _firestore
        .collection(FirestoreCollections.legalDocuments)
        .doc(documentId)
        .get();
    if (doc.exists && doc.data() != null) {
      final legal = LegalDocument.fromMap(doc.id, doc.data()!);
      if (legal.isActive && legal.audience == audience) {
        return legal;
      }
    }

    final snapshot = await _firestore
        .collection(FirestoreCollections.legalDocuments)
        .where('audience', isEqualTo: audience)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return LegalDocument.fromMap(
      snapshot.docs.first.id,
      snapshot.docs.first.data(),
    );
  }

  @override
  Future<List<SettingsEntry>> getSettingsEntries(String targetRole) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.settingsEntries)
        .where('targetRole', whereIn: [targetRole, 'all'])
        .where('isActive', isEqualTo: true)
        .get();
    final entries = snapshot.docs
        .map((doc) => SettingsEntry.fromMap(doc.id, doc.data()))
        .toList();
    entries.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return entries;
  }
}

class FirebasePlannerRepository implements PlannerRepository {
  FirebasePlannerRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final DashboardMetricsCalculator _calculator = DashboardMetricsCalculator();

  @override
  Future<ChildAssignment?> getAssignmentForChild(String childId) async {
    final doc = await _firestore
        .collection(FirestoreCollections.childAssignments)
        .doc(childId)
        .get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return ChildAssignment.fromMap(doc.id, doc.data()!);
  }

  @override
  Future<void> saveAssignment(ChildAssignment assignment) async {
    await _firestore
        .collection(FirestoreCollections.childAssignments)
        .doc(assignment.id)
        .set({
          ...assignment.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Stream<DashboardSnapshot?> watchDashboard(String childId) {
    return _firestore
        .collection(FirestoreCollections.dashboardSnapshots)
        .doc(childId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return DashboardSnapshot.fromMap(doc.id, doc.data()!);
        });
  }

  @override
  Stream<DashboardMetrics?> watchDashboardMetrics(String childId) {
    final progressStream = _firestore
        .collection(FirestoreCollections.activityProgress)
        .where('childId', isEqualTo: childId)
        .snapshots();
    final moodStream = _firestore
        .collection(FirestoreCollections.moodLogs)
        .where('childId', isEqualTo: childId)
        .snapshots();

    return Stream<DashboardMetrics?>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestProgress;
      QuerySnapshot<Map<String, dynamic>>? latestMoods;
      var cancelled = false;

      Future<void> emitIfReady() async {
        if (cancelled || latestProgress == null || latestMoods == null) {
          return;
        }
        try {
          final metrics = await _buildMetrics(
            childId: childId,
            progressSnapshot: latestProgress!,
            moodSnapshot: latestMoods!,
          );
          if (!cancelled) {
            controller.add(metrics);
          }
        } catch (error, stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
          }
        }
      }

      final progressSub = progressStream.listen((snapshot) {
        latestProgress = snapshot;
        emitIfReady();
      }, onError: controller.addError);

      final moodSub = moodStream.listen((snapshot) {
        latestMoods = snapshot;
        emitIfReady();
      }, onError: controller.addError);

      controller.onCancel = () async {
        cancelled = true;
        await progressSub.cancel();
        await moodSub.cancel();
      };
    });
  }

  Future<DashboardMetrics> _buildMetrics({
    required String childId,
    required QuerySnapshot<Map<String, dynamic>> progressSnapshot,
    required QuerySnapshot<Map<String, dynamic>> moodSnapshot,
  }) async {
    final activityEvents = progressSnapshot.docs
        .map((doc) => ActivityProgressEntry.fromMap(doc.id, doc.data()))
        .where((event) => event.status.toLowerCase() == 'completed')
        .toList();
    final moodLogs = moodSnapshot.docs
        .map((doc) => MoodLogEntry.fromMap(doc.id, doc.data()))
        .toList();

    final assignment = await getAssignmentForChild(childId);
    final assignedModules = await _fetchLearningModules(
      assignment?.assignedModuleIds ?? const <String>[],
    );
    final assignedTemplates = await _fetchActivityTemplates(
      assignment?.assignedActivityTemplateIds ?? const <String>[],
    );
    final customActivities =
        assignment?.customDailyActivities ?? const <CustomDailyActivity>[];
    final totalDailyActivitiesAssigned =
        assignedTemplates.length + customActivities.length;

    return _calculator.build(
      childId: childId,
      activityEvents: activityEvents,
      moodLogs: moodLogs,
      assignedModules: assignedModules,
      assignedTemplates: assignedTemplates,
      customActivities: customActivities,
      totalDailyActivitiesAssigned: totalDailyActivitiesAssigned,
    );
  }

  Future<List<LearningModuleModel>> _fetchLearningModules(
    List<String> moduleIds,
  ) async {
    final normalizedIds = moduleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedIds.isEmpty) {
      return const <LearningModuleModel>[];
    }
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final chunk in _chunkIds(normalizedIds)) {
      final snapshot = await _firestore
          .collection(FirestoreCollections.learningModules)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      docs.addAll(snapshot.docs);
    }
    final modules = docs
        .map((doc) => LearningModuleModel.fromMap(doc.id, doc.data()))
        .where((module) => module.isActive)
        .toList();
    modules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return modules;
  }

  Future<List<DailyActivityTemplate>> _fetchActivityTemplates(
    List<String> templateIds,
  ) async {
    final normalizedIds = templateIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedIds.isEmpty) {
      return const <DailyActivityTemplate>[];
    }
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final chunk in _chunkIds(normalizedIds)) {
      final snapshot = await _firestore
          .collection(FirestoreCollections.dailyActivityTemplates)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      docs.addAll(snapshot.docs);
    }
    final templates = docs
        .map((doc) => DailyActivityTemplate.fromMap(doc.id, doc.data()))
        .where((template) => template.isActive)
        .toList();
    templates.sort((a, b) => a.title.compareTo(b.title));
    return templates;
  }

  Iterable<List<String>> _chunkIds(List<String> ids, {int size = 10}) sync* {
    if (ids.isEmpty) {
      return;
    }
    var index = 0;
    while (index < ids.length) {
      final end = (index + size) < ids.length ? index + size : ids.length;
      yield ids.sublist(index, end);
      index = end;
    }
  }

  @override
  Future<void> recordMood({
    required String childId,
    required String emotion,
    String note = '',
  }) async {
    await _firestore.collection(FirestoreCollections.moodLogs).add({
      'childId': childId,
      'emotion': emotion,
      'note': note,
      'source': 'app',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> recordActivityCompletion({
    required String childId,
    required String itemId,
    String? moduleId,
    int score = 0,
    Map<String, dynamic>? metadata,
  }) async {
    await _firestore.collection(FirestoreCollections.activityProgress).add({
      'childId': childId,
      'itemId': itemId,
      'moduleId': moduleId,
      'status': 'completed',
      'score': score,
      'attempts': 1,
      'completedAt': FieldValue.serverTimestamp(),
      if (metadata != null) ...metadata,
    });
  }

  @override
  Future<void> undoActivityCompletion({
    required String childId,
    required String itemId,
  }) async {
    await _firestore.collection(FirestoreCollections.activityProgress).add({
      'childId': childId,
      'itemId': itemId,
      'moduleId': itemId,
      'status': 'undone',
      'score': 0,
      'attempts': 1,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }
}

class FirebaseSupportRepository implements SupportRepository {
  FirebaseSupportRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String _resolveParentDisplayName(Map<String, dynamic>? data) {
    if (data == null) {
      return '';
    }
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return (data['fullName'] ?? data['email'] ?? '').toString();
  }

  @override
  Future<TherapistProfile?> getTherapistById(String therapistId) async {
    final doc = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .doc(therapistId)
        .get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return TherapistProfile.fromMap(doc.id, doc.data()!);
  }

  @override
  Future<List<TherapistProfile>> listTherapists() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .where('isActive', isEqualTo: true)
        .get();
    final therapists = snapshot.docs
        .map((doc) => TherapistProfile.fromMap(doc.id, doc.data()))
        .where((t) => t.verificationStatus == 'approved') // Only approved visible in Professional Support listings!
        .toList();
    therapists.sort((a, b) {
      final aHasReviews = a.totalReviews > 0;
      final bHasReviews = b.totalReviews > 0;
      if (aHasReviews && !bHasReviews) return -1;
      if (!aHasReviews && bHasReviews) return 1;
      if (aHasReviews && bHasReviews) {
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.totalReviews.compareTo(a.totalReviews);
      }
      return 0;
    });
    return therapists;
  }

  @override
  Stream<List<TherapistThread>> watchThreadsForRole(String role) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return const Stream<List<TherapistThread>>.empty();
    }

    final field = role == 'therapist' ? 'therapistId' : 'parentId';
    return _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where(field, isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final threads = snapshot.docs
              .map((doc) => TherapistThread.fromMap(doc.id, doc.data()))
              .toList();
          threads.sort((a, b) {
            final left =
                a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
          return threads;
        });
  }

  @override
  Stream<TherapistThread?> watchThread(String threadId) {
    return _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return TherapistThread.fromMap(doc.id, doc.data()!);
        });
  }

  @override
  Future<TherapistThread> ensureThread({
    required String therapistId,
    required String childId,
    required String subscriptionId,
  }) async {
    final parentId = _auth.currentUser?.uid;
    if (parentId == null) {
      throw StateError('No logged in user');
    }

    final parentDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(parentId)
        .get();
    final therapistDoc = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .doc(therapistId)
        .get();
    final parentDisplayName = _resolveParentDisplayName(parentDoc.data());
    final therapistDisplayName = (therapistDoc.data()?['displayName'] ?? '')
        .toString();

    final existing = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('parentId', isEqualTo: parentId)
        .where('therapistId', isEqualTo: therapistId)
        .where('childId', isEqualTo: childId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      final existingThread = TherapistThread.fromMap(
        existing.docs.first.id,
        existing.docs.first.data(),
      );
      final needsMetadataPatch =
          existingThread.parentDisplayName.isEmpty ||
          existingThread.therapistDisplayName.isEmpty;
      if (needsMetadataPatch) {
        await existing.docs.first.reference.set({
          'parentDisplayName': parentDisplayName,
          'therapistDisplayName': therapistDisplayName,
        }, SetOptions(merge: true));
        return existingThread.copyWith(
          parentDisplayName: parentDisplayName,
          therapistDisplayName: therapistDisplayName,
        );
      }
      return existingThread;
    }

    final ref = _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc();
    final thread = TherapistThread(
      id: ref.id,
      parentId: parentId,
      therapistId: therapistId,
      childId: childId,
      subscriptionId: subscriptionId,
      status: 'active',
      parentDisplayName: parentDisplayName,
      therapistDisplayName: therapistDisplayName,
      lastMessageAt: DateTime.now(),
      emergencyStatus: 'none',
      postCancelVisible: true,
    );
    await ref.set({
      ...thread.toMap(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return thread;
  }

  @override
  Stream<List<TherapistMessage>> watchMessages(String threadId) {
    return _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TherapistMessage.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<void> sendMessage({
    required String threadId,
    required String senderRole,
    required String body,
    List<String> attachments = const <String>[],
    String messageType = 'text',
  }) async {
    final senderId = _auth.currentUser?.uid;
    if (senderId == null) {
      throw StateError('No logged in user');
    }
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .collection('messages')
        .add({
          'senderId': senderId,
          'senderRole': senderRole,
          'body': body,
          'attachments': attachments,
          'messageType': messageType,
          'deliveryStatus': 'sent',
          'sentAt': FieldValue.serverTimestamp(),
        });

    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessagePreview': messageType == 'report' 
              ? '📄 PDF Report Shared'
              : body.length <= 120
                  ? body
                  : '${body.substring(0, 117)}...',
        }, SetOptions(merge: true));
  }

  @override
  Future<void> requestEmergency({
    required String threadId,
    required String requestedByRole,
  }) async {
    final senderId = _auth.currentUser?.uid;
    if (senderId == null) {
      throw StateError('No logged in user');
    }
    final threadRef = _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId);

    await threadRef.collection('messages').add({
      'senderId': senderId,
      'senderRole': requestedByRole,
      'body': 'Emergency support requested.',
      'attachments': const <String>[],
      'messageType': 'system',
      'deliveryStatus': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
    });

    await threadRef.set({
      'emergencyStatus': 'requested',
      'emergencyRequestedBy': requestedByRole,
      'emergencyRequestedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': 'Emergency support requested.',
    }, SetOptions(merge: true));
  }

  @override
  Future<void> resolveEmergency({
    required String threadId,
    required String resolvedByRole,
  }) async {
    final senderId = _auth.currentUser?.uid;
    if (senderId == null) {
      throw StateError('No logged in user');
    }
    final threadRef = _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId);

    await threadRef.collection('messages').add({
      'senderId': senderId,
      'senderRole': resolvedByRole,
      'body': 'Emergency support responded.',
      'attachments': const <String>[],
      'messageType': 'system',
      'deliveryStatus': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
    });

    await threadRef.set({
      'emergencyStatus': 'responded',
      'emergencyRespondedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': 'Emergency support responded.',
    }, SetOptions(merge: true));
  }

  // Reviews & Feedback
  @override
  Future<void> submitReview({
    required String therapistId,
    required int rating,
    required String feedback,
    String privateFeedback = '',
  }) async {
    final parentId = _auth.currentUser?.uid;
    if (parentId == null) throw StateError('No logged in user');
    final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
    final parentName = _resolveParentDisplayName(parentDoc.data());

    final reviewId = '${parentId}_$therapistId';
    final reviewRef = _firestore.collection('therapist_reviews').doc(reviewId);

    final review = TherapistReview(
      id: reviewId,
      parentId: parentId,
      parentName: parentName,
      therapistId: therapistId,
      rating: rating,
      feedback: feedback,
      createdAt: DateTime.now(),
      privateFeedback: privateFeedback,
    );
    await reviewRef.set({
      ...review.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Recalculate average rating & breakdown
    final reviewsSnapshot = await _firestore
        .collection('therapist_reviews')
        .where('therapistId', isEqualTo: therapistId)
        .get();

    int totalReviewsCount = reviewsSnapshot.docs.length;
    double sumRating = 0.0;
    Map<String, int> breakdown = {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0};

    for (final doc in reviewsSnapshot.docs) {
      final r = intFrom(doc.data()['rating'], 5);
      sumRating += r;
      final key = r.clamp(1, 5).toString();
      breakdown[key] = (breakdown[key] ?? 0) + 1;
    }

    double averageRating = totalReviewsCount > 0 ? (sumRating / totalReviewsCount) : 0.0;

    final batch = _firestore.batch();
    final profileRef = _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId);
    batch.update(profileRef, {
      'rating': averageRating,
      'totalReviews': totalReviewsCount,
      'ratingBreakdown': breakdown,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await sendNotification(
      userId: therapistId,
      title: 'New Review Received',
      message: 'A parent submitted a $rating-star review for you.',
      category: 'reviews',
      navigationTarget: {
        'route': 'Reviews',
      },
    );

    await batch.commit();
  }

  @override
  Stream<List<TherapistReview>> watchReviewsForTherapist(String therapistId) {
    return _firestore
        .collection('therapist_reviews')
        .where('therapistId', isEqualTo: therapistId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TherapistReview.fromMap(doc.id, doc.data()))
            .toList());
  }

  // User Reporting & Blocking
  @override
  Future<void> submitReport({
    required String reportedId,
    required String reason,
    required String comments,
    required List<Map<String, dynamic>> chatContext,
  }) async {
    final reporterId = _auth.currentUser?.uid;
    if (reporterId == null) throw StateError('No logged in user');

    final reporterDoc = await _firestore.collection(FirestoreCollections.users).doc(reporterId).get();
    final reporterRole = (reporterDoc.data()?['role'] ?? 'parent').toString();

    final reportRef = _firestore.collection('reports').doc();
    final report = UserReport(
      id: reportRef.id,
      reporterId: reporterId,
      reporterRole: reporterRole,
      reportedId: reportedId,
      reason: reason,
      comments: comments,
      chatContext: chatContext,
      timestamp: DateTime.now(),
      status: 'pending',
    );

    await reportRef.set({
      ...report.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> blockUser({required String blockedId}) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    await _firestore.collection(FirestoreCollections.users).doc(myId).update({
      'blockedUserIds': FieldValue.arrayUnion([blockedId]),
    });
  }

  @override
  Future<void> unblockUser({required String blockedId}) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    await _firestore.collection(FirestoreCollections.users).doc(myId).update({
      'blockedUserIds': FieldValue.arrayRemove([blockedId]),
    });
  }

  @override
  Future<bool> isUserBlocked(String userId) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) return false;

    final myDoc = await _firestore.collection(FirestoreCollections.users).doc(myId).get();
    final myBlocked = stringListFrom(myDoc.data()?['blockedUserIds']);
    if (myBlocked.contains(userId)) return true;

    final peerDoc = await _firestore.collection(FirestoreCollections.users).doc(userId).get();
    final peerBlocked = stringListFrom(peerDoc.data()?['blockedUserIds']);
    if (peerBlocked.contains(myId)) return true;

    return false;
  }

  // In-app Notifications
  @override
  Stream<List<NotificationInboxItem>> watchNotifications() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return const Stream.empty();
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationInboxItem.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  @override
  Future<void> markAllNotificationsAsRead() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final unread = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Future<int> getUnreadNotificationCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return 0;

    final unread = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    return unread.docs.length;
  }

  @override
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String message,
    required String category,
    Map<String, dynamic> navigationTarget = const <String, dynamic>{},
  }) async {
    final userDoc = await _firestore.collection(FirestoreCollections.users).doc(userId).get();
    final data = userDoc.data();
    if (data != null) {
      final prefs = boolMapFrom(data['notificationPreferences'] ?? data['therapistNotificationPreferences']);
      bool enabled = true;
      if (category == 'messages') {
        enabled = prefs['therapistsUpdate'] != false || prefs['pushNotifications'] != false;
      } else if (category == 'activities') {
        enabled = prefs['routineReminders'] != false || prefs['dailyReminders'] != false;
      } else if (category == 'subscription') {
        enabled = prefs['subscription'] != false || prefs['emailNotifications'] != false;
      } else if (category == 'reviews') {
        enabled = prefs['activityAlerts'] != false;
      }

      if (!enabled) {
        return;
      }
    }

    await _firestore.collection('notifications').add({
      'userId': userId,
      'title': title,
      'message': message,
      'category': category,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'navigationTarget': navigationTarget,
    });
  }

  // FCM Device Tokens
  @override
  Future<void> saveFcmToken(String token) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _firestore.collection(FirestoreCollections.users).doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class FirebaseBillingRepository implements BillingRepository {
  FirebaseBillingRepository(this._auth, this._firestore, this._stripeBackend);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final StripeBackendClient _stripeBackend;

  UserSubscription _localBypassSubscription(String userId) {
    return UserSubscription(
      id: 'local-bypass',
      userId: userId,
      productId: 'bypass-plan',
      status: 'active',
      cancelAtPeriodEnd: false,
      currentPeriodEnd: DateTime.now().add(const Duration(days: 3650)),
    );
  }

  @override
  Future<List<SubscriptionProduct>> listProducts() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.subscriptionProducts)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs
        .map((doc) => SubscriptionProduct.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<UserSubscription?> getCurrentSubscription() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return null;
    }
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return _localBypassSubscription(userId);
    }
    final activeSnapshot = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['active', 'trialing'])
        .limit(1)
        .get();
    if (activeSnapshot.docs.isNotEmpty) {
      return UserSubscription.fromMap(
        activeSnapshot.docs.first.id,
        activeSnapshot.docs.first.data(),
      );
    }

    final fallbackSnapshot = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (fallbackSnapshot.docs.isEmpty) {
      return null;
    }
    return UserSubscription.fromMap(
      fallbackSnapshot.docs.first.id,
      fallbackSnapshot.docs.first.data(),
    );
  }

  @override
  Future<String?> createCheckoutSession({
    required String productId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return 'mock://local-bypass';
    }
    return _stripeBackend.createCheckoutSession(
      productId: productId,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );
  }

  @override
  Future<void> cancelSubscription(String subscriptionId) async {
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return;
    }
    await _stripeBackend.cancelSubscription(subscriptionId);
    await _firestore
        .collection(FirestoreCollections.subscriptions)
        .doc(subscriptionId)
        .set({
          'cancelAtPeriodEnd': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Future<void> reactivateSubscription(String subscriptionId) async {
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return;
    }
    await _stripeBackend.reactivateSubscription(subscriptionId);
    await _firestore
        .collection(FirestoreCollections.subscriptions)
        .doc(subscriptionId)
        .set({
          'cancelAtPeriodEnd': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}

class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;


  @override
  Future<Map<String, dynamic>> getAnalyticsStats() async {
    final parentsSnap = await _firestore
        .collection(FirestoreCollections.users)
        .where('role', isEqualTo: 'parent')
        .get();
    
    final therapistsSnap = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .get();

    int pending = 0;
    int approved = 0;
    int rejected = 0;
    int suspended = 0;
    double totalRating = 0.0;
    int ratedCount = 0;

    for (final doc in therapistsSnap.docs) {
      final status = (doc.data()['verificationStatus'] ?? 'pending').toString();
      if (status == 'approved') {
        approved++;
      } else if (status == 'rejected') {
        rejected++;
      } else if (status == 'suspended') {
        suspended++;
      } else {
        pending++;
      }

      final rating = doc.data()['rating'];
      if (rating is num && rating > 0) {
        totalRating += rating.toDouble();
        ratedCount++;
      }
    }

    final subsSnap = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('status', whereIn: ['active', 'trialing'])
        .get();

    final reportsSnap = await _firestore.collection('reports').get();
    final feedbackSnap = await _firestore.collection(FirestoreCollections.feedback).get();
    final reviewsSnap = await _firestore.collection('therapist_reviews').get();

    return {
      'totalParents': parentsSnap.docs.length,
      'totalTherapists': therapistsSnap.docs.length,
      'pendingTherapists': pending,
      'approvedTherapists': approved,
      'rejectedTherapists': rejected,
      'suspendedTherapists': suspended,
      'activeSubscriptions': subsSnap.docs.length,
      'averageTherapistRating': ratedCount > 0 ? (totalRating / ratedCount) : 0.0,
      'totalReports': reportsSnap.docs.length,
      'totalFeedback': feedbackSnap.docs.length + reviewsSnap.docs.length,
    };
  }

  @override
  Future<List<UserProfile>> listParents() async {
    final snap = await _firestore
        .collection(FirestoreCollections.users)
        .where('role', isEqualTo: 'parent')
        .get();
    return snap.docs.map((doc) => UserProfile.fromMap(doc.id, doc.data())).toList();
  }

  @override
  Future<List<TherapistProfile>> listTherapistsByStatus(String status) async {
    Query<Map<String, dynamic>> query = _firestore.collection(FirestoreCollections.therapistProfiles);
    if (status.isNotEmpty) {
      query = query.where('verificationStatus', isEqualTo: status);
    }
    final snap = await query.get();
    return snap.docs.map((doc) => TherapistProfile.fromMap(doc.id, doc.data())).toList();
  }

  @override
  Future<void> verifyTherapist({
    required String therapistId,
    required String status,
    String adminFeedback = '',
    DateTime? licenseExpiryDate,
  }) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    final batch = _firestore.batch();
    final profileRef = _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId);
    
    final updateData = <String, dynamic>{
      'verificationStatus': status,
      'adminFeedback': adminFeedback,
      'verifiedBadge': status == 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (licenseExpiryDate != null) {
      updateData['licenseExpiryDate'] = Timestamp.fromDate(licenseExpiryDate);
    }
    batch.update(profileRef, updateData);

    final logRef = _firestore.collection('admin_audit_logs').doc();
    final log = AdminAuditLog(
      id: logRef.id,
      adminUid: adminId,
      targetUid: therapistId,
      actionType: 'verify_therapist',
      details: 'Status changed to $status. Feedback: $adminFeedback',
      timestamp: DateTime.now(),
    );
    batch.set(logRef, {
      ...log.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    final notificationRef = _firestore.collection('notifications').doc();
    final isApproved = status == 'approved';
    final title = isApproved ? 'Profile Approved!' : 'Profile Update Required';
    final message = isApproved
        ? 'Your therapist profile has been approved. You are now visible to parents!'
        : 'Your profile status: $status. Corrections: $adminFeedback';

    batch.set(notificationRef, {
      'userId': therapistId,
      'title': title,
      'message': message,
      'category': 'verification',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'navigationTarget': const <String, dynamic>{
        'route': 'ProfileStatus',
      },
    });

    await batch.commit();
  }

  @override
  Stream<List<UserReport>> watchReports() {
    return _firestore
        .collection('reports')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserReport.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> updateReportStatus(String reportId, String status) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    await _firestore.collection('reports').doc(reportId).update({
      'status': status,
    });

    await _firestore.collection('admin_audit_logs').add({
      'adminUid': adminId,
      'targetUid': reportId,
      'actionType': 'update_report_status',
      'details': 'Report status set to $status',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> executeModerationAction({
    required String reportedUserId,
    required String action,
    String reason = '',
  }) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    final batch = _firestore.batch();
    final userRef = _firestore.collection(FirestoreCollections.users).doc(reportedUserId);

    if (action == 'warn') {
      batch.update(userRef, {
        'status': 'warned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final notificationRef = _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': reportedUserId,
        'title': 'Account Warning',
        'message': 'Your account has received a warning for: $reason. Please adhere to guidelines.',
        'category': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } else if (action == 'suspend') {
      batch.update(userRef, {
        'status': 'suspended',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final profileRef = _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedUserId);
      batch.set(profileRef, {
        'verificationStatus': 'suspended',
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (action == 'ban') {
      batch.update(userRef, {
        'status': 'banned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final profileRef = _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedUserId);
      batch.set(profileRef, {
        'verificationStatus': 'suspended',
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final logRef = _firestore.collection('admin_audit_logs').doc();
    final log = AdminAuditLog(
      id: logRef.id,
      adminUid: adminId,
      targetUid: reportedUserId,
      actionType: 'moderation_$action',
      details: 'Moderation action $action executed. Reason: $reason',
      timestamp: DateTime.now(),
    );
    batch.set(logRef, {
      ...log.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  @override
  Future<List<Map<String, dynamic>>> listAllFeedbackAndReviews() async {
    final feedbackSnap = await _firestore.collection(FirestoreCollections.feedback).get();
    final reviewsSnap = await _firestore.collection('therapist_reviews').get();

    final list = <Map<String, dynamic>>[];

    for (final doc in feedbackSnap.docs) {
      final data = doc.data();
      list.add({
        'id': doc.id,
        'type': 'app_feedback',
        'title': 'App Feedback',
        'user': data['userId'] ?? data['email'] ?? 'User',
        'body': data['body'] ?? data['feedback'] ?? '',
        'rating': intFrom(data['rating'], 0),
        'timestamp': dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      });
    }

    for (final doc in reviewsSnap.docs) {
      final data = doc.data();
      list.add({
        'id': doc.id,
        'type': 'therapist_review',
        'title': 'Therapist Review',
        'user': data['parentName'] ?? 'Parent',
        'body': 'For therapist ID ${data['therapistId']}: ${data['feedback']}',
        'rating': intFrom(data['rating'], 0),
        'timestamp': dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      });
    }

    list.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
    return list;
  }

  @override
  Future<List<AdminAuditLog>> listAuditLogs() async {
    final snap = await _firestore
        .collection('admin_audit_logs')
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs.map((doc) => AdminAuditLog.fromMap(doc.id, doc.data())).toList();
  }
}
