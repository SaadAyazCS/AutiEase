import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_runtime_config.dart';
import '../models/app_models.dart';
import '../services/auth_verification_policy.dart';
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
  Future<void> recordMood({
    required String childId,
    required String emotion,
    String note,
  });
  Future<void> recordActivityCompletion({
    required String childId,
    required String itemId,
    String? moduleId,
    int score,
  });
}

abstract class SupportRepository {
  Future<List<TherapistProfile>> listTherapists();
  Stream<List<TherapistThread>> watchThreadsForRole(String role);
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
  });
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
    await updateCurrentUser({'notificationPreferences': preferences});
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
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class FirebaseContentRepository implements ContentRepository {
  FirebaseContentRepository(this._firestore);

  final FirebaseFirestore _firestore;

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
  }) async {
    await _firestore.collection(FirestoreCollections.activityProgress).add({
      'childId': childId,
      'itemId': itemId,
      'moduleId': moduleId,
      'status': 'completed',
      'score': score,
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
  Future<List<TherapistProfile>> listTherapists() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.therapistProfiles)
        .where('isActive', isEqualTo: true)
        .get();
    final therapists = snapshot.docs
        .map((doc) => TherapistProfile.fromMap(doc.id, doc.data()))
        .toList();
    therapists.sort((a, b) => b.rating.compareTo(a.rating));
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
          'attachments': const <String>[],
          'sentAt': FieldValue.serverTimestamp(),
        });

    await _firestore
        .collection(FirestoreCollections.therapistThreads)
        .doc(threadId)
        .set({
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessagePreview': body.length <= 120
              ? body
              : '${body.substring(0, 117)}...',
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
  }

  @override
  Future<void> reactivateSubscription(String subscriptionId) async {
    if (AppRuntimeConfig.bypassProSupportPaywall) {
      return;
    }
    await _stripeBackend.reactivateSubscription(subscriptionId);
  }
}
