import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';



import '../config/app_runtime_config.dart';
import '../models/app_models.dart';
import '../services/auth_verification_policy.dart';
import '../services/dashboard_metrics_calculator.dart';
import '../services/payment_backend_client.dart';
import '../services/payment_deep_link_service.dart';
import '../services/notification_service.dart';

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
  static const clinicalNotes = 'clinical_notes';
  static const appointmentSlots = 'appointment_slots';
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
    String? replyToId,
    String? replyToPreview,
  });
  Future<void> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String? reaction,
  });
  Future<void> updateUserActiveStatus({
    required String userId,
    required String role,
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
    List<String> lowRatingReasons = const <String>[],
  });
  Stream<List<TherapistReview>> watchReviewsForTherapist(String therapistId);

  // User Reporting & Blocking
  Future<void> submitReport({
    required String reportedId,
    required String reason,
    required String comments,
    required List<Map<String, dynamic>> chatContext,
    String? threadId,
    String subscriptionStatus = 'none',
    String parentAction = 'none',
  });
  /// Legacy resolve method — kept for compatibility. Use [applyModerationAction] for new code.
  Future<void> resolveReport({
    required String reportId,
    required String action,
    String notes = '',
  });
  Future<void> blockUser({
    required String blockedId,
    required String threadId,
    required String blockerDisplayName,
    required String blockerRole,
  });
  Future<void> unblockUser({
    required String blockedId,
    required String threadId,
    required String unblockerRole,
  });
  Future<bool> isUserBlocked(String userId);
  Future<BlockInfo> isUserBlockedWithInfo({
    required String peerId,
    required TherapistThread thread,
    required String myRole,
  });
  Future<void> sendFinalMessage({
    required String threadId,
    required String senderRole,
    required String body,
  });
  Future<void> sendFinalReply({
    required String threadId,
    required String senderRole,
    required String body,
  });

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

  // Clinical Notes
  Future<void> createClinicalNote({
    required String therapistId,
    required String parentId,
    required String childId,
    required String therapistName,
    required String childName,
    required String title,
    required String body,
    String? slotId,
  });
  Stream<List<ClinicalNote>> watchClinicalNotesForChild(String childId);
  Stream<List<ClinicalNote>> watchClinicalNotesForTherapist(String therapistId);
  Future<void> deleteClinicalNote(String noteId);

  // Appointment Slots
  Future<void> createAppointmentSlot({
    required String therapistId,
    required DateTime dateTime,
    required int durationMinutes,
    String? packageTitle,
    String? assignedToParentId,
  });
  Stream<List<AppointmentSlot>> watchSlotsForTherapist(String therapistId);
  Stream<List<AppointmentSlot>> watchSlotsForParent(String parentId);
  Future<void> markSessionCompleted(String slotId);

  // Slot Requests
  Future<void> createSlotRequest({
    required String parentId,
    required String parentName,
    required String therapistId,
    required String packageTitle,
    required DateTime preferredDateTime,
  });
  Stream<List<SlotRequest>> watchSlotRequestsForTherapist(String therapistId);
  Stream<List<SlotRequest>> watchSlotRequestsForParent(String parentId);
  Future<void> acknowledgeSlotRequest(String requestId);
  Future<void> declineSlotRequest(String requestId, String reason);
  Future<void> markSlotRequestAsCreated(String requestId);
  Future<void> bookAppointmentSlot({
    required String slotId,
    required String parentId,
    required String childId,
    required String childName,
    required String notes,
    String? therapistId,
    String? parentName,
  });
  Future<void> cancelAppointmentSlot(String slotId, {
    String? parentId,
    String? therapistId,
    String? parentName,
  });
  Future<void> deleteAppointmentSlot(String slotId);

  // ─── Moderation: Restriction Checking ──────────────────────────────────────

  /// Returns the active per-relationship restriction between [parentId] and
  /// [therapistId], or null if no active restriction exists.
  Future<RestrictionRecord?> getActiveRestriction({
    required String parentId,
    required String therapistId,
  });

  /// Stream version of [getActiveRestriction] for real-time UI updates.
  Stream<RestrictionRecord?> watchActiveRestriction({
    required String parentId,
    required String therapistId,
  });

  /// Returns true if [userId] has any active restriction (as either party).
  /// Used to block new subscription purchases for restricted parents.
  Future<bool> hasAnyActiveRestriction(String userId);
  Future<bool> hasActiveRestrictionBetween({required String parentId, required String therapistId});

  // ─── Moderation: One-Time Messages ─────────────────────────────────────────

  /// Submit a one-time message (text/image/PDF/voice) in response to an
  /// admin 'Additional Information Required' request.
  Future<void> submitReportMessage({
    required String reportId,
    required String messageType,
    required String content,
    required String requestedByAdminId,
    List<Map<String, dynamic>> attachments = const [],
  });

  /// Stream of messages submitted for a report (admin + sender can read).
  Stream<List<ReportMessage>> watchReportMessages(String reportId);

  // ─── Moderation: History ───────────────────────────────────────────────────

  /// Fetch the full, permanent moderation history for a user.
  Future<List<ModerationHistoryEntry>> getModerationHistory(String userId);

  /// Stream version for real-time moderation timeline in admin UI.
  Stream<List<ModerationHistoryEntry>> watchModerationHistory(String userId);
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
    String? verificationImageBase64,
    String? verificationSource,
    String? verificationUrl,
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
  Future<void> resolveWithdrawalRequest({
    required String requestId,
    required String status,
    String? adminNotes,
    String? receiptBase64,
  });

  // ─── New Moderation Actions ─────────────────────────────────────────────────

  /// Apply a moderation action. This is the primary entry point for all
  /// moderation decisions — from reports, therapist details, parent details,
  /// or audit logs.
  ///
  /// [action] values: 'warn', 'restrict', 'suspend', 'ban', 'no_action'
  /// [reason] is mandatory and must be non-empty.
  /// [reportId] links the action to the source report if applicable.
  /// [restrictedWithUserId] is required for 'restrict' (the other party).
  /// [restrictionDays] is required for 'restrict' (admin-configured duration).
  Future<void> applyModerationAction({
    required String targetUserId,
    required String targetRole,    // 'parent' or 'therapist'
    required String action,
    required String reason,
    String? reportId,
    String? restrictedWithUserId,
    int? restrictionDays,
  });

  /// Remove or reverse an existing moderation action.
  ///
  /// [action] values: 'remove_warn', 'remove_restrict', 'remove_suspend',
  ///                  'remove_ban', 'restore'
  Future<void> removeModerationAction({
    required String targetUserId,
    required String targetRole,
    required String action,
    required String reason,
    String? restrictionId,  // for remove_restrict: which restriction to remove
  });

  /// Request additional information from the reporter, reported user, or both.
  Future<void> requestAdditionalInfo({
    required String reportId,
    required String requestFrom,   // 'reporter', 'reported', 'both'
    required String reason,
    required String description,
  });

  /// Cancel ALL active subscriptions for [userId] (used for Suspend/Ban).
  Future<void> batchCancelSubscriptionsForUser({
    required String userId,
    required String reason,
  });

  /// Cancel ALL future booked appointments for [userId] (used for Suspend/Ban).
  Future<void> batchCancelBookingsForUser({
    required String userId,
    required String reason,
  });

  /// List parents filtered by moderation status badge.
  /// [badge] values: 'all', 'verified', 'warned', 'restricted', 'suspended', 'banned'
  Future<List<UserProfile>> listParentsByModerationStatus(String badge);

  /// List therapists filtered by moderation status badge.
  /// [badge] values: 'all', 'verified', 'warned', 'restricted', 'suspended', 'banned'
  Future<List<TherapistProfile>> listTherapistsByModerationStatus(String badge);

  /// Mark all unread feedback and reviews as read by admin.
  Future<void> markAllFeedbackAsRead();

  /// Perform admin manual payout for a suspended/banned therapist's frozen wallet.
  Future<void> adminPayoutAndResetWallet({
    required String therapistId,
    required double amount,
    required String transactionReference,
    required String receiptBase64,
    required String adminNote,
  });

  /// Create a secondary admin account.
  Future<void> createSecondaryAdmin({
    required String name,
    required String email,
    required String password,
  });

  /// Delete a secondary admin account.
  Future<void> deleteSecondaryAdmin(String adminUid);

  /// List all secondary admin accounts.
  Future<List<UserProfile>> listSecondaryAdmins();
}

abstract class BillingRepository {
  Future<List<SubscriptionProduct>> listProducts();
  Future<UserSubscription?> getSubscriptionForTherapist(String therapistId);
  Stream<UserSubscription?> watchSubscriptionForTherapist(String therapistId);
  Future<bool> purchaseTherapistSubscription(String therapistId, {int packageIndex = 0, bool Function()? isCancelledCheck, void Function()? onUrlLaunched});
  Future<String?> prepareCheckoutUrl(String therapistId, {int packageIndex = 0});
  Future<void> deletePendingSubscription(String therapistId);
  Future<void> cancelSubscriptionInStore(String therapistId, {required bool keepAndLockChats, String? reason});
  Future<void> reactivateSubscriptionInStore(String therapistId);
  Future<void> syncSubscriptionStatus(String therapistId);

  // Therapist Wallet Operations
  Future<Map<String, dynamic>> getTherapistWallet(String therapistId);
  Future<void> requestWithdrawal(String therapistId, double amount, String paymentMethod, String accountDetails, {bool isAppeal = false, String? appealReason});

  // Ledgers
  Future<List<Map<String, dynamic>>> getTherapistTransactions(String therapistId);
  Future<List<Map<String, dynamic>>> getParentTransactions();
}

class AppRepositories {
  AppRepositories._();

  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseAuth authClient = FirebaseAuth.instance;
  static final PaymentBackendClient paymentBackend = PaymentBackendClient(
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
    paymentBackend,
  );
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Predefined admin emails — users logging in with these are automatically
  /// promoted to the admin role without manual Firestore changes.
  static const _adminEmails = <String>{
    'admin@autiease.com',
  };

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
      // If this is a predefined admin email, auto-create their profile.
      final regEmail = user.email?.toLowerCase().trim() ?? '';
      if (_adminEmails.contains(regEmail)) {
        await _firestore
            .collection(FirestoreCollections.users)
            .doc(user.uid)
            .set({
          'displayName': user.displayName ?? 'Admin',
          'email': regEmail,
          'role': 'admin',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return AppSession(
          state: AppSessionState.admin,
          uid: user.uid,
          role: 'admin',
        );
      }
      return AppSession(
        state: AppSessionState.incompleteProfile,
        uid: user.uid,
      );
    }

    final profile = UserProfile.fromMap(doc.id, doc.data()!);

    // ── Block banned / suspended users on session resume ─────────────
    // This is the primary enforcement: even if the Cloud Function to
    // disable Auth failed, the user is signed out here on every app open.
    if (profile.status == 'banned' || profile.status == 'suspended') {
      await _auth.signOut();
      return const AppSession(state: AppSessionState.unauthenticated);
    }
    // ──────────────────────────────────────────────────────────────────

    // ── Auto-promote predefined admin emails ──────────────────────────
    // If the user's email matches a predefined admin email, automatically
    // set their Firestore role to 'admin' so they don't need manual setup.
    final email = user.email?.toLowerCase().trim() ?? '';
    if (_adminEmails.contains(email) && profile.role != 'admin') {
      await _firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .update({'role': 'admin'});
      return AppSession(
        state: AppSessionState.admin,
        uid: profile.uid,
        role: 'admin',
      );
    }
    // ──────────────────────────────────────────────────────────────────

    if (profile.role.isEmpty) {
      return AppSession(
        state: AppSessionState.incompleteProfile,
        uid: user.uid,
      );
    }

    // Skip email verification for all admin-role users (primary + secondary)
    final isAdminUser = _adminEmails.contains(email) || profile.role == 'admin';

    if (!isAdminUser && requiresEmailVerification(
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
        .get();
    final list = snapshot.docs
        .map((doc) => ChildProfile.fromMap(doc.id, doc.data()))
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
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
    // 1. Specialization limit check
    if (profile.servicePackages.length > profile.specializations.length) {
      throw StateError(
          "Your package limit is based on the number of specializations you have selected. "
          "To add more packages, either select more specializations or edit your existing packages.");
    }

    // 2. Active subscriptions check for package deletion
    final existingDoc = await _therapists.doc(profile.id).get();
    if (existingDoc.exists) {
      final existingData = existingDoc.data() ?? {};
      final oldPackagesData = existingData['servicePackages'] as List? ?? [];
      final oldPackages = oldPackagesData
          .map((e) => TherapyPackage.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      final newPackages = profile.servicePackages;
      final deletedIndices = <int>[];

      // Match newPackages to oldPackages. Any unmatched old package is considered deleted.
      final matchedOldIndices = <int>{};
      for (final newPkg in newPackages) {
        var foundIndex = -1;
        // 1. Try exact match
        for (var i = 0; i < oldPackages.length; i++) {
          if (matchedOldIndices.contains(i)) continue;
          final oldPkg = oldPackages[i];
          if (newPkg.title == oldPkg.title &&
              newPkg.price == oldPkg.price &&
              newPkg.durationMinutes == oldPkg.durationMinutes &&
              newPkg.sessionsPerWeek == oldPkg.sessionsPerWeek &&
              newPkg.description == oldPkg.description) {
            foundIndex = i;
            break;
          }
        }
        // 2. Try match by title
        if (foundIndex == -1) {
          for (var i = 0; i < oldPackages.length; i++) {
            if (matchedOldIndices.contains(i)) continue;
            final oldPkg = oldPackages[i];
            if (newPkg.title == oldPkg.title) {
              foundIndex = i;
              break;
            }
          }
        }
        // 3. Fallback to first unmatched index
        if (foundIndex == -1) {
          for (var i = 0; i < oldPackages.length; i++) {
            if (matchedOldIndices.contains(i)) continue;
            foundIndex = i;
            break;
          }
        }
        if (foundIndex != -1) {
          matchedOldIndices.add(foundIndex);
        }
      }

      for (var i = 0; i < oldPackages.length; i++) {
        if (!matchedOldIndices.contains(i)) {
          deletedIndices.add(i);
        }
      }

      if (deletedIndices.isNotEmpty) {
        // Query active subscriptions for this therapist
        final activeSubsSnapshot = await _firestore
            .collection(FirestoreCollections.subscriptions)
            .where('therapistId', isEqualTo: profile.id)
            .where('status', whereIn: ['active', 'trialing', 'grace_period'])
            .get();

        for (final doc in activeSubsSnapshot.docs) {
          final subData = doc.data();
          final prodId = subData['productId']?.toString() ?? '';
          if (prodId.startsWith('auto_${profile.id}_')) {
            final parts = prodId.split('_');
            if (parts.length >= 3) {
              final pkgIndex = int.tryParse(parts.last);
              if (pkgIndex != null && deletedIndices.contains(pkgIndex)) {
                throw StateError('This package cannot be deleted because one or more parents are currently subscribed to it.');
              }
            }
          } else if (prodId == 'bypass-plan' || prodId == 'local-bypass' || prodId == 'cached-offline') {
            if (deletedIndices.contains(0)) {
              throw StateError('This package cannot be deleted because one or more parents are currently subscribed to it.');
            }
          }
        }
      }
    }

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
      'verificationStatus': profile.verificationStatus,
      'experience_years': profile.yearsOfExperience,
      'experience_months': profile.experienceMonths,
      'isAcceptingClients': profile.isAcceptingClients,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'hasUnacknowledgedChanges': profile.hasUnacknowledgedChanges,
      'unacknowledgedChangesFields': profile.unacknowledgedChangesFields,
      'servicePackages': profile.servicePackages.map((item) => item.toMap()).toList(),
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

    try {
      final childDoc = await _firestore.collection(FirestoreCollections.childProfiles).doc(assignment.id).get();
      if (childDoc.exists && childDoc.data() != null) {
        final parentId = childDoc.data()?['parentId']?.toString();
        final childName = childDoc.data()?['name']?.toString() ?? 'Your child';
        if (parentId != null && parentId.isNotEmpty) {
          final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
          final parentData = parentDoc.data();
          if (parentData != null) {
            final prefs = boolMapFrom(parentData['notificationPreferences']);
            final enabled = prefs['routineReminders'] ?? prefs['dailyReminders'] ?? true;
            
            if (enabled) {
              await _firestore.collection('notifications').add({
                'userId': parentId,
                'title': '📋 Routine Updated!',
                'message': 'A new routine/activity plan has been updated for $childName.',
                'category': 'activities',
                'timestamp': FieldValue.serverTimestamp(),
                'isRead': false,
              });
            }
          }
        }
      }
    } catch (_) {
      // Prevent notification errors from blocking assignment save
    }
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

    try {
      final childDoc = await _firestore.collection(FirestoreCollections.childProfiles).doc(childId).get();
      if (childDoc.exists && childDoc.data() != null) {
        final parentId = childDoc.data()?['parentId']?.toString();
        final childName = childDoc.data()?['name']?.toString() ?? 'Your child';
        if (parentId != null && parentId.isNotEmpty) {
          final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
          final parentData = parentDoc.data();
          if (parentData != null) {
            final prefs = boolMapFrom(parentData['notificationPreferences']);
            final enabled = prefs['levelProgressNotification'] ?? prefs['progressUpdates'] ?? true;
            final source = metadata?['source'] as String?;
            final isCommunication = source == 'aac_sentence';
            
            if (enabled && !isCommunication) {
              // Build a human-readable activity name:
              // prefer metadata['gameName'], then moduleId title, then cleaned itemId.
              final rawName = (metadata?['gameName'] as String?)?.isNotEmpty == true
                  ? metadata!['gameName'] as String
                  : (moduleId != null && moduleId.isNotEmpty)
                      ? moduleId.replaceAll('_', ' ').replaceAll('-', ' ')
                      : itemId.replaceAll('_', ' ').replaceAll('-', ' ');
              // Capitalise first letter.
              final activityName = rawName.isNotEmpty
                  ? rawName[0].toUpperCase() + rawName.substring(1)
                  : 'an activity';

              // For games (moduleId-based calls), only send ONE notification per
              // module per session. We deduplicate by skipping if a notification
              // for this moduleId already exists today.
              bool shouldSend = true;
              if (moduleId != null && moduleId.isNotEmpty) {
                final today = DateTime.now();
                final startOfDay = DateTime(today.year, today.month, today.day);
                final existing = await _firestore
                    .collection('notifications')
                    .where('userId', isEqualTo: parentId)
                    .where('moduleId', isEqualTo: moduleId)
                    .get();
                for (final doc in existing.docs) {
                  final ts = doc.data()['timestamp'];
                  DateTime? docDate;
                  if (ts is Timestamp) docDate = ts.toDate();
                  if (docDate != null && docDate.isAfter(startOfDay)) {
                    shouldSend = false;
                    break;
                  }
                }
              }

              if (shouldSend) {
                final isGame = moduleId != null && moduleId.isNotEmpty &&
                    (moduleId.contains('game') || (metadata?['source'] as String? ?? '').contains('game'));
                await _firestore.collection('notifications').add({
                  'userId': parentId,
                  'title': isGame ? '🎮 Game Completed!' : '🌟 Activity Completed!',
                  'message': '$childName completed ${isGame ? 'the game' : 'the activity'} "$activityName".',
                  'category': 'progress',
                  'moduleId': moduleId ?? '',
                  'timestamp': FieldValue.serverTimestamp(),
                  'isRead': false,
                });
              }
            }
          }
        }
      }
    } catch (_) {
      // Prevent notification errors from blocking activity completion save
    }
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
      return 'A parent';
    }
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final rawFullName = (data['fullName'] ?? '').toString().trim();
    if (rawFullName.isNotEmpty) {
      return rawFullName;
    }
    return 'A parent';
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
      var threadResult = existingThread;
      
      if (existingThread.status == 'locked' || existingThread.status == 'reported') {
        await existing.docs.first.reference.update({
          'status': 'active',
          'subscriptionId': subscriptionId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        threadResult = existingThread.copyWith(
          status: 'active',
          subscriptionId: subscriptionId,
        );
      }

      final needsMetadataPatch =
          threadResult.parentDisplayName.isEmpty ||
          threadResult.therapistDisplayName.isEmpty;
      if (needsMetadataPatch) {
        await existing.docs.first.reference.set({
          'parentDisplayName': parentDisplayName,
          'therapistDisplayName': therapistDisplayName,
        }, SetOptions(merge: true));
        return threadResult.copyWith(
          parentDisplayName: parentDisplayName,
          therapistDisplayName: therapistDisplayName,
        );
      }
      return threadResult;
    }

    final ref = _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc();
    final welcomeMsg = "Hi! Thank you for subscribing to my support plan. Please tell me a bit about your child's goals so we can get started!";
    final thread = TherapistThread(
      id: ref.id,
      parentId: parentId,
      therapistId: therapistId,
      childId: childId,
      subscriptionId: subscriptionId,
      status: 'active',
      parentDisplayName: parentDisplayName,
      therapistDisplayName: therapistDisplayName,
      lastMessagePreview: welcomeMsg,
      lastMessageAt: DateTime.now(),
      emergencyStatus: 'none',
      postCancelVisible: true,
    );

    final batch = _firestore.batch();
    batch.set(ref, {
      ...thread.toMap(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final welcomeMsgRef = ref.collection('messages').doc();
    batch.set(welcomeMsgRef, {
      'senderId': therapistId,
      'senderRole': 'therapist',
      'body': welcomeMsg,
      'sentAt': FieldValue.serverTimestamp(),
      'status': 'sent',
    });

    await batch.commit();

    // Notifications are handled entirely by the payment-backend webhook.

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
    String? replyToId,
    String? replyToPreview,
  }) async {
    final senderId = _auth.currentUser?.uid;
    if (senderId == null) {
      throw StateError('No logged in user');
    }
    final threadDoc = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .get();
    final status = threadDoc.data()?['status']?.toString();
    if (threadDoc.exists && (status == 'locked' || status == 'reported')) {
      throw StateError('Cannot send message: This conversation is currently locked.');
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
          if (replyToId != null) 'replyToId': replyToId,
          if (replyToPreview != null) 'replyToPreview': replyToPreview,
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
  Future<void> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String? reaction,
  }) async {
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .collection('messages')
        .doc(messageId)
        .update({
          'reaction': reaction,
        });
  }

  @override
  Future<void> updateUserActiveStatus({
    required String userId,
    required String role,
  }) async {
    if (role == 'therapist') {
      await _firestore
          .collection(FirestoreCollections.therapistProfiles)
          .doc(userId)
          .set({
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } else {
      await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .set({
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
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

    // Fetch thread data so we can address the notification correctly
    final threadSnap = await threadRef.get();
    final threadData = threadSnap.data() ?? <String, dynamic>{};
    final therapistId = (threadData['therapistId'] ?? '').toString();
    final parentName = (threadData['parentDisplayName'] ?? 'A parent').toString();

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

    // Notify the therapist in their notification inbox
    if (therapistId.isNotEmpty) {
      try {
        await _firestore.collection('notifications').add({
          'userId': therapistId,
          'title': '🚨 Emergency Support Requested',
          'message': '$parentName has requested immediate emergency support. Please respond as soon as possible.',
          'category': 'emergency',
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
          'navigationTarget': {
            'route': 'chat',
            'threadId': threadId,
          },
        });
      } catch (_) {
        // Prevent notification errors from blocking emergency save
      }
    }
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
    List<String> lowRatingReasons = const <String>[],
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
      lowRatingReasons: lowRatingReasons,
    );
    await reviewRef.set({
      ...review.toMap(),
      'isReadByAdmin': false,
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
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => TherapistReview.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  // User Reporting & Blocking
  @override
  Future<void> submitReport({
    required String reportedId,
    required String reason,
    required String comments,
    required List<Map<String, dynamic>> chatContext,
    String? threadId,
    String subscriptionStatus = 'none',
    String parentAction = 'none',
  }) async {
    final reporterId = _auth.currentUser?.uid;
    if (reporterId == null) throw StateError('No logged in user');

    final reporterDoc = await _firestore.collection(FirestoreCollections.users).doc(reporterId).get();
    final reporterRole = (reporterDoc.data()?['role'] ?? 'parent').toString();

    // --- Resolve display names for notifications ---
    String reporterName = 'A user';
    String reportedName = 'A user';
    try {
      if (reporterRole == 'parent') {
        reporterName = _resolveParentDisplayName(reporterDoc.data() ?? {});
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedId).get();
        reportedName = (tDoc.data()?['displayName'] ?? 'Therapist').toString();
        if (reportedName.isEmpty) reportedName = 'Therapist';
      } else {
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reporterId).get();
        reporterName = (tDoc.data()?['displayName'] ?? 'Therapist').toString();
        if (reporterName.isEmpty) reporterName = 'Therapist';
        final pDoc = await _firestore.collection(FirestoreCollections.users).doc(reportedId).get();
        reportedName = _resolveParentDisplayName(pDoc.data() ?? {});
      }
    } catch (e) {
      debugPrint('submitReport: failed to resolve display names: $e');
    }

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
      threadId: threadId,
      subscriptionStatus: subscriptionStatus,
      parentAction: parentAction,
    );

    await reportRef.set({
      ...report.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (threadId != null && threadId.trim().isNotEmpty) {
      final tid = threadId.trim();
      // Mark the thread as reported and record which side filed the report
      final reporterFlag = reporterRole == 'parent' ? 'reportedByParent' : 'reportedByTherapist';
      await _firestore
          .collection(FirestoreCollections.therapistThreads)
          .doc(tid)
          .set({
            'status': 'reported',
            reporterFlag: true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }

    // --- Notify the reported person with reporter's real name and reason ---
    try {
      await _firestore.collection('notifications').add({
        'userId': reportedId,
        'title': '⚠️ Report Filed Against You',
        'message': '$reporterName has reported you for "$reason". '
            'The AutiEase admin team will review this and inform both parties of the action taken.',
        'category': 'reports',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        if (threadId != null)
          'navigationTarget': {'route': 'Chat', 'threadId': threadId},
      });
    } catch (e) {
      debugPrint('submitReport: failed to notify reported user: $e');
    }

    // --- Send a confirmation notification to the reporter ---
    try {
      await _firestore.collection('notifications').add({
        'userId': reporterId,
        'title': '✅ Report Submitted',
        'message': 'Your report against $reportedName for "$reason" has been submitted. '
            'Admin will review it and inform both parties accordingly.',
        'category': 'reports',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        if (threadId != null)
          'navigationTarget': {'route': 'Chat', 'threadId': threadId},
      });
    } catch (e) {
      debugPrint('submitReport: failed to notify reporter: $e');
    }
  }


  @override
  Future<void> resolveReport({
    required String reportId,
    required String action,
    String notes = '',
  }) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    // 1. Fetch the report
    final reportDoc = await _firestore.collection('reports').doc(reportId).get();
    if (!reportDoc.exists) {
      throw StateError('Report $reportId not found');
    }
    final data = reportDoc.data() ?? {};
    final reporterId = data['reporterId']?.toString() ?? '';
    final reporterRole = data['reporterRole']?.toString() ?? 'parent';
    final reportedId = data['reportedId']?.toString() ?? '';
    final threadId = data['threadId']?.toString();

    // 2. Resolve the report document
    await _firestore.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'adminDecision': action,
      'adminNotes': notes,
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    // 3. Update the reported user doc if action is warning/suspension/ban/restriction
    final userRef = _firestore.collection(FirestoreCollections.users).doc(reportedId);
    final isSeverityAction = action == 'suspend' || action == 'ban' || action == 'restrict';

    if (action == 'warn') {
      await userRef.update({
        'status': 'warned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else if (action == 'suspend') {
      await userRef.update({
        'status': 'suspended',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedId).set({
        'verificationStatus': 'suspended',
        'isActive': false,
        'adminFeedback': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (action == 'ban') {
      await userRef.update({
        'status': 'banned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedId).set({
        'verificationStatus': 'suspended',
        'isActive': false,
        'adminFeedback': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (action == 'restrict') {
      await userRef.update({
        'status': 'restricted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedId).set({
        'verificationStatus': 'restricted',
        'isActive': false,
        'isAcceptingClients': false,
        'adminFeedback': notes,
        'restrictionUntil': Timestamp.fromDate(DateTime.now().add(const Duration(days: 4))),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // 4. Thread Unlocking Logic
    if (threadId != null && threadId.trim().isNotEmpty) {
      final tid = threadId.trim();
      if (isSeverityAction) {
        // Locked forever due to suspension/ban/restriction
        await _firestore.collection(FirestoreCollections.therapistThreads).doc(tid).update({
          'status': 'locked',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Warning or No Action: unlock if subscription remains active, and clear reporter flags
        final parentId = reporterRole == 'parent' ? reporterId : reportedId;
        final therapistId = reporterRole == 'parent' ? reportedId : reporterId;
        final subDocId = 'sub_${parentId}_$therapistId';
        final subDoc = await _firestore.collection(FirestoreCollections.subscriptions).doc(subDocId).get();
        
        final hasActiveSub = subDoc.exists && subDoc.data()?['isActive'] == true && subDoc.data()?['status'] != 'canceled';
        
        // Clear the reporter flags so both sides can report again if needed
        await _firestore.collection(FirestoreCollections.therapistThreads).doc(tid).update({
          'status': hasActiveSub ? 'active' : 'locked',
          'reportedByParent': false,
          'reportedByTherapist': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // 5. Audit Logging
    final logRef = _firestore.collection('admin_audit_logs').doc();
    final log = AdminAuditLog(
      id: logRef.id,
      adminUid: adminId,
      adminEmail: _auth.currentUser?.email ?? '',
      targetUid: reportId,
      actionType: 'resolve_report',
      details: 'Action: $action, Notes: $notes',
      timestamp: DateTime.now(),
    );
    await logRef.set({
      ...log.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 6. Resolve real display names for notifications
    String reporterName = 'the reporter';
    String reportedName = 'the reported user';
    try {
      if (reporterRole == 'parent') {
        // Reporter is parent
        final pDoc = await _firestore.collection(FirestoreCollections.users).doc(reporterId).get();
        reporterName = _resolveParentDisplayName(pDoc.data() ?? {});
        // Reported is therapist
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reportedId).get();
        reportedName = (tDoc.data()?['displayName'] ?? '').toString();
        if (reportedName.isEmpty) reportedName = 'the therapist';
      } else {
        // Reporter is therapist
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(reporterId).get();
        reporterName = (tDoc.data()?['displayName'] ?? '').toString();
        if (reporterName.isEmpty) reporterName = 'the therapist';
        // Reported is parent
        final pDoc = await _firestore.collection(FirestoreCollections.users).doc(reportedId).get();
        reportedName = _resolveParentDisplayName(pDoc.data() ?? {});
      }
    } catch (e) {
      debugPrint('resolveReport: failed to resolve display names: $e');
    }

    // 7. Send Notifications with real names
    final isNoAction = action == 'no_action' || action == 'remove' || action == 'close' || action == 'request_info';
    final actionLabel = action == 'warn'
        ? 'Warning'
        : action == 'suspend'
            ? 'Suspension'
            : action == 'restrict'
                ? 'Temporary Restriction'
                : action == 'ban'
                    ? 'Permanent Ban'
                    : 'No Action';
    final reasonText = notes.trim().isNotEmpty ? ' Reason: $notes.' : '';

    // A. Notification for Reported User
    String reportedMessage;
    if (isNoAction) {
      reportedMessage = 'A report filed by $reporterName against your account has been reviewed. '
          'After investigation, no policy violation was found and no action has been taken.$reasonText';
    } else {
      reportedMessage = '$reporterName submitted a report against your account. '
          'After review, the admin has issued the following action: $actionLabel.$reasonText '
          'Please adhere to our community guidelines to avoid future violations.';
    }

    await _firestore.collection('notifications').add({
      'userId': reportedId,
      'title': isNoAction ? '✅ Report Dismissed' : '⚠️ Admin Action Taken',
      'message': reportedMessage,
      'category': 'reports',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
      if (threadId != null)
        'navigationTarget': {'route': 'Chat', 'threadId': threadId},
    });

    // B. Notification for Reporter
    String reporterMessage;
    if (isNoAction) {
      reporterMessage = 'Your report against $reportedName has been reviewed. '
          'After investigation, no policy violation was found. No action has been taken at this time.$reasonText';
    } else {
      reporterMessage = 'Your report against $reportedName has been reviewed by the admin. '
          'Action taken: $actionLabel.$reasonText '
          'Thank you for helping us maintain a safe and supportive platform.';
    }

    await _firestore.collection('notifications').add({
      'userId': reporterId,
      'title': '📋 Report Status Update',
      'message': reporterMessage,
      'category': 'reports',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
      if (threadId != null)
        'navigationTarget': {'route': 'Chat', 'threadId': threadId},
    });
  }

  @override
  Future<void> blockUser({
    required String blockedId,
    required String threadId,
    required String blockerDisplayName,
    required String blockerRole,
  }) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    // 1. Add to blocker's user doc
    await _firestore.collection(FirestoreCollections.users).doc(myId).update({
      'blockedUserIds': FieldValue.arrayUnion([blockedId]),
    });

    // 2. Mark the thread with who blocked whom
    final blockField = blockerRole == 'parent' ? 'blockedByParent' : 'blockedByTherapist';
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({blockField: true}, SetOptions(merge: true));

    // 3. Notify the blocked user
    try {
      await _firestore.collection('notifications').add({
        'userId': blockedId,
        'title': '\uD83D\uDEAB You have been blocked',
        'message': '$blockerDisplayName has blocked you. You can no longer send messages until you are unblocked.',
        'category': 'messages',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'navigationTarget': {'route': 'chat', 'threadId': threadId},
      });
    } catch (_) {}
  }

  @override
  Future<void> unblockUser({
    required String blockedId,
    required String threadId,
    required String unblockerRole,
  }) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    // 1. Remove from blocker's user doc
    await _firestore.collection(FirestoreCollections.users).doc(myId).update({
      'blockedUserIds': FieldValue.arrayRemove([blockedId]),
    });

    // 2. Clear the thread block flag and reset one-time message/reply flags
    final blockField = unblockerRole == 'parent' ? 'blockedByParent' : 'blockedByTherapist';
    final finalMsgField = unblockerRole == 'parent'
        ? 'finalMessageSentByTherapist'  // if parent blocked therapist, therapist was the blocked party
        : 'finalMessageSentByParent';    // if therapist blocked parent, parent was the blocked party
    final finalReplyField = unblockerRole == 'parent'
        ? 'finalReplySentByParent'
        : 'finalReplySentByTherapist';
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({
          blockField: false,
          finalMsgField: false,
          finalReplyField: false,
        }, SetOptions(merge: true));

    // 3. Notify unblocked user
    try {
      await _firestore.collection('notifications').add({
        'userId': blockedId,
        'title': '\u2705 You have been unblocked',
        'message': 'You have been unblocked. Normal messaging has been restored.',
        'category': 'messages',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'navigationTarget': {'route': 'chat', 'threadId': threadId},
      });
    } catch (_) {}
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

  @override
  Future<BlockInfo> isUserBlockedWithInfo({
    required String peerId,
    required TherapistThread thread,
    required String myRole,
  }) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) return const BlockInfo();

    // Use thread flags (live, fast)
    final iBlockedThem = myRole == 'parent'
        ? thread.blockedByParent
        : thread.blockedByTherapist;
    final theyBlockedMe = myRole == 'parent'
        ? thread.blockedByTherapist
        : thread.blockedByParent;

    String blockerName = '';
    if (iBlockedThem) {
      blockerName = myRole == 'parent'
          ? thread.parentDisplayName
          : thread.therapistDisplayName;
    } else if (theyBlockedMe) {
      blockerName = myRole == 'parent'
          ? thread.therapistDisplayName
          : thread.parentDisplayName;
    }

    return BlockInfo(
      iBlockedThem: iBlockedThem,
      theyBlockedMe: theyBlockedMe,
      blockerDisplayName: blockerName,
    );
  }

  @override
  Future<void> sendFinalMessage({
    required String threadId,
    required String senderRole,
    required String body,
  }) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    final threadDoc = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .get();
    final data = threadDoc.data() ?? {};
    final threadStatus = data['status']?.toString();
    if (threadStatus == 'locked' || threadStatus == 'reported') {
      throw StateError('Cannot send message: This conversation is currently locked.');
    }
    final alreadySent = senderRole == 'parent'
        ? data['finalMessageSentByParent'] == true
        : data['finalMessageSentByTherapist'] == true;
    if (alreadySent) {
      throw StateError('Final message already sent.');
    }

    // Write the message with messageType: 'final'
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .collection('messages')
        .add({
          'senderId': myId,
          'senderRole': senderRole,
          'body': body,
          'attachments': <String>[],
          'messageType': 'final',
          'deliveryStatus': 'sent',
          'sentAt': FieldValue.serverTimestamp(),
        });

    // Flip the flag
    final flagField = senderRole == 'parent'
        ? 'finalMessageSentByParent'
        : 'finalMessageSentByTherapist';
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({
          flagField: true,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessagePreview': '\uD83D\uDCE9 Final message sent',
        }, SetOptions(merge: true));
  }

  @override
  Future<void> sendFinalReply({
    required String threadId,
    required String senderRole,
    required String body,
  }) async {
    final myId = _auth.currentUser?.uid;
    if (myId == null) throw StateError('No logged in user');

    final threadDoc = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .get();
    final data = threadDoc.data() ?? {};
    final threadStatus = data['status']?.toString();
    if (threadStatus == 'locked' || threadStatus == 'reported') {
      throw StateError('Cannot send message: This conversation is currently locked.');
    }
    final alreadyReplied = senderRole == 'parent'
        ? data['finalReplySentByParent'] == true
        : data['finalReplySentByTherapist'] == true;
    if (alreadyReplied) {
      throw StateError('Final reply already sent.');
    }

    // Write the reply message with messageType: 'final_reply'
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .collection('messages')
        .add({
          'senderId': myId,
          'senderRole': senderRole,
          'body': body,
          'attachments': <String>[],
          'messageType': 'final_reply',
          'deliveryStatus': 'sent',
          'sentAt': FieldValue.serverTimestamp(),
        });

    // Flip the flag
    final flagField = senderRole == 'parent'
        ? 'finalReplySentByParent'
        : 'finalReplySentByTherapist';
    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({
          flagField: true,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessagePreview': '\uD83D\uDCAC One-time reply sent',
        }, SetOptions(merge: true));
  }

  // In-app Notifications
  @override
  Stream<List<NotificationInboxItem>> watchNotifications() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return const Stream.empty();
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotificationInboxItem.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return list;
        });
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
      final role = (data['role'] ?? '').toString();
      final isTherapist = role == 'therapist' || data['therapistNotificationPreferences'] != null;
      final prefs = boolMapFrom(data['notificationPreferences'] ?? data['therapistNotificationPreferences']);
      bool enabled = true;

      if (isTherapist) {
        if (category == 'messages') {
          enabled = prefs['newMessages'] ?? true;
        } else if (category == 'activities') {
          enabled = prefs['reminders'] ?? true;
        } else if (category == 'subscription') {
          enabled = prefs['payments'] ?? true;
        } else if (category == 'reviews') {
          enabled = prefs['bookings'] ?? true;
        } else if (category == 'emergency') {
          enabled = prefs['emergency'] ?? true;
        }
      } else {
        if (category == 'messages') {
          enabled = prefs['therapistsUpdate'] ?? prefs['pushNotifications'] ?? true;
        } else if (category == 'activities' || category == 'scheduler') {
          enabled = prefs['routineReminders'] ?? prefs['dailyReminders'] ?? true;
        } else if (category == 'progress') {
          enabled = prefs['levelProgressNotification'] ?? prefs['progressUpdates'] ?? true;
        } else if (category == 'subscription') {
          enabled = prefs['subscription'] ?? prefs['emailNotifications'] ?? true;
        } else if (category == 'reviews') {
          enabled = prefs['activityAlerts'] ?? true;
        }
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

  // Clinical Notes
  @override
  Future<void> createClinicalNote({
    required String therapistId,
    required String parentId,
    required String childId,
    required String therapistName,
    required String childName,
    required String title,
    required String body,
    String? slotId,
  }) async {
    final noteRef = _firestore.collection(FirestoreCollections.clinicalNotes).doc();
    final note = ClinicalNote(
      id: noteRef.id,
      therapistId: therapistId,
      parentId: parentId,
      childId: childId,
      therapistName: therapistName,
      childName: childName,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    final batch = _firestore.batch();
    batch.set(noteRef, note.toMap());
    if (slotId != null && slotId.isNotEmpty) {
      final slotRef = _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId);
      batch.update(slotRef, {
        'sessionCompleted': true,
        'clinicalNote': body,
      });
    }
    await batch.commit();
  }

  @override
  Stream<List<ClinicalNote>> watchClinicalNotesForChild(String childId) {
    return _firestore
        .collection(FirestoreCollections.clinicalNotes)
        .where('childId', isEqualTo: childId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ClinicalNote.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<ClinicalNote>> watchClinicalNotesForTherapist(String therapistId) {
    return _firestore
        .collection(FirestoreCollections.clinicalNotes)
        .where('therapistId', isEqualTo: therapistId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ClinicalNote.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> deleteClinicalNote(String noteId) async {
    await _firestore.collection(FirestoreCollections.clinicalNotes).doc(noteId).delete();
  }

  // Appointment Slots
  @override
  Future<void> createAppointmentSlot({
    required String therapistId,
    required DateTime dateTime,
    required int durationMinutes,
    String? packageTitle,
    String? assignedToParentId,
  }) async {
    final slotRef = _firestore.collection(FirestoreCollections.appointmentSlots).doc();
    final slot = AppointmentSlot(
      id: slotRef.id,
      therapistId: therapistId,
      dateTime: dateTime,
      durationMinutes: durationMinutes,
      status: 'available',
      createdAt: DateTime.now(),
      packageTitle: packageTitle,
      assignedToParentId: assignedToParentId,
    );
    await slotRef.set(slot.toMap());
  }


  @override
  Stream<List<AppointmentSlot>> watchSlotsForParent(String parentId) {
    return _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => AppointmentSlot.fromMap(doc.id, doc.data()))
              .where((slot) => slot.bookedByParentId == parentId || slot.assignedToParentId == parentId)
              .toList();
        });
  }

  @override
  Future<void> markSessionCompleted(String slotId) async {
    await _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .doc(slotId)
        .update({'sessionCompleted': true});
  }

  // Slot Requests
  @override
  Future<void> createSlotRequest({
    required String parentId,
    required String parentName,
    required String therapistId,
    required String packageTitle,
    required DateTime preferredDateTime,
  }) async {
    final docRef = _firestore.collection('slot_requests').doc();
    final request = SlotRequest(
      id: docRef.id,
      parentId: parentId,
      parentName: parentName,
      therapistId: therapistId,
      packageTitle: packageTitle,
      preferredDateTime: preferredDateTime,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    await docRef.set(request.toMap());
  }

  @override
  Stream<List<SlotRequest>> watchSlotRequestsForTherapist(String therapistId) {
    return _firestore
        .collection('slot_requests')
        .where('therapistId', isEqualTo: therapistId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => SlotRequest.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<SlotRequest>> watchSlotRequestsForParent(String parentId) {
    return _firestore
        .collection('slot_requests')
        .where('parentId', isEqualTo: parentId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => SlotRequest.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> acknowledgeSlotRequest(String requestId) async {
    await _firestore
        .collection('slot_requests')
        .doc(requestId)
        .update({'status': 'approved'});
  }

  @override
  Future<void> declineSlotRequest(String requestId, String reason) async {
    await _firestore
        .collection('slot_requests')
        .doc(requestId)
        .update({
          'status': 'declined',
          'declineReason': reason,
        });
  }

  @override
  Future<void> markSlotRequestAsCreated(String requestId) async {
    await _firestore
        .collection('slot_requests')
        .doc(requestId)
        .update({'status': 'approved'});
  }

  @override
  Stream<List<AppointmentSlot>> watchSlotsForTherapist(String therapistId) {
    return _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .where('therapistId', isEqualTo: therapistId)
        .orderBy('dateTime', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AppointmentSlot.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> bookAppointmentSlot({
    required String slotId,
    required String parentId,
    required String childId,
    required String childName,
    required String notes,
    String? therapistId,
    String? parentName,
  }) async {
    // Detect if parent already has a booked slot with this therapist → reschedule
    if (therapistId != null && therapistId.isNotEmpty) {
      try {
        final existingSnapshot = await _firestore
            .collection(FirestoreCollections.appointmentSlots)
            .where('therapistId', isEqualTo: therapistId)
            .where('bookedByParentId', isEqualTo: parentId)
            .where('status', isEqualTo: 'booked')
            .get();
        for (final oldDoc in existingSnapshot.docs) {
          if (oldDoc.id != slotId) {
            // Free the old slot
            await oldDoc.reference.update({
              'status': 'available',
              'bookedByParentId': FieldValue.delete(),
              'bookedForChildId': FieldValue.delete(),
              'bookedForChildName': FieldValue.delete(),
              'notes': FieldValue.delete(),
            });
          }
        }
      } catch (_) {}
    }

    await _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId).update({
      'status': 'booked',
      'bookedByParentId': parentId,
      'bookedForChildId': childId,
      'bookedForChildName': childName,
      'notes': notes,
    });

    // Notify therapist & parent
    try {
      final slotDoc = await _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId).get();
      final slotData = slotDoc.data();
      final sessionDt = slotData?['dateTime'] != null
          ? (slotData!['dateTime'] as dynamic).toDate() as DateTime
          : DateTime.now();
      final day = sessionDt.day.toString().padLeft(2, '0');
      final month = sessionDt.month.toString().padLeft(2, '0');
      final dateStr = '$day/$month/${sessionDt.year}';
      final hour = sessionDt.hour;
      final hourStr = (hour % 12 == 0 ? 12 : hour % 12).toString();
      final minStr = sessionDt.minute.toString().padLeft(2, '0');
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final timeStr = '$hourStr:$minStr $ampm';

      String resolvedParentName = parentName ?? '';
      if (resolvedParentName.isEmpty) {
        final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
        resolvedParentName = _resolveParentDisplayName(parentDoc.data());
      }
      if (resolvedParentName.isEmpty) {
        resolvedParentName = 'A parent';
      }

      String therapistName = 'Therapist';
      if (therapistId != null && therapistId.isNotEmpty) {
        final therapistDoc = await _firestore
            .collection(FirestoreCollections.therapistProfiles)
            .doc(therapistId)
            .get();
        therapistName = therapistDoc.data()?['displayName']?.toString() ?? 'Therapist';
      }

      // 1. Notify therapist
      if (therapistId != null && therapistId.isNotEmpty) {
        await _firestore.collection('notifications').add({
          'userId': therapistId,
          'title': '\u{1F4C5} Session Booked!',
          'message': '$resolvedParentName has booked a session with you on $dateStr at $timeStr.',
          'category': 'activities',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'TherapistScheduler'},
        });
      }

      // 2. Notify parent
      await _firestore.collection('notifications').add({
        'userId': parentId,
        'title': '\u{1F4C5} Session Booked!',
        'message': 'Your session with $therapistName has been booked successfully on $dateStr at $timeStr.',
        'category': 'activities',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'navigationTarget': {'route': 'ProfessionalSupport'},
      });
    } catch (_) {}
  }

  @override
  Future<void> cancelAppointmentSlot(String slotId, {
    String? parentId,
    String? therapistId,
    String? parentName,
  }) async {
    // 1. Fetch slot data BEFORE updating/deleting fields
    String? dbParentId = parentId;
    String? dbTherapistId = therapistId;
    try {
      final slotDoc = await _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId).get();
      if (slotDoc.exists) {
        final data = slotDoc.data();
        if (data != null) {
          final status = data['status']?.toString();
          if (status != 'booked') {
            debugPrint('cancelAppointmentSlot: Slot $slotId is not booked (status: $status). Early exit.');
            return;
          }
          if (dbParentId == null || dbParentId.isEmpty) {
            dbParentId = data['bookedByParentId']?.toString();
          }
          if (dbTherapistId == null || dbTherapistId.isEmpty) {
            dbTherapistId = data['therapistId']?.toString();
          }
        }
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    // 2. Perform database update
    await _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId).update({
      'status': 'available',
      'bookedByParentId': FieldValue.delete(),
      'bookedForChildId': FieldValue.delete(),
      'bookedForChildName': FieldValue.delete(),
      'notes': FieldValue.delete(),
    });

    final currentUid = _auth.currentUser?.uid;
    final isCancelledByTherapist = currentUid == dbTherapistId;

    // Fetch names
    String therapistName = 'Therapist';
    if (dbTherapistId != null && dbTherapistId.isNotEmpty) {
      try {
        final therapistDoc = await _firestore
            .collection(FirestoreCollections.therapistProfiles)
            .doc(dbTherapistId)
            .get();
        therapistName = therapistDoc.data()?['displayName']?.toString() ?? 'Therapist';
      } catch (_) {}
    }

    String resolvedParentName = '';
    if (parentName != null && parentName.isNotEmpty) {
      resolvedParentName = parentName;
    }
    if (resolvedParentName.isEmpty && dbParentId != null && dbParentId.isNotEmpty) {
      try {
        final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(dbParentId).get();
        resolvedParentName = _resolveParentDisplayName(parentDoc.data());
      } catch (_) {}
    }
    if (resolvedParentName.isEmpty) {
      resolvedParentName = 'A parent';
    }

    // Send notifications to BOTH therapist and parent
    // 1. Therapist notification
    if (dbTherapistId != null && dbTherapistId.isNotEmpty) {
      try {
        final msg = isCancelledByTherapist
            ? 'You have cancelled your scheduled session with $resolvedParentName.'
            : '$resolvedParentName has cancelled the scheduled session.';
        await _firestore.collection('notifications').add({
          'userId': dbTherapistId,
          'title': '\u274C Session Cancelled',
          'message': msg,
          'category': 'activities',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'TherapistScheduler'},
        });
      } catch (_) {}
    }

    // 2. Parent notification
    if (dbParentId != null && dbParentId.isNotEmpty) {
      try {
        final msg = isCancelledByTherapist
            ? '$therapistName has cancelled the scheduled session.'
            : 'You have cancelled your scheduled session with $therapistName.';
        await _firestore.collection('notifications').add({
          'userId': dbParentId,
          'title': '\u274C Session Cancelled',
          'message': msg,
          'category': 'activities',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'ProfessionalSupport'},
        });
      } catch (_) {}
    }
  }

  @override
  Future<void> deleteAppointmentSlot(String slotId) async {
    await _firestore.collection(FirestoreCollections.appointmentSlots).doc(slotId).delete();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Moderation: Restriction Checking
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<RestrictionRecord?> getActiveRestriction({
    required String parentId,
    required String therapistId,
  }) async {
    final snap = await _firestore
        .collection('restrictions')
        .where('parentId', isEqualTo: parentId)
        .where('therapistId', isEqualTo: therapistId)
        .where('status', isEqualTo: 'active')
        .get();
    if (snap.docs.isEmpty) return null;
    final record = RestrictionRecord.fromMap(snap.docs.first.id, snap.docs.first.data());
    if (record.endDate.isAfter(DateTime.now())) {
      return record;
    }
    return null;
  }

  @override
  Stream<RestrictionRecord?> watchActiveRestriction({
    required String parentId,
    required String therapistId,
  }) {
    return _firestore
        .collection('restrictions')
        .where('parentId', isEqualTo: parentId)
        .where('therapistId', isEqualTo: therapistId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final record = RestrictionRecord.fromMap(snap.docs.first.id, snap.docs.first.data());
      if (record.endDate.isAfter(DateTime.now())) {
        return record;
      }
      return null;
    });
  }

  @override
  Future<bool> hasAnyActiveRestriction(String userId) async {
    final now = DateTime.now();
    
    // Check as parent
    final asParent = await _firestore
        .collection('restrictions')
        .where('parentId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .get();
    for (final doc in asParent.docs) {
      final record = RestrictionRecord.fromMap(doc.id, doc.data());
      if (record.endDate.isAfter(now)) {
        return true;
      }
    }

    // Check as therapist
    final asTherapist = await _firestore
        .collection('restrictions')
        .where('therapistId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .get();
    for (final doc in asTherapist.docs) {
      final record = RestrictionRecord.fromMap(doc.id, doc.data());
      if (record.endDate.isAfter(now)) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<bool> hasActiveRestrictionBetween({
    required String parentId,
    required String therapistId,
  }) async {
    final now = DateTime.now();
    final snap = await _firestore
        .collection('restrictions')
        .where('parentId', isEqualTo: parentId)
        .where('therapistId', isEqualTo: therapistId)
        .where('status', isEqualTo: 'active')
        .get();
    for (final doc in snap.docs) {
      final record = RestrictionRecord.fromMap(doc.id, doc.data());
      if (record.endDate.isAfter(now)) {
        return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Moderation: One-Time Messages
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> submitReportMessage({
    required String reportId,
    required String messageType,
    required String content,
    required String requestedByAdminId,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No logged-in user');

    // Fetch sender's role from their user doc
    final userDoc = await _firestore.collection(FirestoreCollections.users).doc(user.uid).get();
    final senderRole = (userDoc.data()?['role'] ?? 'parent').toString();

    final msgRef = _firestore
        .collection('reports')
        .doc(reportId)
        .collection('messages')
        .doc();

    await msgRef.set({
      'reportId': reportId,
      'senderId': user.uid,
      'senderRole': senderRole,
      'messageType': messageType,
      'content': content,
      'requestedByAdminId': requestedByAdminId,
      'attachments': attachments,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<ReportMessage>> watchReportMessages(String reportId) {
    return _firestore
        .collection('reports')
        .doc(reportId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ReportMessage.fromMap(d.id, d.data()))
            .toList());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Moderation: History
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<List<ModerationHistoryEntry>> getModerationHistory(String userId) async {
    final snap = await _firestore
        .collection('moderation_history')
        .where('targetUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => ModerationHistoryEntry.fromMap(d.id, d.data()))
        .toList();
  }

  @override
  Stream<List<ModerationHistoryEntry>> watchModerationHistory(String userId) {
    return _firestore
        .collection('moderation_history')
        .where('targetUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ModerationHistoryEntry.fromMap(d.id, d.data()))
            .toList());
  }
}


class FirebaseBillingRepository implements BillingRepository {
  FirebaseBillingRepository(this._auth, this._firestore, this._paymentBackend);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final PaymentBackendClient _paymentBackend;

  String _subscriptionDocId(String userId, String therapistId) =>
      '${userId.trim()}_${therapistId.trim()}';

  UserSubscription _localBypassSubscription(String userId, String therapistId) {
    return UserSubscription(
      id: _subscriptionDocId(userId, therapistId),
      userId: userId,
      therapistId: therapistId,
      productId: 'bypass-plan',
      status: 'active',
      cancelAtPeriodEnd: false,
      currentPeriodEnd: DateTime.now().add(const Duration(days: 3650)),
    );
  }

  String _requireAuthenticatedUser({required String action}) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('You need to be logged in to $action.');
    }
    return userId;
  }

  Map<String, dynamic> _makeMapEncodable(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, {'_type': 'Timestamp', 'value': value.millisecondsSinceEpoch});
      } else if (value is DateTime) {
        return MapEntry(key, {'_type': 'DateTime', 'value': value.millisecondsSinceEpoch});
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, _makeMapEncodable(value));
      } else if (value is List) {
        final encodableList = value.map((item) {
          if (item is Timestamp) {
            return {'_type': 'Timestamp', 'value': item.millisecondsSinceEpoch};
          } else if (item is DateTime) {
            return {'_type': 'DateTime', 'value': item.millisecondsSinceEpoch};
          } else if (item is Map<String, dynamic>) {
            return _makeMapEncodable(item);
          }
          return item;
        }).toList();
        return MapEntry(key, encodableList);
      }
      return MapEntry(key, value);
    });
  }

  Map<String, dynamic> _restoreEncodableMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is Map<String, dynamic>) {
        if (value['_type'] == 'Timestamp') {
          return MapEntry(key, Timestamp.fromMillisecondsSinceEpoch(value['value'] as int));
        } else if (value['_type'] == 'DateTime') {
          return MapEntry(key, DateTime.fromMillisecondsSinceEpoch(value['value'] as int));
        }
        return MapEntry(key, _restoreEncodableMap(value));
      } else if (value is List) {
        final restoredList = value.map((item) {
          if (item is Map<String, dynamic>) {
            if (item['_type'] == 'Timestamp') {
              return Timestamp.fromMillisecondsSinceEpoch(item['value'] as int);
            } else if (item['_type'] == 'DateTime') {
              return DateTime.fromMillisecondsSinceEpoch(item['value'] as int);
            }
            return _restoreEncodableMap(item);
          }
          return item;
        }).toList();
        return MapEntry(key, restoredList);
      }
      return MapEntry(key, value);
    });
  }

  Future<String> _resolveProductIdForTherapist(String therapistId, {int packageIndex = 0}) async {
    final therapistSnapshot = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .doc(therapistId)
        .get();
    final therapistData =
        therapistSnapshot.data() ?? const <String, dynamic>{};

    // ── Derive a deterministic product ID from servicePackages ────────
    final rawPackages = therapistData['servicePackages'];
    if (rawPackages is List && rawPackages.isNotEmpty) {
      final visiblePackages = rawPackages
          .whereType<Map>()
          .where((p) => p['visible'] != false)
          .toList();
      if (packageIndex >= 0 && packageIndex < visiblePackages.length) {
        final pkg = visiblePackages[packageIndex];
        final rawPrice = pkg['price'];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0;
        if (price > 0) {
          return 'auto_${therapistId}_$packageIndex';
        }
      } else if (visiblePackages.isNotEmpty) {
        final pkg = visiblePackages.first;
        final rawPrice = pkg['price'];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0;
        if (price > 0) {
          return 'auto_${therapistId}_0';
        }
      }
    }

    final existingProductId =
        (therapistData['subscriptionProductId'] ?? '').toString().trim();
    if (existingProductId.isNotEmpty) {
      return existingProductId;
    }

    throw StateError(
      'This therapist has no service packages with a valid price. '
      'Add at least one visible service package in therapist profile settings.',
    );
  }

  Future<bool> _waitForSubscriptionActivation({
    required String userId,
    required String therapistId,
    bool Function()? isCancelledCheck,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final docId = _subscriptionDocId(userId, therapistId);
    final startedAt = DateTime.now();
    // SafePay has a known sandbox/production race condition where the failure-redirect
    // fires before the payment is fully confirmed, temporarily writing 'payment_failed'
    // to Firestore. The backend then double-checks with the gateway and rewrites the
    // status to 'active'. We allow a 45-second grace window before treating
    // 'payment_failed' as terminal, and proactively trigger a backend re-verification
    // during that window so the correction happens faster.
    const gracePeriod = Duration(seconds: 45);

    final wakeupController = StreamController<void>.broadcast();
    StreamSubscription<PaymentDeepLinkResult>? deepLinkSub;
    bool forceCheckNow = false;

    // Listen to deep links to wake up the polling loop and force a check immediately.
    final userPart = userId.length > 8 ? userId.substring(0, 8) : userId;
    final therapistPart = therapistId.length > 8 ? therapistId.substring(0, 8) : therapistId;

    deepLinkSub = PaymentDeepLinkService.instance.results.listen((result) {
      final isMatch = result.basketId.contains(userPart) && result.basketId.contains(therapistPart);
      if (isMatch || result.basketId.isEmpty) {
        debugPrint('_waitForSubscriptionActivation: Deep link received status=${result.status} basket=${result.basketId}');
        if (result.isSuccess) {
          forceCheckNow = true;
          if (!wakeupController.isClosed) {
            wakeupController.add(null);
          }
        }
      }
    });

    try {
      while (DateTime.now().difference(startedAt) < timeout) {
        if (isCancelledCheck != null && isCancelledCheck()) {
          debugPrint('_waitForSubscriptionActivation: isCancelledCheck is true (checkout cancelled by UI). Exiting.');
          return false;
        }

        if (forceCheckNow) {
          forceCheckNow = false;
          debugPrint('_waitForSubscriptionActivation: Forcing backend check due to success deep link.');
          try {
            await _paymentBackend.checkSubscriptionStatus(therapistId);
          } catch (e) {
            debugPrint('_waitForSubscriptionActivation: backend re-verification error on success deep link: $e');
          }
        }

        final snapshot = await _firestore
            .collection(FirestoreCollections.subscriptions)
            .doc(docId)
            .get();
        if (snapshot.exists && snapshot.data() != null) {
          final subscription = UserSubscription.fromMap(snapshot.id, snapshot.data()!);
          final status = subscription.status.trim().toLowerCase();
          debugPrint('_waitForSubscriptionActivation: Firestore doc status=$status isActive=${subscription.isActive}');
          if (subscription.isActive || status == 'active') {
            debugPrint('_waitForSubscriptionActivation: subscription is active. Returning true.');
            return true;
          }
          // 'canceled' and 'expired' are admin-set terminal states — exit immediately.
          if (status == 'canceled' || status == 'expired') {
            debugPrint('_waitForSubscriptionActivation: terminal status=$status. Returning false.');
            return false;
          }
          // 'payment_failed' may be a transient SafePay redirect race condition.
          // Only treat it as terminal after the grace period has elapsed.
          // During the grace period, trigger a backend re-verification on each observation.
          if (status == 'payment_failed') {
            final elapsed = DateTime.now().difference(startedAt);
            if (elapsed >= gracePeriod) {
              debugPrint('_waitForSubscriptionActivation: payment_failed confirmed after grace period — exiting.');
              return false;
            }
            debugPrint('_waitForSubscriptionActivation: payment_failed within grace period (${elapsed.inSeconds}s) — triggering backend re-verification.');
            try {
              await _paymentBackend.checkSubscriptionStatus(therapistId);
            } catch (e) {
              debugPrint('_waitForSubscriptionActivation: backend re-verification error: $e');
            }
          }
        } else {
          debugPrint('_waitForSubscriptionActivation: Firestore doc does not exist yet.');
        }

        // Wait for 3 seconds OR until the success deep link stream wakes us up
        try {
          await wakeupController.stream.first.timeout(const Duration(seconds: 3));
        } catch (_) {
          // Timeout is expected
        }
      }
    } finally {
      await deepLinkSub.cancel();
      await wakeupController.close();
    }
    debugPrint('_waitForSubscriptionActivation: Polling timed out. Returning false.');
    return false;
  }

  Future<void> _updateUserEntitlements(String userId) async {
    final activeSnapshot = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: const ['active', 'trialing', 'grace_period'])
        .limit(1)
        .get();
    final hasActive = activeSnapshot.docs.isNotEmpty;
    await _firestore.collection(FirestoreCollections.users).doc(userId).set({
      'subscriptionTier': hasActive ? 'professional-support' : 'free',
      'entitlements': {
        'professionalSupport': hasActive,
        'chatAccess': hasActive,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
  Future<UserSubscription?> getSubscriptionForTherapist(
    String therapistId,
  ) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      return null;
    }
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return null;
    }
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return _localBypassSubscription(userId, normalizedTherapistId);
    }
    final docId = _subscriptionDocId(userId, normalizedTherapistId);
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.subscriptions)
          .doc(docId)
          .get();
      if (!snapshot.exists || snapshot.data() == null) {
        await _cacheSubscriptionStateOffline(docId, isActive: false);
        return null;
      }
      final sub = UserSubscription.fromMap(snapshot.id, snapshot.data()!);
      await _cacheSubscriptionStateOffline(docId, isActive: sub.isActive);
      return sub;
    } catch (_) {
      final cachedActive = await _getCachedSubscriptionStateOffline(docId);
      if (cachedActive) {
        return UserSubscription(
          id: docId,
          userId: userId,
          therapistId: therapistId,
          productId: 'cached-offline',
          status: 'active',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 1)),
        );
      }
      return null;
    }
  }

  @override
  Stream<UserSubscription?> watchSubscriptionForTherapist(String therapistId) {
    final normalizedTherapistId = therapistId.trim();
    final userId = _auth.currentUser?.uid;
    if (userId == null || normalizedTherapistId.isEmpty) {
      return const Stream<UserSubscription?>.empty();
    }
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return Stream<UserSubscription?>.value(
        _localBypassSubscription(userId, normalizedTherapistId),
      );
    }
    final docId = _subscriptionDocId(userId, normalizedTherapistId);
    return _firestore
        .collection(FirestoreCollections.subscriptions)
        .doc(docId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) {
            _cacheSubscriptionStateOffline(docId, isActive: false);
            return null;
          }
          final sub = UserSubscription.fromMap(snapshot.id, data);
          _cacheSubscriptionStateOffline(docId, isActive: sub.isActive);
          return sub;
        });
  }

  Future<void> _cacheSubscriptionStateOffline(String docId, {required bool isActive}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sub_active_$docId', isActive);
    } catch (_) {}
  }

  Future<bool> _getCachedSubscriptionStateOffline(String docId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('sub_active_$docId') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> syncSubscriptionStatus(String therapistId) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      return;
    }
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return;
    }
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return;
    }
    
    // Trigger direct backend gateway verification request
    await _paymentBackend.checkSubscriptionStatus(normalizedTherapistId);
    await _updateUserEntitlements(userId);
  }

  @override
  Future<String?> prepareCheckoutUrl(String therapistId, {int packageIndex = 0}) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      throw StateError('Missing therapist id.');
    }
    _requireAuthenticatedUser(action: 'purchase a subscription');
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return null;
    }
    if (!_paymentBackend.isConfigured) {
      throw StateError(
        'Payment backend is not configured. Start app with '
        '--dart-define=PAYMENT_BACKEND_BASE_URL=https://your-backend-url',
      );
    }
    final productId = await _resolveProductIdForTherapist(normalizedTherapistId, packageIndex: packageIndex);

    final checkoutUrl = await _paymentBackend.createCheckoutSession(
      therapistId: normalizedTherapistId,
      productId: productId,
      successUrl: AppRuntimeConfig.paymentSuccessUrl,
      cancelUrl: AppRuntimeConfig.paymentCancelUrl,
    );
    return checkoutUrl;
  }

  @override
  Future<bool> purchaseTherapistSubscription(
    String therapistId, {
    int packageIndex = 0,
    bool Function()? isCancelledCheck,
    void Function()? onUrlLaunched,
  }) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      throw StateError('Missing therapist id.');
    }
    final userId = _requireAuthenticatedUser(action: 'purchase a subscription');
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return true;
    }

    final docId = _subscriptionDocId(userId, normalizedTherapistId);
    try {
      final doc = await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).get();
      if (doc.exists && doc.data() != null) {
        final isActive = doc.data()?['isActive'] == true;
        if (isActive) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('backup_sub_$docId', jsonEncode(_makeMapEncodable(doc.data()!)));
          debugPrint('Backed up active subscription $docId before plan switch');
        }
      }
    } catch (e) {
      debugPrint('Failed to backup active subscription: $e');
    }

    if (isCancelledCheck != null && isCancelledCheck()) {
      return false;
    }

    final checkoutUrl = await prepareCheckoutUrl(normalizedTherapistId, packageIndex: packageIndex);
    if (checkoutUrl == null || checkoutUrl.trim().isEmpty) {
      if (AppRuntimeConfig.bypassProSupportPaywall) {
        return true;
      }
      throw StateError('Payment backend did not return a checkout URL.');
    }

    if (isCancelledCheck != null && isCancelledCheck()) {
      return false;
    }

    final launched = await launchUrl(
      Uri.parse(checkoutUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Unable to open payment checkout.');
    }

    if (onUrlLaunched != null) {
      onUrlLaunched();
    }

    if (isCancelledCheck != null && isCancelledCheck()) {
      return false;
    }

    final active = await _waitForSubscriptionActivation(
      userId: userId,
      therapistId: normalizedTherapistId,
      isCancelledCheck: isCancelledCheck,
    );
    await _updateUserEntitlements(userId);
    if (active) {
      final docId = _subscriptionDocId(userId, normalizedTherapistId);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('backup_sub_$docId');
      } catch (_) {}
      
      try {
        final profileDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(normalizedTherapistId).get();
        if (profileDoc.exists && profileDoc.data() != null) {
          final profile = TherapistProfile.fromMap(profileDoc.id, profileDoc.data()!);
          final pkg = profile.servicePackages[packageIndex];
          await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).set({
            'subscribedPackageSnapshot': pkg.toMap(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Failed to save subscribed package snapshot: $e');
      }
      return true;
    }
    final latest = await getSubscriptionForTherapist(normalizedTherapistId);
    return latest?.isActive == true;
  }

  @override
  Future<void> deletePendingSubscription(String therapistId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    final docId = _subscriptionDocId(userId, therapistId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupStr = prefs.getString('backup_sub_$docId');
      
      if (backupStr != null) {
        final backupData = jsonDecode(backupStr) as Map<String, dynamic>;
        await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).set(_restoreEncodableMap(backupData));
        await prefs.remove('backup_sub_$docId');
        debugPrint('Successfully restored backup active subscription $docId on user cancellation request');
        return;
      }

      final doc = await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).get();
      if (doc.exists && doc.data() != null) {
        final status = (doc.data()?['status'] ?? '').toString().trim().toLowerCase();
        final isActive = doc.data()?['isActive'] == true;
        if (!isActive && (status == 'pending' || status == 'payment_failed')) {
          await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).delete();
          debugPrint('Successfully deleted pending/failed subscription $docId on user cancellation request');
        }
      }
    } catch (e) {
      debugPrint('Failed to delete pending/restore backup subscription: $e');
    }
  }

  @override
  Future<void> cancelSubscriptionInStore(
    String therapistId, {
    required bool keepAndLockChats,
    String? reason,
  }) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      throw StateError('Missing therapist id.');
    }
    final userId = _requireAuthenticatedUser(action: 'manage subscriptions');
    final docId = _subscriptionDocId(userId, normalizedTherapistId);

    if (reason != null && reason.trim().isNotEmpty) {
      try {
        await _firestore.collection('cancellation_analytics').add({
          'parentId': userId,
          'therapistId': normalizedTherapistId,
          'reason': reason.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Failed to log cancellation analytics: $e');
      }
    }

    if (AppRuntimeConfig.bypassProSupportPaywall) {
      // In bypass mode, update Firestore directly to cancel
      try {
        await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).set({
          'status': 'canceled',
          'isActive': false,
          'cancelAtPeriodEnd': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Direct client-side subscription update failed: $e');
      }
    } else {
      if (!_paymentBackend.isConfigured) {
        throw StateError(
          'Payment backend is not configured. Start app with '
          '--dart-define=PAYMENT_BACKEND_BASE_URL=https://your-backend-url',
        );
      }
      await _paymentBackend.cancelSubscription(docId);
      // Ensure Firestore subscription doc reflects the cancelled status locally immediately
      try {
        await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).set({
          'status': 'canceled',
          'isActive': false,
          'cancelAtPeriodEnd': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Direct client-side subscription update failed: $e');
      }
    }

    // 2. Remove the therapist from the parent's active subscriptions field
    try {
      await _firestore.collection(FirestoreCollections.users).doc(userId).set({
        'proSupportSubscribedTherapistIds': FieldValue.arrayRemove([normalizedTherapistId]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to remove therapist from parent proSupportSubscribedTherapistIds: $e');
    }

    // 3. Cancel all upcoming booked therapy sessions and pending bookings for this parent & therapist
    try {
      final bookedSlotsSnapshot = await _firestore
          .collection(FirestoreCollections.appointmentSlots)
          .where('therapistId', isEqualTo: normalizedTherapistId)
          .where('bookedByParentId', isEqualTo: userId)
          .get();

      for (final slotDoc in bookedSlotsSnapshot.docs) {
        final slotId = slotDoc.id;
        await slotDoc.reference.update({
          'status': 'available',
          'bookedByParentId': FieldValue.delete(),
          'bookedForChildId': FieldValue.delete(),
          'bookedForChildName': FieldValue.delete(),
          'notes': FieldValue.delete(),
        });
        // 4. Remove scheduled local notifications
        try {
          await NotificationService.instance.cancelSessionReminder(slotId.hashCode.abs());
        } catch (e) {
          debugPrint('Failed to cancel local session reminder: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to cancel booked appointment slots: $e');
    }

    // 5. Remove any in-app reminder notifications from Firestore for this therapist and parent
    try {
      final remindersSnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('category', isEqualTo: 'activities')
          .where('title', isEqualTo: '⏰ Session Reminder')
          .get();

      final batch = _firestore.batch();
      var count = 0;
      for (final doc in remindersSnapshot.docs) {
        final targetUser = doc.data()['userId']?.toString() ?? '';
        if (targetUser == userId || targetUser == normalizedTherapistId) {
          batch.delete(doc.reference);
          count++;
          if (count >= 400) {
            await batch.commit();
            count = 0;
          }
        }
      }
      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Failed to clean up session reminder notifications: $e');
    }
    
    // Handle chat history deletion vs lock
    final threadSnapshot = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('parentId', isEqualTo: userId)
        .where('therapistId', isEqualTo: normalizedTherapistId)
        .get();

    for (final doc in threadSnapshot.docs) {
      if (!keepAndLockChats) {
        // Delete messages subcollection in chunks of 400 to respect Firestore batch write limits
        final msgsSnapshot = await doc.reference.collection('messages').get();
        final docsList = msgsSnapshot.docs;
        for (var i = 0; i < docsList.length; i += 400) {
          final end = (i + 400 > docsList.length) ? docsList.length : i + 400;
          final chunk = docsList.sublist(i, end);
          final batch = _firestore.batch();
          for (final msg in chunk) {
            batch.delete(msg.reference);
          }
          await batch.commit();
        }
        // Delete parent thread doc itself
        await doc.reference.delete();
      } else {
        // Keep and Lock: Update thread status to locked
        await doc.reference.set({
          'status': 'locked',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await _updateUserEntitlements(userId);

    // Bypass mode: notify parent and therapist of cancellation client-side
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      try {
        final therapistProfile = await _firestore
            .collection(FirestoreCollections.therapistProfiles)
            .doc(normalizedTherapistId)
            .get();
        final therapistDisplayName = therapistProfile.data()?['displayName']?.toString() ?? 'Therapist';
        final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(userId).get();
        final parentData = parentDoc.data() ?? {};
        final pFirst = (parentData['firstName'] ?? '').toString().trim();
        final pLast = (parentData['lastName'] ?? '').toString().trim();
        final parentDisplayName = '$pFirst $pLast'.trim().isNotEmpty
            ? '$pFirst $pLast'.trim()
            : (parentData['fullName'] ?? parentData['displayName'] ?? 'A parent').toString().trim();
        await _firestore.collection('notifications').add({
          'userId': userId,
          'title': '❌ Subscription Cancelled',
          'message': 'Your subscription to $therapistDisplayName has been cancelled.',
          'category': 'subscription',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'ProfessionalSupport'},
        });
        await _firestore.collection('notifications').add({
          'userId': normalizedTherapistId,
          'title': '❌ Subscription Cancelled',
          'message': '$parentDisplayName has cancelled their subscription.',
          'category': 'subscription',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'TherapistDashboard'},
        });
      } catch (_) {}
    }
  }

  @override
  Future<void> reactivateSubscriptionInStore(String therapistId) async {
    final normalizedTherapistId = therapistId.trim();
    if (normalizedTherapistId.isEmpty) {
      throw StateError('Missing therapist id.');
    }
    final userId = _requireAuthenticatedUser(action: 'manage subscriptions');
    final docId = _subscriptionDocId(userId, normalizedTherapistId);

    if (AppRuntimeConfig.bypassProSupportPaywall) {
      // In bypass mode, update Firestore directly to active
      try {
        await _firestore.collection(FirestoreCollections.subscriptions).doc(docId).set({
          'status': 'active',
          'isActive': true,
          'cancelAtPeriodEnd': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Direct client-side subscription update failed: $e');
      }
    } else {
      if (!_paymentBackend.isConfigured) {
        throw StateError(
          'Payment backend is not configured. Start app with '
          '--dart-define=PAYMENT_BACKEND_BASE_URL=https://your-backend-url',
        );
      }
      await _paymentBackend.reactivateSubscription(docId);
    }

    // Set thread status back to active if it was locked
    final threadSnapshot = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('parentId', isEqualTo: userId)
        .where('therapistId', isEqualTo: normalizedTherapistId)
        .get();

    for (final doc in threadSnapshot.docs) {
      await doc.reference.set({
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await _updateUserEntitlements(userId);

    // Bypass mode: notify parent and therapist of reactivation client-side
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      try {
        final therapistProfile = await _firestore
            .collection(FirestoreCollections.therapistProfiles)
            .doc(normalizedTherapistId)
            .get();
        final therapistDisplayName = therapistProfile.data()?['displayName']?.toString() ?? 'Therapist';
        final parentDoc = await _firestore.collection(FirestoreCollections.users).doc(userId).get();
        final parentData = parentDoc.data() ?? {};
        final pFirstR = (parentData['firstName'] ?? '').toString().trim();
        final pLastR = (parentData['lastName'] ?? '').toString().trim();
        final parentDisplayName = '$pFirstR $pLastR'.trim().isNotEmpty
            ? '$pFirstR $pLastR'.trim()
            : (parentData['fullName'] ?? parentData['displayName'] ?? 'A parent').toString().trim();
        await _firestore.collection('notifications').add({
          'userId': userId,
          'title': '\u{1F504} Subscription Reactivated',
          'message': 'Your subscription to $therapistDisplayName has been reactivated.',
          'category': 'subscription',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'ProfessionalSupport'},
        });
        await _firestore.collection('notifications').add({
          'userId': normalizedTherapistId,
          'title': '\u{1F504} Subscription Reactivated',
          'message': '$parentDisplayName has reactivated their subscription.',
          'category': 'subscription',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'navigationTarget': {'route': 'TherapistDashboard'},
        });
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, dynamic>> getTherapistWallet(String therapistId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .doc(therapistId.trim())
        .get();
    if (!snapshot.exists || snapshot.data() == null) {
      return {'walletBalance': 0.0, 'totalEarnings': 0.0};
    }
    final data = snapshot.data()!;
    return {
      'walletBalance': double.tryParse((data['walletBalance'] ?? 0.0).toString()) ?? 0.0,
      'totalEarnings': double.tryParse((data['totalEarnings'] ?? 0.0).toString()) ?? 0.0,
    };
  }

  @override
  Future<void> requestWithdrawal(
    String therapistId,
    double amount,
    String paymentMethod,
    String accountDetails, {
    bool isAppeal = false,
    String? appealReason,
  }) async {
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      final normalizedId = therapistId.trim();
      try {
        // 1. Deduct wallet balance directly in Firestore since rules allow therapist updates
        await _firestore.collection(FirestoreCollections.therapistProfiles).doc(normalizedId).set({
          'walletBalance': FieldValue.increment(-amount),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 2. Save a mock withdrawal transaction in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final key = 'mock_transactions_$normalizedId';
        final mockTxnsJson = prefs.getString(key) ?? '[]';
        final List<dynamic> list = jsonDecode(mockTxnsJson);
        list.add({
          'id': 'mock_withdraw_${DateTime.now().millisecondsSinceEpoch}',
          'therapistId': normalizedId,
          'amount': amount,
          'type': 'withdrawal',
          'paymentMethod': paymentMethod,
          'accountDetails': accountDetails,
          'status': 'pending',
          'isAppeal': isAppeal,
          'appealReason': appealReason,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
        await prefs.setString(key, jsonEncode(list));
      } catch (e) {
        debugPrint('Failed to perform mock withdrawal: $e');
        throw StateError('Mock withdrawal failed: $e');
      }
      return;
    }

    if (!_paymentBackend.isConfigured) {
      throw StateError('Payment backend is not configured.');
    }
    await _paymentBackend.requestWithdrawal(
      amount: amount,
      paymentMethod: paymentMethod,
      accountDetails: accountDetails,
      isAppeal: isAppeal,
      appealReason: appealReason,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getTherapistTransactions(String therapistId) async {
    final snapshot = await _firestore
        .collection('therapist_earnings')
        .where('therapistId', isEqualTo: therapistId.trim())
        .get();
    final docs = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

    // If bypass paywall is enabled, load mock transactions from shared preferences
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final mockTxnsJson = prefs.getString('mock_transactions_$therapistId') ?? '[]';
        final List<dynamic> parsed = jsonDecode(mockTxnsJson);
        for (final item in parsed) {
          final map = Map<String, dynamic>.from(item);
          if (map['createdAt'] != null) {
            map['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(map['createdAt'] as int);
          }
          docs.add(map);
        }
      } catch (e) {
        debugPrint('Failed to load mock transactions: $e');
      }
    }

    docs.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return docs;
  }

  @override
  Future<List<Map<String, dynamic>>> getParentTransactions() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return const [];
    }
    final snapshot = await _firestore
        .collection('therapist_earnings')
        .where('userId', isEqualTo: userId)
        .get();
    final docs = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    docs.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return docs;
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
    int banned = 0;

    for (final doc in therapistsSnap.docs) {
      final status = (doc.data()['verificationStatus'] ?? 'pending').toString();
      if (status == 'approved') {
        approved++;
      } else if (status == 'rejected') {
        rejected++;
      } else if (status == 'suspended') {
        suspended++;
      } else if (status == 'banned') {
        banned++; // Fixed: banned therapists no longer count as pending
      } else {
        pending++;
      }
    }

    // Count suspended and banned parents
    int suspendedParents = 0;
    int bannedParents = 0;
    for (final doc in parentsSnap.docs) {
      final status = (doc.data()['status'] ?? 'active').toString();
      if (status == 'suspended') {
        suspendedParents++;
      } else if (status == 'banned') {
        bannedParents++;
      }
    }

    final subsSnap = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('status', whereIn: ['active', 'trialing', 'grace_period'])
        .get();

    final reportsSnap = await _firestore.collection('reports').get();
    int pendingReports = 0;
    for (final doc in reportsSnap.docs) {
      if (doc.data()['status'] == 'pending') {
        pendingReports++;
      }
    }
    final feedbackSnap = await _firestore.collection(FirestoreCollections.feedback).get();
    final reviewsSnap = await _firestore.collection('therapist_reviews').get();

    return {
      'totalParents': parentsSnap.docs.length,
      'totalTherapists': therapistsSnap.docs.length,
      'pendingTherapists': pending,
      'approvedTherapists': approved,
      'rejectedTherapists': rejected,
      'suspendedTherapists': suspended,
      'bannedTherapists': banned,
      'suspendedParents': suspendedParents,
      'bannedParents': bannedParents,
      'activeSubscriptions': subsSnap.docs.length,
      'totalReports': reportsSnap.docs.length,
      'pendingReports': pendingReports,
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
    final snap = await _firestore.collection(FirestoreCollections.therapistProfiles).get();
    final all = snap.docs.map((doc) => TherapistProfile.fromMap(doc.id, doc.data())).toList();
    if (status.isEmpty) return all;
    return all.where((t) => t.verificationStatus == status).toList();
  }

  @override
  Future<void> verifyTherapist({
    required String therapistId,
    required String status,
    String adminFeedback = '',
    DateTime? licenseExpiryDate,
    String? verificationImageBase64,
    String? verificationSource,
    String? verificationUrl,
  }) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    final batch = _firestore.batch();
    final profileRef = _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId);

    if (status == 'approved') {
      if (verificationImageBase64 == null || verificationImageBase64.isEmpty ||
          verificationSource == null || verificationSource.isEmpty) {
        throw ArgumentError('Please upload verification evidence and specify the verification source before approving this therapist.');
      }
      final evRef = _firestore.collection('therapist_verification_evidence').doc(therapistId);
      batch.set(evRef, {
        'therapistId': therapistId,
        'imageBase64': verificationImageBase64,
        'source': verificationSource,
        'url': verificationUrl ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'adminUid': adminId,
        'adminEmail': _auth.currentUser?.email ?? '',
      });
    }
    
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
      adminEmail: _auth.currentUser?.email ?? '',
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

    final logRef = _firestore.collection('admin_audit_logs').doc();
    final log = AdminAuditLog(
      id: logRef.id,
      adminUid: adminId,
      adminEmail: _auth.currentUser?.email ?? '',
      targetUid: reportId,
      actionType: 'update_report_status',
      details: 'Report status set to $status',
      timestamp: DateTime.now(),
    );
    await logRef.set({
      ...log.toMap(),
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
      adminEmail: _auth.currentUser?.email ?? '',
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

    // Batch fetch all users for name/email/role resolution
    final usersSnap = await _firestore.collection(FirestoreCollections.users).get();
    final therapistSnap = await _firestore.collection(FirestoreCollections.therapistProfiles).get();
    final Map<String, Map<String, dynamic>> userLookup = {};
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final firstName = (data['firstName'] ?? '').toString();
      final lastName = (data['lastName'] ?? '').toString();
      final fullName = data['fullName']?.toString() ?? '$firstName $lastName'.trim();
      userLookup[doc.id] = {
        'name': fullName.isNotEmpty ? fullName : (data['email'] ?? 'Unknown User'),
        'email': data['email'] ?? '',
        'role': data['role'] ?? 'parent',
      };
    }
    final Map<String, String> therapistNameLookup = {};
    for (final doc in therapistSnap.docs) {
      therapistNameLookup[doc.id] = (doc.data()['displayName'] ?? 'Unknown Therapist').toString();
    }

    final list = <Map<String, dynamic>>[];

    for (final doc in feedbackSnap.docs) {
      final data = doc.data();
      final uid = (data['userId'] ?? '').toString();
      final resolved = userLookup[uid];
      list.add({
        'id': doc.id,
        'type': 'app_feedback',
        'title': 'App Feedback',
        'userId': uid,
        'userName': resolved?['name'] ?? data['name'] ?? data['email'] ?? uid,
        'userEmail': resolved?['email'] ?? data['email'] ?? '',
        'userRole': resolved?['role'] ?? data['role'] ?? 'parent',
        'body': data['body'] ?? data['feedback'] ?? '',
        'isReadByAdmin': data['isReadByAdmin'] ?? false,
        'timestamp': dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      });
    }

    for (final doc in reviewsSnap.docs) {
      final data = doc.data();
      final uid = (data['parentId'] ?? '').toString();
      final therapistId = (data['therapistId'] ?? '').toString();
      final resolved = userLookup[uid];
      list.add({
        'id': doc.id,
        'type': 'therapist_review',
        'title': 'Therapist Review',
        'userId': uid,
        'userName': resolved?['name'] ?? data['parentName'] ?? 'Parent',
        'userEmail': resolved?['email'] ?? '',
        'userRole': 'parent',
        'therapistId': therapistId,
        'therapistName': therapistNameLookup[therapistId] ?? 'Unknown Therapist',
        'body': data['feedback'] ?? '',
        'isReadByAdmin': data['isReadByAdmin'] ?? false,
        'timestamp': dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      });
    }

    list.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
    return list;
  }

  @override
  Future<void> markAllFeedbackAsRead() async {
    try {
      final feedbackSnap = await _firestore.collection(FirestoreCollections.feedback)
          .where('isReadByAdmin', isEqualTo: false).get();
      if (feedbackSnap.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in feedbackSnap.docs) {
          batch.update(doc.reference, {'isReadByAdmin': true});
        }
        await batch.commit();
      }

      final reviewsSnap = await _firestore.collection('therapist_reviews')
          .where('isReadByAdmin', isEqualTo: false).get();
      if (reviewsSnap.docs.isNotEmpty) {
        final batch2 = _firestore.batch();
        for (final doc in reviewsSnap.docs) {
          batch2.update(doc.reference, {'isReadByAdmin': true});
        }
        await batch2.commit();
      }
    } catch (e) {
      debugPrint('markAllFeedbackAsRead: $e');
    }
  }

  @override
  Future<List<AdminAuditLog>> listAuditLogs() async {
    final snap = await _firestore
        .collection('admin_audit_logs')
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs.map((doc) => AdminAuditLog.fromMap(doc.id, doc.data())).toList();
  }

  @override
  Future<void> resolveWithdrawalRequest({
    required String requestId,
    required String status,
    String? adminNotes,
    String? receiptBase64,
  }) async {
    final adminId = _auth.currentUser?.uid;
    if (adminId == null) throw StateError('No logged in admin');

    // 1. Fetch the withdrawal request document
    final reqDoc = await _firestore.collection('withdrawal_requests').doc(requestId).get();
    if (!reqDoc.exists) throw StateError('Withdrawal request not found');
    final reqData = reqDoc.data() ?? {};
    final therapistId = reqData['therapistId']?.toString() ?? '';
    final amount = (reqData['amount'] as num?)?.toDouble() ?? 0.0;

    // 2. Update the withdrawal request in Firestore
    await _firestore.collection('withdrawal_requests').doc(requestId).update({
      'status': status,
      if (adminNotes != null && adminNotes.isNotEmpty) 'adminNotes': adminNotes,
      if (receiptBase64 != null && receiptBase64.isNotEmpty) 'receiptBase64': receiptBase64,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': adminId,
    });

    // Update matching record in therapist_earnings to sync UI status & remove cooldown lock
    try {
      final earningsDoc = await _firestore.collection('therapist_earnings').doc(requestId).get();
      if (earningsDoc.exists) {
        await _firestore.collection('therapist_earnings').doc(requestId).update({
          'status': status,
          if (adminNotes != null && adminNotes.isNotEmpty) 'adminNotes': adminNotes,
          if (receiptBase64 != null && receiptBase64.isNotEmpty) 'receiptBase64': receiptBase64,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Failed to update therapist_earnings status: $e');
    }

    // 3. Update therapist wallet balance based on resolution
    if (therapistId.isNotEmpty) {
      if (status == 'paid') {
        // Mark paid: wallet was already deducted on request creation — just track the payout
        await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).update({
          'totalPaidOut': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (status == 'rejected') {
        // Rejection: reverse the wallet deduction — money goes back to therapist
        await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).update({
          'walletBalance': FieldValue.increment(amount), // restore the amount
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Write a wallet_ledger reversal entry so the therapist sees the credit in their history
        try {
          final ledgerRef = _firestore.collection('wallet_ledger').doc();
          await ledgerRef.set({
            'id': ledgerRef.id,
            'therapistId': therapistId,
            'type': 'withdrawal_reversal',
            'amount': amount,
            'description': 'Withdrawal request rejected — Rs.${amount.toStringAsFixed(0)} returned to wallet. '
                '${adminNotes != null && adminNotes.isNotEmpty ? 'Reason: $adminNotes' : ''}',
            'relatedRequestId': requestId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('resolveWithdrawalRequest: failed to write ledger reversal: $e');
        }
      }
    }

    // 4. Write audit log
    final logRef = _firestore.collection('admin_audit_logs').doc();
    await logRef.set({
      'id': logRef.id,
      'adminUid': adminId,
      'adminEmail': _auth.currentUser?.email ?? '',
      'targetUid': therapistId,
      'actionType': status == 'paid' ? 'withdrawal_paid' : 'withdrawal_rejected',
      'details': 'Request: $requestId, Amount: Rs.$amount, Notes: ${adminNotes ?? ''}',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 5. Notify the therapist if they have payments notifications enabled
    if (therapistId.isNotEmpty) {
      try {
        final therapistDoc = await _firestore.collection(FirestoreCollections.users).doc(therapistId).get();
        final therapistData = therapistDoc.data();
        bool paymentsEnabled = true;
        if (therapistData != null) {
          final prefs = boolMapFrom(therapistData['notificationPreferences'] ?? therapistData['therapistNotificationPreferences']);
          paymentsEnabled = prefs['payments'] ?? true;
        }

        if (paymentsEnabled) {
          if (status == 'paid') {
            await _firestore.collection('notifications').add({
              'userId': therapistId,
              'title': '✅ Withdrawal Paid',
              'message': 'Your withdrawal request of Rs.${amount.toStringAsFixed(0)} has been processed and paid. '
                  '${adminNotes != null && adminNotes.isNotEmpty ? 'Reference: $adminNotes.' : ''}',
              'category': 'wallet',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
              'navigationTarget': {'route': 'TherapistWallet'},
            });
          } else {
            await _firestore.collection('notifications').add({
              'userId': therapistId,
              'title': '❌ Withdrawal Rejected',
              'message': 'Your withdrawal request of Rs.${amount.toStringAsFixed(0)} has been rejected. '
                  '${adminNotes != null && adminNotes.isNotEmpty ? 'Reason: $adminNotes.' : 'Please contact support for details.'}',
              'category': 'wallet',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
              'navigationTarget': {'route': 'TherapistWallet'},
            });
          }
        }
      } catch (e) {
        debugPrint('resolveWithdrawalRequest: failed to notify therapist: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Admin Manual Payout & Secondary Admin Management
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> adminPayoutAndResetWallet({
    required String therapistId,
    required double amount,
    required String transactionReference,
    required String receiptBase64,
    required String adminNote,
  }) async {
    final adminId = _auth.currentUser?.uid ?? '';
    final adminEmail = _auth.currentUser?.email ?? '';

    // 1. Record payout in admin_payout_ledger
    await _firestore.collection('admin_payout_ledger').add({
      'therapistId': therapistId,
      'amount': amount,
      'transactionReference': transactionReference,
      'receiptBase64': receiptBase64,
      'adminNote': adminNote,
      'adminId': adminId,
      'adminEmail': adminEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Reset therapist wallet balance to 0
    await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).update({
      'walletBalance': 0.0,
      'totalPaidOut': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Record audit log
    await _firestore.collection('admin_audit_logs').add({
      'adminUid': adminId,
      'adminEmail': adminEmail,
      'targetUid': therapistId,
      'actionType': 'admin_manual_payout',
      'details': 'Manual payout of Rs.${amount.toStringAsFixed(2)} | Ref: $transactionReference | Note: $adminNote',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 4. Notify therapist
    await _firestore.collection('notifications').add({
      'userId': therapistId,
      'title': '✅ Wallet Payout Processed',
      'message': 'An administrator has manually processed a payout of Rs.${amount.toStringAsFixed(2)} from your wallet. '
          'Transaction Reference: $transactionReference. '
          '${adminNote.isNotEmpty ? 'Note: $adminNote.' : ''} '
          'Your wallet balance has been reset. Please contact support at autieasefyp@gmail.com for any queries.',
      'category': 'wallet',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> createSecondaryAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    // Create via a temporary secondary FirebaseApp instance to avoid signing out the current admin session.
    // This allows creating new accounts directly from the client without requiring a Blaze plan for Cloud Functions.
    FirebaseApp? tempApp;
    try {
      final appName = 'TempSecondaryAdminApp_${DateTime.now().millisecondsSinceEpoch}';
      tempApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final creds = await tempAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      final uid = creds.user?.uid ?? '';
      if (uid.isEmpty) throw StateError('Firebase Auth registration did not return a UID');

      // Write user doc with role: admin using the main Firestore instance
      await _firestore.collection(FirestoreCollections.users).doc(uid).set({
        'uid': uid,
        'email': email.trim(),
        'firstName': name.trim(),
        'lastName': '',
        'fullName': name.trim(),
        'role': 'admin',
        'status': 'active',
        'isPrimaryAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Audit log
      final adminEmail = _auth.currentUser?.email ?? '';
      await _firestore.collection('admin_audit_logs').add({
        'adminUid': _auth.currentUser?.uid ?? '',
        'adminEmail': adminEmail,
        'targetUid': uid,
        'actionType': 'create_secondary_admin',
        'details': 'Created secondary admin account: $name ($email)',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('createSecondaryAdmin client-side failed: $e');
      rethrow;
    } finally {
      if (tempApp != null) {
        try {
          await tempApp.delete();
        } catch (e) {
          debugPrint('Failed to delete temporary secondary app: $e');
        }
      }
    }
  }

  @override
  Future<void> deleteSecondaryAdmin(String adminUid) async {
    final adminEmail = _auth.currentUser?.email ?? '';
    // Deleting the user document will trigger cleanupDeletedUserDocument
    // which calls disableUserAccount and cascades cleanup.
    await _firestore.collection(FirestoreCollections.users).doc(adminUid).delete();

    // Audit log
    await _firestore.collection('admin_audit_logs').add({
      'adminUid': _auth.currentUser?.uid ?? '',
      'adminEmail': adminEmail,
      'targetUid': adminUid,
      'actionType': 'delete_secondary_admin',
      'details': 'Deleted secondary admin account (UID: $adminUid)',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<UserProfile>> listSecondaryAdmins() async {
    final snap = await _firestore
        .collection(FirestoreCollections.users)
        .where('role', isEqualTo: 'admin')
        .where('isPrimaryAdmin', isEqualTo: false)
        .get();
    return snap.docs.map((doc) => UserProfile.fromMap(doc.id, doc.data())).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // New Moderation Action Implementations
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> applyModerationAction({
    required String targetUserId,
    required String targetRole,
    required String action,
    required String reason,
    String? reportId,
    String? restrictedWithUserId,
    int? restrictionDays,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is mandatory for every moderation action.');
    }

    final adminId = _auth.currentUser?.uid ?? '';
    final adminEmail = _auth.currentUser?.email ?? '';

    // ── Resolve real display names ────────────────────────────────────────────
    String targetName = 'the user';
    String otherPartyName = 'the other user';
    try {
      if (targetRole == 'therapist') {
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).get();
        targetName = (tDoc.data()?['displayName'] ?? '').toString();
        if (targetName.isEmpty) targetName = 'the therapist';
        if (restrictedWithUserId != null) {
          final pDoc = await _firestore.collection(FirestoreCollections.users).doc(restrictedWithUserId).get();
          final data = pDoc.data() ?? {};
          otherPartyName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          if (otherPartyName.isEmpty) otherPartyName = 'the parent';
        }
      } else {
        final pDoc = await _firestore.collection(FirestoreCollections.users).doc(targetUserId).get();
        final data = pDoc.data() ?? {};
        targetName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        if (targetName.isEmpty) targetName = 'the parent';
        if (restrictedWithUserId != null) {
          final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(restrictedWithUserId).get();
          otherPartyName = (tDoc.data()?['displayName'] ?? '').toString();
          if (otherPartyName.isEmpty) otherPartyName = 'the therapist';
        }
      }
    } catch (e) {
      debugPrint('applyModerationAction: failed to resolve names: $e');
    }

    // ── Write moderation_history entry ────────────────────────────────────────
    final histRef = _firestore.collection('moderation_history').doc();
    await histRef.set({
      'targetUserId': targetUserId,
      'targetRole': targetRole,
      'action': action,
      'reason': reason,
      'adminId': adminId,
      'adminEmail': adminEmail,
      'timestamp': FieldValue.serverTimestamp(),
      if (reportId != null) 'reportId': reportId,
      if (restrictedWithUserId != null) 'restrictedWithUserId': restrictedWithUserId,
      if (restrictionDays != null) 'restrictionDays': restrictionDays,
    });

    // ── Write audit log ────────────────────────────────────────────────────────
    final logRef = _firestore.collection('admin_audit_logs').doc();
    await logRef.set({
      'id': logRef.id,
      'adminUid': adminId,
      'adminEmail': adminEmail,
      'targetUid': targetUserId,
      'actionType': 'moderation_$action',
      'details': 'Action: $action | Target: $targetName ($targetRole) | Reason: $reason',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // ── Action-specific logic ──────────────────────────────────────────────────
    switch (action) {
      case 'warn':
        await _applyWarn(
          targetUserId: targetUserId,
          targetRole: targetRole,
          targetName: targetName,
          reason: reason,
          reportId: reportId,
        );
        break;

      case 'restrict':
        final days = restrictionDays ?? 4;
        final otherId = restrictedWithUserId;
        if (otherId == null) {
          throw ArgumentError('restrictedWithUserId is required for restrict action.');
        }
        await _applyRestrict(
          targetUserId: targetUserId,
          targetRole: targetRole,
          targetName: targetName,
          otherUserId: otherId,
          otherPartyName: otherPartyName,
          restrictionDays: days,
          reportId: reportId ?? '',
          moderationHistoryId: histRef.id,
          reason: reason,
        );
        break;

      case 'suspend':
        await _applyGlobalAction(
          targetUserId: targetUserId,
          targetRole: targetRole,
          targetName: targetName,
          isPermanent: false,
          reason: reason,
          reportId: reportId,
        );
        break;

      case 'ban':
        await _applyGlobalAction(
          targetUserId: targetUserId,
          targetRole: targetRole,
          targetName: targetName,
          isPermanent: true,
          reason: reason,
          reportId: reportId,
        );
        break;

      case 'no_action':
        // Update report only; no user status changes
        if (reportId != null) {
          await _firestore.collection('reports').doc(reportId).update({
            'status': 'resolved',
            'adminDecision': 'no_action',
            'adminNotes': reason,
            'resolvedAt': FieldValue.serverTimestamp(),
          });
          // Clear thread report flags
          final reportDoc = await _firestore.collection('reports').doc(reportId).get();
          final threadId = reportDoc.data()?['threadId']?.toString();
          if (threadId != null && threadId.isNotEmpty) {
            await _firestore.collection(FirestoreCollections.therapistThreads).doc(threadId).update({
              'status': 'active',
              'reportedByParent': false,
              'reportedByTherapist': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          // Notify reporter only
          final reporterId = reportDoc.data()?['reporterId']?.toString() ?? '';
          await _firestore.collection('notifications').add({
            'userId': reporterId,
            'title': '✅ Report Reviewed — No Action Taken',
            'message': 'Your report against $targetName has been thoroughly reviewed. '
                'After investigation, our team determined that no policy violation occurred. '
                'No action has been taken at this time. Thank you for helping keep the platform safe.',
            'category': 'moderation',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        break;
    }
  }

  Future<void> _applyWarn({
    required String targetUserId,
    required String targetRole,
    required String targetName,
    required String reason,
    String? reportId,
  }) async {
    // Update user's moderationStatus to 'warned' (NOT status — account stays active)
    await _firestore.collection(FirestoreCollections.users).doc(targetUserId).update({
      'moderationStatus': 'warned',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // If therapist, also update therapist profile moderationStatus
    if (targetRole == 'therapist') {
      await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).set({
        'moderationStatus': 'warned',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Resolve report if linked
    String? reporterId;
    String? threadId;
    if (reportId != null) {
      final reportDoc = await _firestore.collection('reports').doc(reportId).get();
      reporterId = reportDoc.data()?['reporterId']?.toString();
      threadId = reportDoc.data()?['threadId']?.toString();
      await _firestore.collection('reports').doc(reportId).update({
        'status': 'resolved',
        'adminDecision': 'warn',
        'adminNotes': reason,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      // Clear thread report flags — communication continues normally
      if (threadId != null && threadId.isNotEmpty) {
        await _firestore.collection(FirestoreCollections.therapistThreads).doc(threadId).update({
          'status': 'active',
          'reportedByParent': false,
          'reportedByTherapist': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Notify target: warning issued
    await _firestore.collection('notifications').add({
      'userId': targetUserId,
      'title': '⚠️ Official Warning Issued',
      'message': 'An official warning has been issued on your account by the platform administrators. '
          'Reason: $reason. '
          'Please review our community guidelines and ensure compliance to avoid further action. '
          'This warning is recorded on your account.',
      'category': 'moderation',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Notify reporter: warning was issued
    if (reporterId != null && reporterId.isNotEmpty) {
      await _firestore.collection('notifications').add({
        'userId': reporterId,
        'title': '📋 Report Update: Warning Issued',
        'message': 'Your report against $targetName has been reviewed. '
            'The administration has issued an official warning to this user. '
            'Thank you for helping maintain a safe platform.',
        'category': 'moderation',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _applyRestrict({
    required String targetUserId,
    required String targetRole,
    required String targetName,
    required String otherUserId,
    required String otherPartyName,
    required int restrictionDays,
    required String reportId,
    required String moderationHistoryId,
    required String reason,
  }) async {
    final now = DateTime.now();
    final endDate = now.add(Duration(days: restrictionDays));

    // Determine parentId and therapistId
    final String parentId = targetRole == 'parent' ? targetUserId : otherUserId;
    final String therapistId = targetRole == 'therapist' ? targetUserId : otherUserId;

    // Create restriction record
    final restrictRef = _firestore.collection('restrictions').doc();
    await restrictRef.set({
      'parentId': parentId,
      'therapistId': therapistId,
      'reportId': reportId,
      'moderationHistoryId': moderationHistoryId,
      'startDate': Timestamp.fromDate(now),
      'endDate': Timestamp.fromDate(endDate),
      'restrictionDays': restrictionDays,
      'status': 'active',
      'appliedByAdminId': _auth.currentUser?.uid ?? '',
    });

    // Flag both users as having active restrictions
    await _firestore.collection(FirestoreCollections.users).doc(parentId).update({
      'hasActiveRestrictions': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (parentId == targetUserId) 'moderationStatus': 'restricted',
    });
    await _firestore.collection(FirestoreCollections.users).doc(therapistId).update({
      'hasActiveRestrictions': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (therapistId == targetUserId) 'moderationStatus': 'restricted',
    });
    // Also update therapist_profiles for hasActiveRestrictions
    await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).set({
      'hasActiveRestrictions': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (therapistId == targetUserId) 'moderationStatus': 'restricted',
    }, SetOptions(merge: true));

    // Resolve the report
    await _firestore.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'adminDecision': 'restrict',
      'adminNotes': reason,
      'restrictionDays': restrictionDays,
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    // IMPORTANT: Do NOT lock the thread, change isActive, or modify isAcceptingClients.
    // The chat screen checks restrictions collection in real-time.
    // Only clear report flags.
    final reportDoc = await _firestore.collection('reports').doc(reportId).get();
    final threadId = reportDoc.data()?['threadId']?.toString();
    if (threadId != null && threadId.isNotEmpty) {
      await _firestore.collection(FirestoreCollections.therapistThreads).doc(threadId).update({
        'status': 'active',
        'reportedByParent': false,
        'reportedByTherapist': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final endDateStr = '${endDate.day}/${endDate.month}/${endDate.year}';

    // Notify the target (restricted party)
    await _firestore.collection('notifications').add({
      'userId': targetUserId,
      'title': '🔒 Communication Temporarily Restricted',
      'message': 'Your communication with $otherPartyName has been temporarily restricted '
          'by the platform administrators for $restrictionDays day(s). '
          'Reason: $reason. '
          'The restriction will automatically expire on $endDateStr. '
          'Your profile visibility and other relationships are not affected.',
      'category': 'moderation',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
      'navigationTarget': {'route': 'Notifications'},
    });

    final isOtherPartyTherapist = targetRole == 'parent';

    // Notify the other party
    await _firestore.collection('notifications').add({
      'userId': otherUserId,
      'title': '🔒 Communication Temporarily Restricted',
      'message': isOtherPartyTherapist
          ? 'Your communication with $targetName has been temporarily restricted '
              'by the platform administrators for $restrictionDays day(s). '
              'Reason: $reason. '
              'The restriction will automatically expire on $endDateStr.'
          : 'Your communication with $targetName has been temporarily restricted '
              'by the platform administrators for $restrictionDays day(s). '
              'Reason: $reason. '
              'The restriction will automatically expire on $endDateStr. '
              'You may choose to continue or cancel your current subscription.',
      'category': 'moderation',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
      if (!isOtherPartyTherapist)
        'navigationTarget': {'route': 'SubscriptionDecisionAfterModeration', 'reportId': reportId},
    });
  }

  Future<void> _applyGlobalAction({
    required String targetUserId,
    required String targetRole,
    required String targetName,
    required bool isPermanent,
    required String reason,
    String? reportId,
  }) async {
    final action = isPermanent ? 'ban' : 'suspend';
    final newStatus = isPermanent ? 'banned' : 'suspended';
    final verifStatus = isPermanent ? 'banned' : 'suspended';

    // 1. Update user doc status
    await _firestore.collection(FirestoreCollections.users).doc(targetUserId).update({
      'status': newStatus,
      'moderationStatus': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. If therapist, update therapist profile + freeze wallet + hide packages + auto-reject withdrawals
    if (targetRole == 'therapist') {
      await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).set({
        'verificationStatus': verifStatus,
        'moderationStatus': newStatus,
        'isActive': false,
        'isAcceptingClients': false,
        'adminFeedback': reason,
        'walletFrozen': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Hide all packages (mark visible: false so parents can't subscribe to them)
      try {
        final therapistProfileDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).get();
        final packages = (therapistProfileDoc.data()?['servicePackages'] as List?)?.map((p) {
          if (p is Map) {
            return {...Map<String, dynamic>.from(p), 'visible': false};
          }
          return p;
        }).toList();
        if (packages != null && packages.isNotEmpty) {
          await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).update({
            'servicePackages': packages,
          });
        }
      } catch (e) {
        debugPrint('_applyGlobalAction: failed to hide packages: $e');
      }

      // Auto-reject pending withdrawal requests
      try {
        final pendingWithdrawals = await _firestore
            .collection('withdrawal_requests')
            .where('therapistId', isEqualTo: targetUserId)
            .where('status', isEqualTo: 'pending')
            .get();
        for (final doc in pendingWithdrawals.docs) {
          await doc.reference.update({
            'status': 'rejected',
            'adminNotes': 'Auto-rejected: account $newStatus. Wallet has been frozen. Contact support at autieasefyp@gmail.com.',
            'resolvedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('_applyGlobalAction: failed to auto-reject withdrawals: $e');
      }
    }

    // 3. Disable Firebase Auth account via Cloud Function (force sign-out all devices)
    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('disableUserAccount').call({'uid': targetUserId});
    } catch (e) {
      debugPrint('applyGlobalAction: Cloud Function disableUserAccount failed: $e');
      // Non-fatal: client-side login guard will still catch it on next login attempt
    }

    // 4. Resolve report if linked
    if (reportId != null) {
      final reportDoc = await _firestore.collection('reports').doc(reportId).get();
      final threadId = reportDoc.data()?['threadId']?.toString();
      await _firestore.collection('reports').doc(reportId).update({
        'status': 'resolved',
        'adminDecision': action,
        'adminNotes': reason,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      if (threadId != null && threadId.isNotEmpty) {
        await _firestore.collection(FirestoreCollections.therapistThreads).doc(threadId).update({
          'status': 'locked',
          'reportedByParent': false,
          'reportedByTherapist': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // 5. Batch cancel all subscriptions & collect affected user IDs for notifications
    final Set<String> affectedUserIds = {};
    await batchCancelSubscriptionsForUser(userId: targetUserId, reason: reason);

    // Cancel pending slot requests
    try {
      final parentRequests = await _firestore
          .collection('slot_requests')
          .where('parentId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();
      final therapistRequests = await _firestore
          .collection('slot_requests')
          .where('therapistId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in [...parentRequests.docs, ...therapistRequests.docs]) {
        await doc.reference.update({
          'status': 'cancelled',
          'declineReason': 'cancelled due to admin moderation: $reason',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('_applyGlobalAction: failed to cancel slot requests: $e');
    }

    // Collect affected other-party IDs for bulk notifications
    if (targetRole == 'therapist') {
      final subsSnap = await _firestore
          .collection(FirestoreCollections.subscriptions)
          .where('therapistId', isEqualTo: targetUserId)
          .get();
      for (final doc in subsSnap.docs) {
        final parentId = doc.data()['userId']?.toString();
        if (parentId != null && parentId.isNotEmpty) {
          affectedUserIds.add(parentId);
        }
      }
    } else {
      final subsSnap = await _firestore
          .collection(FirestoreCollections.subscriptions)
          .where('userId', isEqualTo: targetUserId)
          .get();
      for (final doc in subsSnap.docs) {
        final therapistId = doc.data()['therapistId']?.toString();
        if (therapistId != null && therapistId.isNotEmpty) {
          affectedUserIds.add(therapistId);
        }
      }
    }

    // 6. Batch cancel all future bookings
    await batchCancelBookingsForUser(userId: targetUserId, reason: reason);

    // 7. Notify target user
    final suspendMsg = isPermanent
        ? 'Your account has been permanently banned by the platform administrators '
          'due to a serious violation of platform policies. '
          'Reason: $reason. '
          'You are no longer permitted to access this platform.'
        : 'Your account has been suspended by the administration due to a violation of platform policies. '
          'Reason: $reason. '
          'If you believe this action was taken in error, please contact our Support Team at autieasefyp@gmail.com for further assistance. '
          'All active subscriptions and bookings have been cancelled.';

    await _firestore.collection('notifications').add({
      'userId': targetUserId,
      'title': isPermanent ? '⛔ Account Permanently Banned' : '🔴 Account Suspended',
      'message': suspendMsg,
      'category': 'moderation',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 8. Notify all affected other-party users
    for (final affectedId in affectedUserIds) {
      String affectedMsg;
      if (targetRole == 'therapist') {
        affectedMsg = isPermanent
            ? 'We regret to inform you that $targetName has been permanently removed from the platform '
              'due to a serious policy violation. '
              'Reason: $reason. '
              'Your subscription has been cancelled and no further charges will apply. '
              'We apologize for any inconvenience and encourage you to explore other qualified therapists on AutiEase.'
            : 'We regret to inform you that $targetName has been suspended from the platform '
              'due to a policy violation. '
              'Reason: $reason. '
              'Your subscription has been cancelled. '
              'You may explore and subscribe to another therapist on AutiEase.';
      } else {
        affectedMsg = isPermanent
            ? 'A parent you were working with, $targetName, has been permanently banned from the platform.'
            : 'A parent you were working with, $targetName, has been temporarily suspended from the platform.';
      }

      await _firestore.collection('notifications').add({
        'userId': affectedId,
        'title': isPermanent
            ? '⚠️ Therapist Permanently Removed'
            : '⚠️ Therapist Suspended',
        'message': affectedMsg,
        'category': 'moderation',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'navigationTarget': {'route': 'ProfessionalSupport'},
      });
    }

    // 9. Notify original reporter (if report exists and reporter is identifiable)
    if (reportId != null) {
      try {
        final reportDoc = await _firestore.collection('reports').doc(reportId).get();
        final reporterId = reportDoc.data()?['reporterId']?.toString();
        if (reporterId != null && reporterId.isNotEmpty) {
          await _firestore.collection('notifications').add({
            'userId': reporterId,
            'title': '📋 Report Update: ${isPermanent ? "Ban" : "Suspension"} Applied',
            'message': 'Your report against $targetName has been reviewed and acted upon. '
                'The administration has ${isPermanent ? "permanently banned" : "suspended"} this user. '
                'Thank you for helping maintain a safe platform.',
            'category': 'moderation',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('applyGlobalAction: failed to notify reporter: $e');
      }
    }
  }

  @override
  Future<void> removeModerationAction({
    required String targetUserId,
    required String targetRole,
    required String action,
    required String reason,
    String? restrictionId,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is mandatory for removing a moderation action.');
    }

    final adminId = _auth.currentUser?.uid ?? '';
    final adminEmail = _auth.currentUser?.email ?? '';

    // Resolve target display name
    String targetName = 'the user';
    try {
      if (targetRole == 'therapist') {
        final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).get();
        targetName = (tDoc.data()?['displayName'] ?? '').toString();
        if (targetName.isEmpty) targetName = 'the therapist';
      } else {
        final pDoc = await _firestore.collection(FirestoreCollections.users).doc(targetUserId).get();
        final data = pDoc.data() ?? {};
        targetName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        if (targetName.isEmpty) targetName = 'the parent';
      }
    } catch (_) {}

    // Write history entry for the removal
    final histRef = _firestore.collection('moderation_history').doc();
    await histRef.set({
      'targetUserId': targetUserId,
      'targetRole': targetRole,
      'action': action,
      'reason': reason,
      'adminId': adminId,
      'adminEmail': adminEmail,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Write audit log
    final logRef = _firestore.collection('admin_audit_logs').doc();
    await logRef.set({
      'id': logRef.id,
      'adminUid': adminId,
      'adminEmail': adminEmail,
      'targetUid': targetUserId,
      'actionType': 'moderation_$action',
      'details': 'Removing: $action | Target: $targetName | Reason: $reason',
      'timestamp': FieldValue.serverTimestamp(),
    });

    switch (action) {
      case 'remove_warn':
        await _firestore.collection(FirestoreCollections.users).doc(targetUserId).update({
          'moderationStatus': 'verified',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (targetRole == 'therapist') {
          await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).set({
            'moderationStatus': 'verified',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await _firestore.collection('notifications').add({
          'userId': targetUserId,
          'title': '✅ Warning Removed',
          'message': 'The official warning on your account has been removed by the platform administrators. '
              'Your account status has been restored to Verified. Reason: $reason.',
          'category': 'moderation',
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
        break;

      case 'remove_restrict':
        if (restrictionId != null) {
          final restrictDoc = await _firestore.collection('restrictions').doc(restrictionId).get();
          final parentId = restrictDoc.data()?['parentId']?.toString() ?? '';
          final therapistId = restrictDoc.data()?['therapistId']?.toString() ?? '';

          await _firestore.collection('restrictions').doc(restrictionId).update({
            'status': 'removed',
            'removedByAdminId': adminId,
            'removalReason': reason,
            'removedAt': FieldValue.serverTimestamp(),
          });

          // Check if either user still has other active restrictions
          for (final uid in [parentId, therapistId]) {
            final activeRestricts = await _firestore
                .collection('restrictions')
                .where('status', isEqualTo: 'active')
                .get();
            final now = DateTime.now();
            final userStillRestricted = activeRestricts.docs.any((d) {
              final data = d.data();
              final isTarget = data['parentId'] == uid || data['therapistId'] == uid;
              if (!isTarget) return false;
              final endTs = data['endDate'];
              if (endTs is Timestamp) {
                return endTs.toDate().isAfter(now);
              }
              return false;
            });
            if (!userStillRestricted) {
              await _firestore.collection(FirestoreCollections.users).doc(uid).update({
                'hasActiveRestrictions': false,
                'moderationStatus': 'verified',
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (uid == therapistId) {
                await _firestore.collection(FirestoreCollections.therapistProfiles).doc(uid).set({
                  'hasActiveRestrictions': false,
                  'moderationStatus': 'verified',
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            }
          }

          // Resolve names for customized notifications
          String parentName = 'the parent';
          String therapistName = 'the therapist';
          try {
            final pDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
            final pData = pDoc.data() ?? {};
            parentName = '${pData['firstName'] ?? ''} ${pData['lastName'] ?? ''}'.trim();
            if (parentName.isEmpty) parentName = 'the parent';
          } catch (_) {}
          try {
            final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).get();
            therapistName = (tDoc.data()?['displayName'] ?? '').toString();
            if (therapistName.isEmpty) therapistName = 'the therapist';
          } catch (_) {}

          // Notify Parent
          await _firestore.collection('notifications').add({
            'userId': parentId,
            'title': '✅ Communication Restored',
            'message': 'Your communication with $therapistName has been restored by the platform administrators. '
                'You may now communicate normally. Reason: $reason.',
            'category': 'moderation',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Notify Therapist
          await _firestore.collection('notifications').add({
            'userId': therapistId,
            'title': '✅ Communication Restored',
            'message': 'Your communication with $parentName has been restored by the platform administrators. '
                'You may now communicate normally. Reason: $reason.',
            'category': 'moderation',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        break;

      case 'remove_suspend':
      case 'remove_ban':
      case 'restore':
        // Fetch user data first to see if they were restricted or suspended
        bool wasRestricted = false;
        bool didSendCustomNotification = false;
        try {
          final uDoc = await _firestore.collection(FirestoreCollections.users).doc(targetUserId).get();
          wasRestricted = uDoc.data()?['hasActiveRestrictions'] == true;
        } catch (_) {}

        // 1. Find and remove all active restrictions involving targetUserId
        try {
          final activeRestrictionsQuery = await _firestore
              .collection('restrictions')
              .where('status', isEqualTo: 'active')
              .get();
          
          final targetRestrictions = activeRestrictionsQuery.docs.where((d) {
            final data = d.data();
            return data['parentId'] == targetUserId || data['therapistId'] == targetUserId;
          }).toList();
          for (final doc in targetRestrictions) {
            final data = doc.data();
            final parentId = data['parentId']?.toString() ?? '';
            final therapistId = data['therapistId']?.toString() ?? '';

            await doc.reference.update({
              'status': 'removed',
              'removedByAdminId': adminId,
              'removalReason': reason,
              'removedAt': FieldValue.serverTimestamp(),
            });

            // Resolve names for customized notifications
            String parentName = 'the parent';
            String therapistName = 'the therapist';
            try {
              final pDoc = await _firestore.collection(FirestoreCollections.users).doc(parentId).get();
              final pData = pDoc.data() ?? {};
              parentName = '${pData['firstName'] ?? ''} ${pData['lastName'] ?? ''}'.trim();
              if (parentName.isEmpty) parentName = 'the parent';
            } catch (_) {}
            try {
              final tDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(therapistId).get();
              therapistName = (tDoc.data()?['displayName'] ?? '').toString();
              if (therapistName.isEmpty) therapistName = 'the therapist';
            } catch (_) {}

            // Notify Parent
            await _firestore.collection('notifications').add({
              'userId': parentId,
              'title': '✅ Communication Restored',
              'message': 'Your communication with $therapistName has been restored by the platform administrators. '
                  'You may now communicate normally. Reason: $reason.',
              'category': 'moderation',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
            });

            // Notify Therapist
            await _firestore.collection('notifications').add({
              'userId': therapistId,
              'title': '✅ Communication Restored',
              'message': 'Your communication with $parentName has been restored by the platform administrators. '
                  'You may now communicate normally. Reason: $reason.',
              'category': 'moderation',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
            });

            didSendCustomNotification = true;

            // Re-check and clear hasActiveRestrictions for both users
            for (final uid in [parentId, therapistId]) {
              final activeRestricts = await _firestore
                  .collection('restrictions')
                  .where('status', isEqualTo: 'active')
                  .get();
              final now = DateTime.now();
              final userStillRestricted = activeRestricts.docs.any((d) {
                final rData = d.data();
                final isTarget = rData['parentId'] == uid || rData['therapistId'] == uid;
                if (!isTarget) return false;
                final endTs = rData['endDate'];
                if (endTs is Timestamp) {
                  return endTs.toDate().isAfter(now);
                }
                return false;
              });
              if (!userStillRestricted) {
                await _firestore.collection(FirestoreCollections.users).doc(uid).update({
                  'hasActiveRestrictions': false,
                  'moderationStatus': 'verified',
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (uid == therapistId) {
                  await _firestore.collection(FirestoreCollections.therapistProfiles).doc(uid).set({
                    'hasActiveRestrictions': false,
                    'moderationStatus': 'verified',
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }
              }
            }
          }
        } catch (e) {
          debugPrint('removeModerationAction: failed to clear restrictions: $e');
        }

        // 2. Restore any locked/reported chat threads involving this user to active
        try {
          final parentThreads = await _firestore
              .collection(FirestoreCollections.therapistThreads)
              .where('parentId', isEqualTo: targetUserId)
              .get();
          final therapistThreads = await _firestore
              .collection(FirestoreCollections.therapistThreads)
              .where('therapistId', isEqualTo: targetUserId)
              .get();

          final allThreads = [...parentThreads.docs, ...therapistThreads.docs];
          for (final doc in allThreads) {
            final tStatus = doc.data()['status']?.toString();
            if (tStatus == 'locked' || tStatus == 'reported') {
              await doc.reference.update({
                'status': 'active',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        } catch (e) {
          debugPrint('removeModerationAction: failed to restore thread status: $e');
        }

        // Re-enable the Firebase Auth account
        try {
          final functions = FirebaseFunctions.instance;
          await functions.httpsCallable('enableUserAccount').call({'uid': targetUserId});
        } catch (e) {
          debugPrint('removeModerationAction: Cloud Function enableUserAccount failed: $e');
        }

        // Restore user status to active
        await _firestore.collection(FirestoreCollections.users).doc(targetUserId).update({
          'status': 'active',
          'moderationStatus': 'verified',
          'hasActiveRestrictions': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (targetRole == 'therapist') {
          await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).set({
            'verificationStatus': 'approved',
            'isActive': true,
            'isAcceptingClients': true,
            'moderationStatus': 'verified',
            'hasActiveRestrictions': false,
            'walletFrozen': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // Restore package visibility (set visible: true)
          try {
            final therapistProfileDoc = await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).get();
            final packages = (therapistProfileDoc.data()?['servicePackages'] as List?)?.map((p) {
              if (p is Map) {
                final mp = Map<String, dynamic>.from(p);
                mp.remove('visible'); // remove visible:false to restore default (visible)
                return mp;
              }
              return p;
            }).toList();
            if (packages != null && packages.isNotEmpty) {
              await _firestore.collection(FirestoreCollections.therapistProfiles).doc(targetUserId).update({
                'servicePackages': packages,
              });
            }
          } catch (e) {
            debugPrint('removeModerationAction: failed to restore packages: $e');
          }
        }

        // Notify the user based on whether they were restricted vs suspended/banned
        if (wasRestricted) {
          if (!didSendCustomNotification) {
            await _firestore.collection('notifications').add({
              'userId': targetUserId,
              'title': '✅ Communication Restored',
              'message': 'The restriction on your account has been removed by the platform administrators. '
                  'You may now communicate normally. Reason: $reason.',
              'category': 'moderation',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        } else {
          await _firestore.collection('notifications').add({
            'userId': targetUserId,
            'title': '✅ Account Restored',
            'message': 'Your account has been restored by the platform administrators. '
                'You may now log in and resume using AutiEase. '
                'Note: Previously cancelled subscriptions are not automatically restored. '
                'Reason: $reason.',
            'category': 'moderation',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        break;
    }
  }

  @override
  Future<void> requestAdditionalInfo({
    required String reportId,
    required String requestFrom,
    required String reason,
    required String description,
  }) async {
    final adminId = _auth.currentUser?.uid ?? '';
    final adminEmail = _auth.currentUser?.email ?? '';

    // Fetch report data
    final reportDoc = await _firestore.collection('reports').doc(reportId).get();
    if (!reportDoc.exists) throw StateError('Report $reportId not found');
    final data = reportDoc.data() ?? {};
    final reporterId = data['reporterId']?.toString() ?? '';
    final reportedId = data['reportedId']?.toString() ?? '';

    // Update report status
    await _firestore.collection('reports').doc(reportId).update({
      'status': 'additional_info_requested',
      'additionalInfoRequestedFrom': requestFrom,
      'adminInfoRequestReason': reason,
      'adminInfoRequestDescription': description,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Write moderation history entry
    final histRef = _firestore.collection('moderation_history').doc();
    await histRef.set({
      'targetUserId': reportedId,
      'targetRole': data['reporterRole'] == 'parent' ? 'therapist' : 'parent',
      'action': 'additional_info_requested',
      'reason': reason,
      'adminId': adminId,
      'adminEmail': adminEmail,
      'reportId': reportId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Write audit log
    await _firestore.collection('admin_audit_logs').doc().set({
      'adminUid': adminId,
      'adminEmail': adminEmail,
      'targetUid': reportedId,
      'actionType': 'additional_info_requested',
      'details': 'Report: $reportId | From: $requestFrom | Reason: $reason',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Send notifications to the requested parties
    final notifyIds = <String>[];
    if (requestFrom == 'reporter' || requestFrom == 'both') {
      notifyIds.add(reporterId);
    }
    if (requestFrom == 'reported' || requestFrom == 'both') {
      notifyIds.add(reportedId);
    }

    for (final userId in notifyIds) {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': '📋 Additional Information Requested',
        'message': 'The administration has reviewed your report and requires additional information. '
            'Reason: $reason. '
            'Details needed: $description. '
            'Please submit your information through the "View Report" option. '
            'You will only be able to submit information once, so please be thorough.',
        'category': 'moderation',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'navigationTarget': {
          'route': 'ReportMessage',
          'reportId': reportId,
          'requestedByAdminId': adminId,
        },
      });
    }
  }

  @override
  Future<void> batchCancelSubscriptionsForUser({
    required String userId,
    required String reason,
  }) async {
    // Find all active subscriptions for this user (as subscriber or as therapist)
    final subsAsUser = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['active', 'trialing', 'grace_period'])
        .get();
    final subsAsTherapist = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('therapistId', isEqualTo: userId)
        .where('status', whereIn: ['active', 'trialing', 'grace_period'])
        .get();

    final allSubs = {...subsAsUser.docs, ...subsAsTherapist.docs};
    for (final doc in allSubs) {
      await doc.reference.update({
        'status': 'cancelled',
        'cancelAtPeriodEnd': false,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationReason': 'admin_moderation: $reason',
      });
    }

    // Also lock associated threads
    final threads = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final parentThreads = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('parentId', isEqualTo: userId)
        .get();
    threads.addAll(parentThreads.docs);
    final therapistThreads = await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .where('therapistId', isEqualTo: userId)
        .get();
    threads.addAll(therapistThreads.docs);

    for (final thread in threads) {
      if (thread.data()['status'] != 'locked') {
        await thread.reference.update({
          'status': 'locked',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  @override
  Future<void> batchCancelBookingsForUser({
    required String userId,
    required String reason,
  }) async {
    final now = Timestamp.now();
    // Cancel future bookings where this user is either the therapist or booker
    final asParent = await _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .where('bookedByParentId', isEqualTo: userId)
        .where('status', isEqualTo: 'booked')
        .where('dateTime', isGreaterThan: now)
        .get();
    final asTherapist = await _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .where('therapistId', isEqualTo: userId)
        .where('status', isEqualTo: 'booked')
        .where('dateTime', isGreaterThan: now)
        .get();
    // Also cancel future available slots for the therapist (if the therapist is banned/suspended)
    final availableSlots = await _firestore
        .collection(FirestoreCollections.appointmentSlots)
        .where('therapistId', isEqualTo: userId)
        .where('status', isEqualTo: 'available')
        .where('dateTime', isGreaterThan: now)
        .get();

    for (final slot in [...asParent.docs, ...asTherapist.docs, ...availableSlots.docs]) {
      await slot.reference.update({
        'status': 'cancelled',
        'cancellationReason': 'admin_moderation: $reason',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Future<List<UserProfile>> listParentsByModerationStatus(String badge) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection(FirestoreCollections.users).where('role', isEqualTo: 'parent');

    switch (badge) {
      case 'verified':
        query = query
            .where('status', isEqualTo: 'active')
            .where('moderationStatus', isEqualTo: 'verified')
            .where('hasActiveRestrictions', isEqualTo: false);
        break;
      case 'warned':
        query = query
            .where('status', isEqualTo: 'active')
            .where('moderationStatus', isEqualTo: 'warned')
            .where('hasActiveRestrictions', isEqualTo: false);
        break;
      case 'restricted':
        query = query.where('hasActiveRestrictions', isEqualTo: true);
        break;
      case 'suspended':
        query = query.where('status', isEqualTo: 'suspended');
        break;
      case 'banned':
        query = query.where('status', isEqualTo: 'banned');
        break;
      // 'all' — no additional filter
    }

    final snap = await query.get();
    return snap.docs.map((d) => UserProfile.fromMap(d.id, d.data())).toList();
  }

  @override
  Future<List<TherapistProfile>> listTherapistsByModerationStatus(String badge) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection(FirestoreCollections.therapistProfiles);

    switch (badge) {
      case 'verified':
        query = query
            .where('verificationStatus', isEqualTo: 'approved')
            .where('moderationStatus', isEqualTo: 'verified')
            .where('hasActiveRestrictions', isEqualTo: false);
        break;
      case 'warned':
        query = query
            .where('verificationStatus', isEqualTo: 'approved')
            .where('moderationStatus', isEqualTo: 'warned')
            .where('hasActiveRestrictions', isEqualTo: false);
        break;
      case 'restricted':
        query = query.where('hasActiveRestrictions', isEqualTo: true);
        break;
      case 'suspended':
        query = query.where('verificationStatus', isEqualTo: 'suspended');
        break;
      case 'banned':
        query = query.where('verificationStatus', isEqualTo: 'banned');
        break;
      // 'all' — no additional filter
    }

    final snap = await query.get();
    return snap.docs.map((d) => TherapistProfile.fromMap(d.id, d.data())).toList();
  }
}


