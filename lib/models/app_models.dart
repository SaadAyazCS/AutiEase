import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/duration_utils.dart';
import '../utils/currency_utils.dart';

DateTime? dateTimeFromFirestore(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<String> stringListFrom(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}

Map<String, dynamic> mapFrom(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

Map<String, bool> boolMapFrom(dynamic value) {
  final raw = mapFrom(value);
  return raw.map(
    (key, item) => MapEntry(
      key,
      item is bool ? item : item.toString().toLowerCase() == 'true',
    ),
  );
}

int intFrom(dynamic value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

enum AppSessionState {
  unauthenticated,
  incompleteProfile,
  emailVerificationPending,
  parent,
  therapist,
  admin,
}

class AppSession {
  const AppSession({
    required this.state,
    this.uid,
    this.role,
    this.activeChildId,
  });

  final AppSessionState state;
  final String? uid;
  final String? role;
  final String? activeChildId;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.status,
    required this.phone,
    required this.photoUrl,
    required this.subscriptionTier,
    required this.entitlements,
    required this.notificationPreferences,
    this.playSettings = const {},
    this.activeChildId,
    this.createdAt,
    this.updatedAt,
    this.isChildModeLocked = false,
    this.childModePin = '',
    this.lastActiveAt,
    // Moderation fields
    this.moderationStatus = 'verified',
    this.hasActiveRestrictions = false,
  });

  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  /// Account lifecycle status: 'active', 'suspended', 'banned'.
  /// Used for login blocking. Changed only by Suspend/Ban global actions.
  final String status;
  final String phone;
  final String photoUrl;
  final String subscriptionTier;
  final Map<String, bool> entitlements;
  final Map<String, bool> notificationPreferences;
  final Map<String, dynamic> playSettings;
  final String? activeChildId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isChildModeLocked;
  final String childModePin;
  final DateTime? lastActiveAt;
  /// Admin moderation label: 'verified', 'warned'.
  /// Does not include 'restricted' (stored per-relationship in restrictions collection).
  /// Does not include 'suspended'/'banned' (those are tracked via [status]).
  final String moderationStatus;
  /// True when this user has at least one active entry in the restrictions collection.
  /// Used for fast tab filtering in admin panel without extra queries.
  final bool hasActiveRestrictions;

  String get fullName => '$firstName $lastName'.trim();

  /// Convenience getter for the effective display badge in admin UI.
  /// Priority: banned > suspended > restricted > warned > verified.
  String get effectiveModerationBadge {
    if (status == 'banned') return 'banned';
    if (status == 'suspended') return 'suspended';
    if (hasActiveRestrictions) return 'restricted';
    if (moderationStatus == 'warned') return 'warned';
    return 'verified';
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      email: (data['email'] ?? '').toString(),
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      role: (data['role'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      phone: (data['phone'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      subscriptionTier: (data['subscriptionTier'] ?? 'free').toString(),
      entitlements: boolMapFrom(data['entitlements']),
      notificationPreferences: boolMapFrom(data['notificationPreferences']),
      playSettings: mapFrom(data['playSettings']),
      activeChildId: data['activeChildId']?.toString(),
      createdAt: dateTimeFromFirestore(data['createdAt']),
      updatedAt: dateTimeFromFirestore(data['updatedAt']),
      isChildModeLocked: data['isChildModeLocked'] == true,
      childModePin: (data['childModePin'] ?? '').toString(),
      lastActiveAt: dateTimeFromFirestore(data['lastActiveAt']),
      moderationStatus: (data['moderationStatus'] ?? 'verified').toString(),
      hasActiveRestrictions: data['hasActiveRestrictions'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'uid': uid,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'role': role,
      'status': status,
      'phone': phone,
      'photoUrl': photoUrl,
      'subscriptionTier': subscriptionTier,
      'entitlements': entitlements,
      'notificationPreferences': notificationPreferences,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'moderationStatus': moderationStatus,
      'hasActiveRestrictions': hasActiveRestrictions,
    };
    if (role == 'parent') {
      map['playSettings'] = playSettings;
      map['activeChildId'] = activeChildId;
      map['isChildModeLocked'] = isChildModeLocked;
      map['childModePin'] = childModePin;
    }
    return map;
  }
}

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.avatar,
    required this.supportAreas,
    required this.status,
    this.activePlanId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String parentId;
  final String name;
  final String avatar;
  final List<String> supportAreas;
  final String status;
  final String? activePlanId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ChildProfile.fromMap(String id, Map<String, dynamic> data) {
    return ChildProfile(
      id: id,
      parentId: (data['parentId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      avatar: (data['avatar'] ?? '').toString(),
      supportAreas: stringListFrom(data['supportAreas']),
      status: (data['status'] ?? 'active').toString(),
      activePlanId: data['activePlanId']?.toString(),
      createdAt: dateTimeFromFirestore(data['createdAt']),
      updatedAt: dateTimeFromFirestore(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'name': name,
      'avatar': avatar,
      'supportAreas': supportAreas,
      'status': status,
      'activePlanId': activePlanId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class AppModule {
  const AppModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.routeKey,
    required this.targetRole,
    required this.sortOrder,
    required this.isActive,
    this.imageAsset = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String routeKey;
  final String targetRole;
  final int sortOrder;
  final bool isActive;
  final String imageAsset;

  factory AppModule.fromMap(String id, Map<String, dynamic> data) {
    return AppModule(
      id: id,
      title: (data['title'] ?? '').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      routeKey: (data['routeKey'] ?? id).toString(),
      targetRole: (data['targetRole'] ?? '').toString(),
      sortOrder: intFrom(data['sortOrder']),
      isActive: data['isActive'] != false,
      imageAsset: (data['imageAsset'] ?? '').toString(),
    );
  }
}

class ProfessionalSupportFeatureFlags {
  const ProfessionalSupportFeatureFlags({
    required this.chatEnabled,
    required this.paymentsEnabled,
  });

  final bool chatEnabled;
  final bool paymentsEnabled;

  static const enabled = ProfessionalSupportFeatureFlags(
    chatEnabled: true,
    paymentsEnabled: true,
  );

  factory ProfessionalSupportFeatureFlags.fromAppModuleMap(
    Map<String, dynamic> data,
  ) {
    return ProfessionalSupportFeatureFlags(
      chatEnabled: data['chatEnabled'] != false,
      paymentsEnabled: data['paymentsEnabled'] != false,
    );
  }
}

class ContentCategory {
  const ContentCategory({
    required this.id,
    required this.type,
    required this.title,
    required this.icon,
    required this.imageUrl,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String type;
  final String title;
  final String icon;
  final String imageUrl;
  final int sortOrder;
  final bool isActive;

  factory ContentCategory.fromMap(String id, Map<String, dynamic> data) {
    return ContentCategory(
      id: id,
      type: (data['type'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      icon: (data['icon'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      sortOrder: intFrom(data['sortOrder']),
      isActive: data['isActive'] != false,
    );
  }
}

class ContentItem {
  const ContentItem({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.audioText,
    required this.level,
    required this.tags,
    required this.isActive,
  });

  final String id;
  final String categoryId;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String audioText;
  final int level;
  final List<String> tags;
  final bool isActive;

  factory ContentItem.fromMap(String id, Map<String, dynamic> data) {
    return ContentItem(
      id: id,
      categoryId: (data['categoryId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      audioText: (data['audioText'] ?? '').toString(),
      level: intFrom(data['level'], 1),
      tags: stringListFrom(data['tags']),
      isActive: data['isActive'] != false,
    );
  }
}

class LearningModuleModel {
  const LearningModuleModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.learningCategoryKey,
    required this.learningCategoryTitle,
    required this.gameTypeKey,
    required this.levelRange,
    required this.assetRefs,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String title;
  final String description;
  final String type;
  final String learningCategoryKey;
  final String learningCategoryTitle;
  final String gameTypeKey;
  final String levelRange;
  final List<String> assetRefs;
  final int sortOrder;
  final bool isActive;

  factory LearningModuleModel.fromMap(String id, Map<String, dynamic> data) {
    return LearningModuleModel(
      id: id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      type: (data['type'] ?? '').toString(),
      learningCategoryKey: (data['learningCategoryKey'] ?? 'general')
          .toString()
          .trim(),
      learningCategoryTitle: (data['learningCategoryTitle'] ?? 'General')
          .toString()
          .trim(),
      gameTypeKey: (data['gameTypeKey'] ?? id).toString().trim(),
      levelRange: (data['levelRange'] ?? '').toString(),
      assetRefs: stringListFrom(data['assetRefs']),
      sortOrder: intFrom(data['sortOrder']),
      isActive: data['isActive'] != false,
    );
  }
}

class DailyActivityTemplate {
  const DailyActivityTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.moduleRefs,
    required this.estimatedMinutes,
    required this.difficulty,
    required this.isActive,
  });

  final String id;
  final String title;
  final String description;
  final List<String> moduleRefs;
  final int estimatedMinutes;
  final String difficulty;
  final bool isActive;

  factory DailyActivityTemplate.fromMap(String id, Map<String, dynamic> data) {
    return DailyActivityTemplate(
      id: id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      moduleRefs: stringListFrom(data['moduleRefs']),
      estimatedMinutes: intFrom(data['estimatedMinutes']),
      difficulty: (data['difficulty'] ?? 'easy').toString(),
      isActive: data['isActive'] != false,
    );
  }
}

class CustomDailyActivity {
  const CustomDailyActivity({
    required this.id,
    required this.title,
    required this.durationMinutes,
    this.createdAt,
  });

  final String id;
  final String title;
  final int durationMinutes;
  final DateTime? createdAt;

  factory CustomDailyActivity.fromMap(Map<String, dynamic> data) {
    final storedDuration = intFrom(data['durationMinutes']);
    final parsedLegacyDuration = parseDurationLabelToMinutes(
      (data['timeLabel'] ?? '').toString(),
    );
    final resolvedDuration = storedDuration > 0
        ? storedDuration
        : normalizeDurationMinutes(parsedLegacyDuration);

    return CustomDailyActivity(
      id: (data['id'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      durationMinutes: resolvedDuration,
      createdAt: dateTimeFromFirestore(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'durationMinutes': normalizeDurationMinutes(durationMinutes),
      // Keep legacy field for backward compatibility with older builds.
      'timeLabel': formatDurationLabel(durationMinutes),
      'createdAt': createdAt,
    };
  }
}

class ChildAssignment {
  const ChildAssignment({
    required this.id,
    required this.childId,
    required this.parentId,
    required this.assignedCategoryIds,
    required this.assignedModuleIds,
    required this.assignedActivityTemplateIds,
    required this.status,
    this.customDailyActivities = const <CustomDailyActivity>[],
    this.effectiveFrom,
  });

  final String id;
  final String childId;
  final String parentId;
  final List<String> assignedCategoryIds;
  final List<String> assignedModuleIds;
  final List<String> assignedActivityTemplateIds;
  final String status;
  final List<CustomDailyActivity> customDailyActivities;
  final DateTime? effectiveFrom;

  factory ChildAssignment.fromMap(String id, Map<String, dynamic> data) {
    return ChildAssignment(
      id: id,
      childId: (data['childId'] ?? '').toString(),
      parentId: (data['parentId'] ?? '').toString(),
      assignedCategoryIds: stringListFrom(data['assignedCategoryIds']),
      assignedModuleIds: stringListFrom(data['assignedModuleIds']),
      assignedActivityTemplateIds: stringListFrom(
        data['assignedActivityTemplateIds'],
      ),
      status: (data['status'] ?? 'draft').toString(),
      customDailyActivities: (data['customDailyActivities'] is List)
          ? (data['customDailyActivities'] as List)
                .map((item) => CustomDailyActivity.fromMap(mapFrom(item)))
                .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
                .toList()
          : const <CustomDailyActivity>[],
      effectiveFrom: dateTimeFromFirestore(data['effectiveFrom']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'parentId': parentId,
      'assignedCategoryIds': assignedCategoryIds,
      'assignedModuleIds': assignedModuleIds,
      'assignedActivityTemplateIds': assignedActivityTemplateIds,
      'status': status,
      'customDailyActivities': customDailyActivities
          .map((item) => item.toMap())
          .toList(),
      'effectiveFrom': effectiveFrom,
    };
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.childId,
    required this.completedTasks,
    required this.weeklyMinutes,
    required this.streakDays,
    required this.moodEntries,
    required this.lastUpdated,
  });

  final String childId;
  final int completedTasks;
  final int weeklyMinutes;
  final int streakDays;
  final int moodEntries;
  final DateTime? lastUpdated;

  factory DashboardSnapshot.fromMap(String childId, Map<String, dynamic> data) {
    return DashboardSnapshot(
      childId: childId,
      completedTasks: intFrom(data['completedTasks']),
      weeklyMinutes: intFrom(data['weeklyMinutes']),
      streakDays: intFrom(data['streakDays']),
      moodEntries: intFrom(data['moodEntries']),
      lastUpdated: dateTimeFromFirestore(data['lastUpdated']),
    );
  }
}

class ActivityProgressEntry {
  const ActivityProgressEntry({
    required this.id,
    required this.childId,
    required this.itemId,
    required this.moduleId,
    required this.status,
    required this.score,
    required this.attempts,
    this.completedAt,
  });

  final String id;
  final String childId;
  final String itemId;
  final String? moduleId;
  final String status;
  final int score;
  final int attempts;
  final DateTime? completedAt;

  factory ActivityProgressEntry.fromMap(String id, Map<String, dynamic> data) {
    return ActivityProgressEntry(
      id: id,
      childId: (data['childId'] ?? '').toString(),
      itemId: (data['itemId'] ?? '').toString(),
      moduleId: data['moduleId']?.toString(),
      status: (data['status'] ?? 'completed').toString(),
      score: intFrom(data['score']),
      attempts: intFrom(data['attempts'], 1),
      completedAt: dateTimeFromFirestore(data['completedAt']),
    );
  }
}

class MoodLogEntry {
  const MoodLogEntry({
    required this.id,
    required this.childId,
    required this.emotion,
    required this.note,
    this.createdAt,
  });

  final String id;
  final String childId;
  final String emotion;
  final String note;
  final DateTime? createdAt;

  factory MoodLogEntry.fromMap(String id, Map<String, dynamic> data) {
    return MoodLogEntry(
      id: id,
      childId: (data['childId'] ?? '').toString(),
      emotion: (data['emotion'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      createdAt: dateTimeFromFirestore(data['createdAt']),
    );
  }
}

class DashboardReportSection {
  const DashboardReportSection({
    required this.title,
    required this.progressValue,
    required this.body,
    required this.statusLabel,
  });

  final String title;
  final double progressValue;
  final String body;
  final String statusLabel;
}

class DashboardReport {
  const DashboardReport({
    required this.title,
    required this.dateLabel,
    required this.summarySubtitle,
    required this.summaryText,
    required this.sections,
    required this.recommendations,
  });

  final String title;
  final String dateLabel;
  final String summarySubtitle;
  final String summaryText;
  final List<DashboardReportSection> sections;
  final List<String> recommendations;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.childId,
    required this.completedActivities,
    required this.weeklyMinutes,
    required this.monthlyCompletedActivities,
    required this.monthlyMinutes,
    required this.activityLevel,
    required this.moodLabel,
    required this.movePlayProgress,
    required this.talkExpressProgress,
    required this.focusGamesProgress,
    required this.weeklyReport,
    required this.monthlyReport,
    required this.generatedAt,
    this.streakDays = 0,
    this.dailyActivitiesToday = 0,
    this.dailyActivitiesTotal = 0,
    this.communicationTapsThisWeek = 0,
  });

  final String childId;
  final int completedActivities;
  final int weeklyMinutes;
  final int monthlyCompletedActivities;
  final int monthlyMinutes;
  final String activityLevel;
  final String moodLabel;
  final double movePlayProgress;
  final double talkExpressProgress;
  final double focusGamesProgress;
  final DashboardReport weeklyReport;
  final DashboardReport monthlyReport;
  final DateTime generatedAt;

  /// Number of consecutive days (ending today) that had at least one completed activity.
  final int streakDays;

  /// Number of daily activities completed today.
  final int dailyActivitiesToday;

  /// Total number of daily activities assigned (template + custom).
  final int dailyActivitiesTotal;

  /// Number of distinct communication vocabulary items spoken this week.
  final int communicationTapsThisWeek;

  factory DashboardMetrics.empty(String childId) {
    const emptySections = <DashboardReportSection>[
      DashboardReportSection(
        title: 'Move & Play',
        progressValue: 0,
        body: 'No tracked activity yet.',
        statusLabel: 'No Data',
      ),
      DashboardReportSection(
        title: 'Talk & Express',
        progressValue: 0,
        body: 'No tracked activity yet.',
        statusLabel: 'No Data',
      ),
      DashboardReportSection(
        title: 'Focus Games',
        progressValue: 0,
        body: 'No tracked activity yet.',
        statusLabel: 'No Data',
      ),
    ];
    return DashboardMetrics(
      childId: childId,
      completedActivities: 0,
      weeklyMinutes: 0,
      monthlyCompletedActivities: 0,
      monthlyMinutes: 0,
      activityLevel: 'Low',
      moodLabel: 'Not set',
      movePlayProgress: 0,
      talkExpressProgress: 0,
      focusGamesProgress: 0,
      streakDays: 0,
      dailyActivitiesToday: 0,
      dailyActivitiesTotal: 0,
      communicationTapsThisWeek: 0,
      weeklyReport: const DashboardReport(
        title: 'Weekly Progress Report',
        dateLabel: '',
        summarySubtitle: 'Progress',
        summaryText: 'No activity has been tracked this week yet.',
        sections: emptySections,
        recommendations: <String>[
          'Start with one short learning session today.',
          'Use Learning Planner to assign activities.',
        ],
      ),
      monthlyReport: const DashboardReport(
        title: 'Monthly Assessment',
        dateLabel: '',
        summarySubtitle: 'Assessment',
        summaryText: 'No activity has been tracked this month yet.',
        sections: emptySections,
        recommendations: <String>[
          'Assign modules and daily activities in Learning Planner.',
          'Track a few sessions to unlock monthly insights.',
        ],
      ),
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class TherapyPackage {
  const TherapyPackage({
    required this.title,
    required this.durationMinutes,
    required this.sessionsPerWeek,
    required this.price,
    required this.description,
    this.visible = true,
  });

  final String title;
  final int durationMinutes;
  final int sessionsPerWeek;
  final double price;
  final String description;
  final bool visible;

  TherapyPackage copy({
    String? title,
    int? durationMinutes,
    int? sessionsPerWeek,
    double? price,
    String? description,
    bool? visible,
  }) {
    return TherapyPackage(
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      sessionsPerWeek: sessionsPerWeek ?? this.sessionsPerWeek,
      price: price ?? this.price,
      description: description ?? this.description,
      visible: visible ?? this.visible,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'durationMinutes': durationMinutes,
    'sessionsPerWeek': sessionsPerWeek,
    'price': price,
    'description': description,
    'visible': visible,
  };

  factory TherapyPackage.fromMap(Map<String, dynamic> map) => TherapyPackage(
    title: map['title']?.toString() ?? '',
    durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
    sessionsPerWeek: (map['sessionsPerWeek'] as num?)?.toInt() ?? 0,
    price: (map['price'] as num?)?.toDouble() ?? 0.0,
    description: map['description']?.toString() ?? '',
    visible: map['visible'] as bool? ?? true,
  );
}

class TherapistProfile {
  const TherapistProfile({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.specializations,
    required this.pricing,
    required this.languages,
    required this.rating,
    required this.availability,
    required this.photoUrl,
    required this.isActive,
    this.yearsOfExperience = 0,
    this.experienceMonths = 0,
    this.credentials = '',
    this.photoUrlBase64 = '',
    this.certificateBase64 = '',
    this.verificationStatus = 'pending',
    this.adminFeedback = '',
    this.verifiedBadge = false,
    this.licenseNumber = '',
    this.registrationNumber = '',
    this.cnic = '',
    this.experienceDetails = '',
    this.ratingBreakdown = const <String, int>{'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
    this.totalReviews = 0,
    this.servicePackages = const <TherapyPackage>[],
    this.isAcceptingClients = true,
    this.lastActiveAt,
    this.hasUnacknowledgedChanges = false,
    this.unacknowledgedChangesFields = const <String>[],
    @Deprecated('Use restrictions collection for per-relationship restrictions')
    this.restrictionUntil,
    // Moderation fields
    this.moderationStatus = 'verified',
    this.hasActiveRestrictions = false,
  });

  final String id;
  final String displayName;
  final String bio;
  final List<String> specializations;
  final String pricing;
  final List<String> languages;
  final double rating;
  final String availability;
  final String photoUrl;
  final bool isActive;
  /// Total whole years of experience. Also serves as the legacy field alias.
  final int yearsOfExperience;
  /// Additional months of experience (0-11).
  final int experienceMonths;
  final String credentials;
  final String photoUrlBase64;
  final String certificateBase64;
  final String verificationStatus;
  final String adminFeedback;
  final bool verifiedBadge;
  final String licenseNumber;
  final String registrationNumber;
  final String cnic;
  final String experienceDetails;
  final Map<String, int> ratingBreakdown;
  final int totalReviews;
  final List<TherapyPackage> servicePackages;
  final bool isAcceptingClients;
  final DateTime? lastActiveAt;
  final bool hasUnacknowledgedChanges;
  final List<String> unacknowledgedChangesFields;
  /// Deprecated: per-relationship restrictions are now in the `restrictions` Firestore collection.
  @Deprecated('Use restrictions collection for per-relationship restrictions')
  final DateTime? restrictionUntil;
  /// Admin moderation label: 'verified', 'warned'.
  /// Does not include 'restricted' (stored per-relationship in restrictions collection).
  /// Does not include 'suspended'/'banned' (those are tracked via verificationStatus).
  final String moderationStatus;
  /// True when this therapist has at least one active entry in the restrictions collection.
  final bool hasActiveRestrictions;

  /// Convenience getter for the effective display badge in admin UI.
  /// Priority: banned > suspended > restricted > warned > verified.
  String get effectiveModerationBadge {
    if (verificationStatus == 'banned') return 'banned';
    if (verificationStatus == 'suspended') return 'suspended';
    if (hasActiveRestrictions) return 'restricted';
    if (moderationStatus == 'warned') return 'warned';
    return 'verified';
  }

  /// Convenience alias for yearsOfExperience.
  int get experienceYears => yearsOfExperience;

  TherapistProfile copyWith({
    String? displayName,
    String? bio,
    List<String>? specializations,
    String? pricing,
    List<String>? languages,
    double? rating,
    String? availability,
    String? photoUrl,
    bool? isActive,
    int? yearsOfExperience,
    int? experienceMonths,
    String? credentials,
    String? photoUrlBase64,
    String? certificateBase64,
    String? verificationStatus,
    String? adminFeedback,
    bool? verifiedBadge,
    String? licenseNumber,
    String? registrationNumber,
    String? cnic,
    String? experienceDetails,
    Map<String, int>? ratingBreakdown,
    int? totalReviews,
    List<TherapyPackage>? servicePackages,
    bool? isAcceptingClients,
    DateTime? lastActiveAt,
    bool? hasUnacknowledgedChanges,
    List<String>? unacknowledgedChangesFields,
    DateTime? restrictionUntil,
    String? moderationStatus,
    bool? hasActiveRestrictions,
  }) {
    return TherapistProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      specializations: specializations ?? this.specializations,
      pricing: pricing ?? this.pricing,
      languages: languages ?? this.languages,
      rating: rating ?? this.rating,
      availability: availability ?? this.availability,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
      experienceMonths: experienceMonths ?? this.experienceMonths,
      credentials: credentials ?? this.credentials,
      photoUrlBase64: photoUrlBase64 ?? this.photoUrlBase64,
      certificateBase64: certificateBase64 ?? this.certificateBase64,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      adminFeedback: adminFeedback ?? this.adminFeedback,
      verifiedBadge: verifiedBadge ?? this.verifiedBadge,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      cnic: cnic ?? this.cnic,
      experienceDetails: experienceDetails ?? this.experienceDetails,
      ratingBreakdown: ratingBreakdown ?? this.ratingBreakdown,
      totalReviews: totalReviews ?? this.totalReviews,
      servicePackages: servicePackages ?? this.servicePackages,
      isAcceptingClients: isAcceptingClients ?? this.isAcceptingClients,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      hasUnacknowledgedChanges: hasUnacknowledgedChanges ?? this.hasUnacknowledgedChanges,
      unacknowledgedChangesFields: unacknowledgedChangesFields ?? this.unacknowledgedChangesFields,
      // ignore: deprecated_member_use_from_same_package
      restrictionUntil: restrictionUntil ?? this.restrictionUntil,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      hasActiveRestrictions: hasActiveRestrictions ?? this.hasActiveRestrictions,
    );
  }

  /// Human-readable experience string:
  ///   5 years, 0 months  → "5 Years"
  ///   5 years, 1 month   → "5.1 Years (approx)"
  String get formattedExperience {
    if (yearsOfExperience == 0 && experienceMonths == 0) return 'Not set';
    if (experienceMonths == 0) return '$yearsOfExperience Years';
    return '$yearsOfExperience.$experienceMonths Years (approx)';
  }

  factory TherapistProfile.fromMap(String id, Map<String, dynamic> data) {
    final rawRating = data['rating'];
    final rawBreakdown = data['ratingBreakdown'];
    Map<String, int> resolvedBreakdown = const <String, int>{'1': 0, '2': 0, '3': 0, '4': 0, '5': 0};
    if (rawBreakdown is Map) {
      resolvedBreakdown = rawBreakdown.map((key, value) => MapEntry(key.toString(), intFrom(value)));
    }
    return TherapistProfile(
      id: id,
      displayName: (data['displayName'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      specializations: stringListFrom(data['specializations']),
      pricing: (data['pricing'] ?? '').toString(),
      languages: stringListFrom(data['languages']),
      rating: rawRating is num ? rawRating.toDouble() : 0,
      availability: (data['availability'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      isActive: data['isActive'] != false,
      yearsOfExperience: intFrom(
        data['experience_years'] ?? data['yearsOfExperience'],
      ),
      experienceMonths: intFrom(data['experience_months']),
      credentials: (data['credentials'] ?? '').toString(),
      photoUrlBase64: (data['photoUrlBase64'] ?? '').toString(),
      certificateBase64: (data['certificateBase64'] ?? '').toString(),
      verificationStatus: (data['verificationStatus'] ?? 'pending').toString(),
      adminFeedback: (data['adminFeedback'] ?? '').toString(),
      verifiedBadge: data['verifiedBadge'] == true,
      licenseNumber: (data['licenseNumber'] ?? '').toString(),
      registrationNumber: (data['registrationNumber'] ?? '').toString(),
      cnic: (data['cnic'] ?? '').toString(),
      experienceDetails: (data['experienceDetails'] ?? '').toString(),
      ratingBreakdown: resolvedBreakdown,
      totalReviews: intFrom(data['totalReviews'], 0),
      servicePackages: (data['servicePackages'] is List)
          ? (data['servicePackages'] as List)
              .map((item) => TherapyPackage.fromMap(mapFrom(item)))
              .toList()
          : const <TherapyPackage>[],
      isAcceptingClients: data['isAcceptingClients'] != false,
      lastActiveAt: dateTimeFromFirestore(data['lastActiveAt']),
      hasUnacknowledgedChanges: data['hasUnacknowledgedChanges'] == true,
      unacknowledgedChangesFields: stringListFrom(data['unacknowledgedChangesFields']),
      // ignore: deprecated_member_use_from_same_package
      restrictionUntil: dateTimeFromFirestore(data['restrictionUntil']),
      moderationStatus: (data['moderationStatus'] ?? 'verified').toString(),
      hasActiveRestrictions: data['hasActiveRestrictions'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'bio': bio,
      'specializations': specializations,
      'pricing': pricing,
      'languages': languages,
      'rating': rating,
      'availability': availability,
      'photoUrl': photoUrl,
      'isActive': isActive,
      'experience_years': yearsOfExperience,
      'experience_months': experienceMonths,
      'credentials': credentials,
      'photoUrlBase64': photoUrlBase64,
      'certificateBase64': certificateBase64,
      'verificationStatus': verificationStatus,
      'adminFeedback': adminFeedback,
      'verifiedBadge': verifiedBadge,
      'licenseNumber': licenseNumber,
      'registrationNumber': registrationNumber,
      'cnic': cnic,
      'experienceDetails': experienceDetails,
      'ratingBreakdown': ratingBreakdown,
      'totalReviews': totalReviews,
      'servicePackages': servicePackages.map((item) => item.toMap()).toList(),
      'isAcceptingClients': isAcceptingClients,
      'lastActiveAt': lastActiveAt,
      'hasUnacknowledgedChanges': hasUnacknowledgedChanges,
      'unacknowledgedChangesFields': unacknowledgedChangesFields,
      'moderationStatus': moderationStatus,
      'hasActiveRestrictions': hasActiveRestrictions,
    };
  }
}

class TherapistReview {
  const TherapistReview({
    required this.id,
    required this.parentId,
    required this.parentName,
    required this.therapistId,
    required this.rating,
    required this.feedback,
    required this.createdAt,
    this.privateFeedback = '',
    this.lowRatingReasons = const <String>[],
  });

  final String id;
  final String parentId;
  final String parentName;
  final String therapistId;
  final int rating;
  final String feedback;
  final DateTime createdAt;
  final String privateFeedback;
  final List<String> lowRatingReasons;

  factory TherapistReview.fromMap(String id, Map<String, dynamic> data) {
    return TherapistReview(
      id: id,
      parentId: (data['parentId'] ?? '').toString(),
      parentName: (data['parentName'] ?? '').toString(),
      therapistId: (data['therapistId'] ?? '').toString(),
      rating: intFrom(data['rating'], 5),
      feedback: (data['feedback'] ?? '').toString(),
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      privateFeedback: (data['privateFeedback'] ?? '').toString(),
      lowRatingReasons: (data['lowRatingReasons'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'parentName': parentName,
      'therapistId': therapistId,
      'rating': rating,
      'feedback': feedback,
      'createdAt': createdAt,
      'privateFeedback': privateFeedback,
      'lowRatingReasons': lowRatingReasons,
    };
  }
}

class UserReport {
  const UserReport({
    required this.id,
    required this.reporterId,
    required this.reporterRole,
    required this.reportedId,
    required this.reason,
    required this.comments,
    required this.chatContext,
    required this.timestamp,
    required this.status,
    this.threadId,
    this.subscriptionStatus = 'none',
    this.parentAction = 'none',
    this.adminDecision,
    this.adminNotes,
    this.resolvedAt,
    // Additional information request fields
    this.additionalInfoRequestedFrom,
    this.adminInfoRequestReason,
    this.adminInfoRequestDescription,
    // Restriction configuration
    this.restrictionDays,
  });

  final String id;
  final String reporterId;
  final String reporterRole;
  final String reportedId;
  final String reason;
  final String comments;
  final List<Map<String, dynamic>> chatContext;
  final DateTime timestamp;
  /// Report lifecycle status.
  /// Values: 'pending', 'additional_info_requested', 'resolved'
  /// (adminDecision stores the actual action: warn/restrict/suspend/ban/no_action/additional_info)
  final String status;
  final String? threadId;
  final String subscriptionStatus;
  final String parentAction;
  /// The admin's moderation decision: 'warn', 'restrict', 'suspend', 'ban', 'no_action'.
  final String? adminDecision;
  final String? adminNotes;
  final DateTime? resolvedAt;
  /// Who the admin is requesting additional info from: 'reporter', 'reported', or 'both'.
  final String? additionalInfoRequestedFrom;
  /// The admin's reason for needing additional information.
  final String? adminInfoRequestReason;
  /// Specific description of what information the admin needs.
  final String? adminInfoRequestDescription;
  /// Number of days the restriction should last (set by admin when action is 'restrict').
  final int? restrictionDays;

  factory UserReport.fromMap(String id, Map<String, dynamic> data) {
    final rawContext = data['chatContext'] as List?;
    final context = rawContext != null
        ? rawContext.map((item) => Map<String, dynamic>.from(item as Map)).toList()
        : const <Map<String, dynamic>>[];

    return UserReport(
      id: id,
      reporterId: (data['reporterId'] ?? '').toString(),
      reporterRole: (data['reporterRole'] ?? '').toString(),
      reportedId: (data['reportedId'] ?? '').toString(),
      reason: (data['reason'] ?? '').toString(),
      comments: (data['comments'] ?? '').toString(),
      chatContext: context,
      timestamp: dateTimeFromFirestore(data['timestamp']) ?? DateTime.now(),
      status: (data['status'] ?? 'pending').toString(),
      threadId: data['threadId']?.toString(),
      subscriptionStatus: (data['subscriptionStatus'] ?? 'none').toString(),
      parentAction: (data['parentAction'] ?? 'none').toString(),
      adminDecision: data['adminDecision']?.toString(),
      adminNotes: data['adminNotes']?.toString(),
      resolvedAt: dateTimeFromFirestore(data['resolvedAt']),
      additionalInfoRequestedFrom: data['additionalInfoRequestedFrom']?.toString(),
      adminInfoRequestReason: data['adminInfoRequestReason']?.toString(),
      adminInfoRequestDescription: data['adminInfoRequestDescription']?.toString(),
      restrictionDays: data['restrictionDays'] != null ? intFrom(data['restrictionDays']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reporterId': reporterId,
      'reporterRole': reporterRole,
      'reportedId': reportedId,
      'reason': reason,
      'comments': comments,
      'chatContext': chatContext,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      if (threadId != null) 'threadId': threadId,
      'subscriptionStatus': subscriptionStatus,
      'parentAction': parentAction,
      if (adminDecision != null) 'adminDecision': adminDecision,
      if (adminNotes != null) 'adminNotes': adminNotes,
      if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
      if (additionalInfoRequestedFrom != null) 'additionalInfoRequestedFrom': additionalInfoRequestedFrom,
      if (adminInfoRequestReason != null) 'adminInfoRequestReason': adminInfoRequestReason,
      if (adminInfoRequestDescription != null) 'adminInfoRequestDescription': adminInfoRequestDescription,
      if (restrictionDays != null) 'restrictionDays': restrictionDays,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Moderation System Models
// ─────────────────────────────────────────────────────────────────────────────

/// A single entry in a user's permanent moderation history.
/// Records every admin action applied or removed. This history is NEVER deleted.
class ModerationHistoryEntry {
  const ModerationHistoryEntry({
    required this.id,
    required this.targetUserId,
    required this.targetRole,
    required this.action,
    required this.reason,
    required this.adminId,
    required this.adminEmail,
    required this.timestamp,
    this.reportId,
    this.restrictedWithUserId,
    this.restrictionDays,
  });

  final String id;
  /// The user who received the moderation action.
  final String targetUserId;
  /// Role of the target user: 'parent' or 'therapist'.
  final String targetRole;
  /// The moderation action applied.
  /// Values: 'warn', 'restrict', 'suspend', 'ban', 'no_action',
  ///         'remove_warn', 'remove_restrict', 'remove_suspend', 'remove_ban',
  ///         'additional_info_requested', 'restore'
  final String action;
  /// Mandatory reason provided by the admin. Never empty.
  final String reason;
  final String adminId;
  final String adminEmail;
  final DateTime timestamp;
  /// The report that triggered this moderation action (if applicable).
  final String? reportId;
  /// For 'restrict' actions: the other party's userId (e.g., the parent for a therapist restriction).
  final String? restrictedWithUserId;
  /// For 'restrict' actions: duration in days configured by admin.
  final int? restrictionDays;

  factory ModerationHistoryEntry.fromMap(String id, Map<String, dynamic> data) {
    return ModerationHistoryEntry(
      id: id,
      targetUserId: (data['targetUserId'] ?? '').toString(),
      targetRole: (data['targetRole'] ?? '').toString(),
      action: (data['action'] ?? '').toString(),
      reason: (data['reason'] ?? '').toString(),
      adminId: (data['adminId'] ?? '').toString(),
      adminEmail: (data['adminEmail'] ?? '').toString(),
      timestamp: dateTimeFromFirestore(data['timestamp']) ?? DateTime.now(),
      reportId: data['reportId']?.toString(),
      restrictedWithUserId: data['restrictedWithUserId']?.toString(),
      restrictionDays: data['restrictionDays'] != null ? intFrom(data['restrictionDays']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'targetUserId': targetUserId,
      'targetRole': targetRole,
      'action': action,
      'reason': reason,
      'adminId': adminId,
      'adminEmail': adminEmail,
      'timestamp': timestamp,
      if (reportId != null) 'reportId': reportId,
      if (restrictedWithUserId != null) 'restrictedWithUserId': restrictedWithUserId,
      if (restrictionDays != null) 'restrictionDays': restrictionDays,
    };
  }
}

/// A per-relationship restriction record.
/// A restriction only affects interaction between [parentId] and [therapistId].
/// All other parents/therapists are unaffected.
class RestrictionRecord {
  const RestrictionRecord({
    required this.id,
    required this.parentId,
    required this.therapistId,
    required this.reportId,
    required this.moderationHistoryId,
    required this.startDate,
    required this.endDate,
    required this.restrictionDays,
    required this.status,
    required this.appliedByAdminId,
    this.removedByAdminId,
    this.removalReason,
    this.removedAt,
  });

  final String id;
  final String parentId;
  final String therapistId;
  /// The report that triggered this restriction.
  final String reportId;
  /// The moderation_history entry that created this restriction.
  final String moderationHistoryId;
  final DateTime startDate;
  final DateTime endDate;
  final int restrictionDays;
  /// Status: 'active', 'expired', 'removed'
  final String status;
  final String appliedByAdminId;
  final String? removedByAdminId;
  final String? removalReason;
  final DateTime? removedAt;

  bool get isActive =>
      status == 'active' && DateTime.now().isBefore(endDate);

  factory RestrictionRecord.fromMap(String id, Map<String, dynamic> data) {
    return RestrictionRecord(
      id: id,
      parentId: (data['parentId'] ?? '').toString(),
      therapistId: (data['therapistId'] ?? '').toString(),
      reportId: (data['reportId'] ?? '').toString(),
      moderationHistoryId: (data['moderationHistoryId'] ?? '').toString(),
      startDate: dateTimeFromFirestore(data['startDate']) ?? DateTime.now(),
      endDate: dateTimeFromFirestore(data['endDate']) ?? DateTime.now(),
      restrictionDays: intFrom(data['restrictionDays'], 4),
      status: (data['status'] ?? 'active').toString(),
      appliedByAdminId: (data['appliedByAdminId'] ?? '').toString(),
      removedByAdminId: data['removedByAdminId']?.toString(),
      removalReason: data['removalReason']?.toString(),
      removedAt: dateTimeFromFirestore(data['removedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'therapistId': therapistId,
      'reportId': reportId,
      'moderationHistoryId': moderationHistoryId,
      'startDate': startDate,
      'endDate': endDate,
      'restrictionDays': restrictionDays,
      'status': status,
      'appliedByAdminId': appliedByAdminId,
      if (removedByAdminId != null) 'removedByAdminId': removedByAdminId,
      if (removalReason != null) 'removalReason': removalReason,
      if (removedAt != null) 'removedAt': removedAt,
    };
  }
}

/// A message submitted by a reporter or reported user as part of an
/// 'Additional Information Required' request from an admin.
/// Stored as a subcollection: reports/{reportId}/messages/{messageId}.
class ReportMessage {
  const ReportMessage({
    required this.id,
    required this.reportId,
    required this.senderId,
    required this.senderRole,
    required this.messageType,
    required this.content,
    required this.timestamp,
    required this.requestedByAdminId,
    this.attachments = const [],
  });

  final String id;
  final String reportId;
  final String senderId;
  /// 'parent' or 'therapist'
  final String senderRole;
  /// 'text', 'image', 'pdf', 'voice'
  final String messageType;
  /// Text content, or a description for non-text messages.
  final String content;
  final DateTime timestamp;
  /// The admin who requested this information.
  final String requestedByAdminId;
  /// Attachment data: [{type, data (base64 or url), filename}]
  final List<Map<String, dynamic>> attachments;

  factory ReportMessage.fromMap(String id, Map<String, dynamic> data) {
    final rawAttachments = data['attachments'] as List?;
    final attachments = rawAttachments != null
        ? rawAttachments.map((item) => Map<String, dynamic>.from(item as Map)).toList()
        : const <Map<String, dynamic>>[];
    return ReportMessage(
      id: id,
      reportId: (data['reportId'] ?? '').toString(),
      senderId: (data['senderId'] ?? '').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      messageType: (data['messageType'] ?? 'text').toString(),
      content: (data['content'] ?? '').toString(),
      timestamp: dateTimeFromFirestore(data['timestamp']) ?? DateTime.now(),
      requestedByAdminId: (data['requestedByAdminId'] ?? '').toString(),
      attachments: attachments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reportId': reportId,
      'senderId': senderId,
      'senderRole': senderRole,
      'messageType': messageType,
      'content': content,
      'timestamp': timestamp,
      'requestedByAdminId': requestedByAdminId,
      'attachments': attachments,
    };
  }
}

class NotificationInboxItem {
  const NotificationInboxItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    required this.isRead,
    this.navigationTarget = const <String, dynamic>{},
  });

  final String id;
  final String userId;
  final String title;
  final String message;
  final String category; // 'messages', 'subscription', 'reviews', 'activities', 'verification', 'system'
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic> navigationTarget;

  factory NotificationInboxItem.fromMap(String id, Map<String, dynamic> data) {
    return NotificationInboxItem(
      id: id,
      userId: (data['userId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      category: (data['category'] ?? 'system').toString(),
      timestamp: dateTimeFromFirestore(data['timestamp']) ?? DateTime.now(),
      isRead: data['isRead'] == true,
      navigationTarget: mapFrom(data['navigationTarget']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'message': message,
      'category': category,
      'timestamp': timestamp,
      'isRead': isRead,
      'navigationTarget': navigationTarget,
    };
  }
}

class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.adminUid,
    required this.targetUid,
    required this.actionType,
    required this.details,
    required this.timestamp,
    this.adminEmail = '',
  });

  final String id;
  final String adminUid;
  final String targetUid;
  final String actionType;
  final String details;
  final DateTime timestamp;
  final String adminEmail;

  factory AdminAuditLog.fromMap(String id, Map<String, dynamic> data) {
    return AdminAuditLog(
      id: id,
      adminUid: (data['adminUid'] ?? '').toString(),
      targetUid: (data['targetUid'] ?? '').toString(),
      actionType: (data['actionType'] ?? '').toString(),
      details: (data['details'] ?? '').toString(),
      timestamp: dateTimeFromFirestore(data['timestamp']) ?? DateTime.now(),
      adminEmail: (data['adminEmail'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminUid': adminUid,
      'targetUid': targetUid,
      'actionType': actionType,
      'details': details,
      'timestamp': timestamp,
      'adminEmail': adminEmail,
    };
  }
}


/// Describes the block relationship between two users in a thread.
class BlockInfo {
  const BlockInfo({
    this.iBlockedThem = false,
    this.theyBlockedMe = false,
    this.blockerDisplayName = '',
  });

  /// True if the current user is the one who initiated the block.
  final bool iBlockedThem;

  /// True if the peer has blocked the current user.
  final bool theyBlockedMe;

  /// Display name of whoever did the blocking (used for dynamic UI text).
  final String blockerDisplayName;

  bool get isBlocked => iBlockedThem || theyBlockedMe;
}

class TherapistThread {
  const TherapistThread({
    required this.id,
    required this.parentId,
    required this.therapistId,
    required this.childId,
    required this.subscriptionId,
    required this.status,
    this.parentDisplayName = '',
    this.therapistDisplayName = '',
    this.lastMessagePreview = '',
    this.lastMessageAt,
    this.emergencyStatus = 'none',
    this.emergencyRequestedBy,
    this.emergencyRequestedAt,
    this.emergencyRespondedAt,
    this.postCancelVisible = true,
    this.parentTyping = false,
    this.therapistTyping = false,
    this.parentLastRead,
    this.therapistLastRead,
    this.blockedByParent = false,
    this.blockedByTherapist = false,
    this.finalMessageSentByParent = false,
    this.finalMessageSentByTherapist = false,
    this.finalReplySentByParent = false,
    this.finalReplySentByTherapist = false,
    // Report tracking — true after the respective side has filed an open report
    this.reportedByParent = false,
    this.reportedByTherapist = false,
  });

  final String id;
  final String parentId;
  final String therapistId;
  final String childId;
  final String subscriptionId;
  final String status;
  final String parentDisplayName;
  final String therapistDisplayName;
  final String lastMessagePreview;
  final DateTime? lastMessageAt;
  final String emergencyStatus;
  final String? emergencyRequestedBy;
  final DateTime? emergencyRequestedAt;
  final DateTime? emergencyRespondedAt;
  final bool postCancelVisible;
  final bool parentTyping;
  final bool therapistTyping;
  final DateTime? parentLastRead;
  final DateTime? therapistLastRead;
  final bool blockedByParent;
  final bool blockedByTherapist;
  final bool finalMessageSentByParent;
  final bool finalMessageSentByTherapist;
  final bool finalReplySentByParent;
  final bool finalReplySentByTherapist;
  /// True after the parent has filed an open report on this thread.
  final bool reportedByParent;
  /// True after the therapist has filed an open report on this thread.
  final bool reportedByTherapist;

  bool get hasOpenEmergency => emergencyStatus == 'requested';
  bool get emergencyResponded => emergencyStatus == 'responded';
  bool get isBlocked => blockedByParent || blockedByTherapist;

  factory TherapistThread.fromMap(String id, Map<String, dynamic> data) {
    return TherapistThread(
      id: id,
      parentId: (data['parentId'] ?? '').toString(),
      therapistId: (data['therapistId'] ?? '').toString(),
      childId: (data['childId'] ?? '').toString(),
      subscriptionId: (data['subscriptionId'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      parentDisplayName: (data['parentDisplayName'] ?? '').toString(),
      therapistDisplayName: (data['therapistDisplayName'] ?? '').toString(),
      lastMessagePreview: (data['lastMessagePreview'] ?? '').toString(),
      lastMessageAt: dateTimeFromFirestore(data['lastMessageAt']),
      emergencyStatus: (data['emergencyStatus'] ?? 'none').toString(),
      emergencyRequestedBy: data['emergencyRequestedBy']?.toString(),
      emergencyRequestedAt: dateTimeFromFirestore(data['emergencyRequestedAt']),
      emergencyRespondedAt: dateTimeFromFirestore(data['emergencyRespondedAt']),
      postCancelVisible: data['postCancelVisible'] != false,
      parentTyping: data['parentTyping'] == true,
      therapistTyping: data['therapistTyping'] == true,
      parentLastRead: dateTimeFromFirestore(data['parentLastRead']),
      therapistLastRead: dateTimeFromFirestore(data['therapistLastRead']),
      blockedByParent: data['blockedByParent'] == true,
      blockedByTherapist: data['blockedByTherapist'] == true,
      finalMessageSentByParent: data['finalMessageSentByParent'] == true,
      finalMessageSentByTherapist: data['finalMessageSentByTherapist'] == true,
      finalReplySentByParent: data['finalReplySentByParent'] == true,
      finalReplySentByTherapist: data['finalReplySentByTherapist'] == true,
      reportedByParent: data['reportedByParent'] == true,
      reportedByTherapist: data['reportedByTherapist'] == true,
    );
  }

  TherapistThread copyWith({
    String? parentDisplayName,
    String? therapistDisplayName,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    String? status,
    String? subscriptionId,
    String? emergencyStatus,
    String? emergencyRequestedBy,
    DateTime? emergencyRequestedAt,
    DateTime? emergencyRespondedAt,
    bool? postCancelVisible,
    bool? parentTyping,
    bool? therapistTyping,
    DateTime? parentLastRead,
    DateTime? therapistLastRead,
    bool? blockedByParent,
    bool? blockedByTherapist,
    bool? finalMessageSentByParent,
    bool? finalMessageSentByTherapist,
    bool? finalReplySentByParent,
    bool? finalReplySentByTherapist,
    bool? reportedByParent,
    bool? reportedByTherapist,
  }) {
    return TherapistThread(
      id: id,
      parentId: parentId,
      therapistId: therapistId,
      childId: childId,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      status: status ?? this.status,
      parentDisplayName: parentDisplayName ?? this.parentDisplayName,
      therapistDisplayName: therapistDisplayName ?? this.therapistDisplayName,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      emergencyStatus: emergencyStatus ?? this.emergencyStatus,
      emergencyRequestedBy: emergencyRequestedBy ?? this.emergencyRequestedBy,
      emergencyRequestedAt: emergencyRequestedAt ?? this.emergencyRequestedAt,
      emergencyRespondedAt: emergencyRespondedAt ?? this.emergencyRespondedAt,
      postCancelVisible: postCancelVisible ?? this.postCancelVisible,
      parentTyping: parentTyping ?? this.parentTyping,
      therapistTyping: therapistTyping ?? this.therapistTyping,
      parentLastRead: parentLastRead ?? this.parentLastRead,
      therapistLastRead: therapistLastRead ?? this.therapistLastRead,
      blockedByParent: blockedByParent ?? this.blockedByParent,
      blockedByTherapist: blockedByTherapist ?? this.blockedByTherapist,
      finalMessageSentByParent: finalMessageSentByParent ?? this.finalMessageSentByParent,
      finalMessageSentByTherapist: finalMessageSentByTherapist ?? this.finalMessageSentByTherapist,
      finalReplySentByParent: finalReplySentByParent ?? this.finalReplySentByParent,
      finalReplySentByTherapist: finalReplySentByTherapist ?? this.finalReplySentByTherapist,
      reportedByParent: reportedByParent ?? this.reportedByParent,
      reportedByTherapist: reportedByTherapist ?? this.reportedByTherapist,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'therapistId': therapistId,
      'childId': childId,
      'subscriptionId': subscriptionId,
      'status': status,
      'parentDisplayName': parentDisplayName,
      'therapistDisplayName': therapistDisplayName,
      'lastMessagePreview': lastMessagePreview,
      if (lastMessageAt != null) 'lastMessageAt': lastMessageAt,
      'emergencyStatus': emergencyStatus,
      'emergencyRequestedBy': emergencyRequestedBy,
      'emergencyRequestedAt': emergencyRequestedAt,
      'emergencyRespondedAt': emergencyRespondedAt,
      'postCancelVisible': postCancelVisible,
      'blockedByParent': blockedByParent,
      'blockedByTherapist': blockedByTherapist,
      'finalMessageSentByParent': finalMessageSentByParent,
      'finalMessageSentByTherapist': finalMessageSentByTherapist,
      'finalReplySentByParent': finalReplySentByParent,
      'finalReplySentByTherapist': finalReplySentByTherapist,
      'reportedByParent': reportedByParent,
      'reportedByTherapist': reportedByTherapist,
    };
  }
}

class TherapistMessage {
  const TherapistMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.attachments,
    this.sentAt,
    this.messageType = 'text',
    this.deliveryStatus = 'sent',
    this.deliveryError,
    this.isDeleted = false,
    this.replyToId,
    this.replyToPreview,
    this.reaction,
  });

  final String id;
  final String senderId;
  final String senderRole;
  final String body;
  final List<String> attachments;
  final DateTime? sentAt;
  final String messageType;
  final String deliveryStatus;
  final String? deliveryError;
  final bool isDeleted;
  final String? replyToId;
  final String? replyToPreview;
  final String? reaction;

  factory TherapistMessage.fromMap(String id, Map<String, dynamic> data) {
    return TherapistMessage(
      id: id,
      senderId: (data['senderId'] ?? '').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      attachments: stringListFrom(data['attachments']),
      sentAt: dateTimeFromFirestore(data['sentAt']),
      messageType: (data['messageType'] ?? 'text').toString(),
      deliveryStatus: (data['deliveryStatus'] ?? 'sent').toString(),
      deliveryError: data['deliveryError']?.toString(),
      isDeleted: data['isDeleted'] == true,
      replyToId: data['replyToId']?.toString(),
      replyToPreview: data['replyToPreview']?.toString(),
      reaction: data['reaction']?.toString(),
    );
  }
}

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.featureList,
    required this.priceLabel,
    required this.isActive,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> featureList;
  final String priceLabel;
  final bool isActive;

  factory SubscriptionProduct.fromMap(String id, Map<String, dynamic> data) {
    return SubscriptionProduct(
      id: id,
      title: (data['title'] ?? '').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      featureList: stringListFrom(data['featureList']),
      priceLabel: formatPriceString((data['priceLabel'] ?? '').toString()),
      isActive: data['isActive'] != false,
    );
  }
}

class UserSubscription {
  const UserSubscription({
    required this.id,
    required this.userId,
    this.therapistId,
    required this.productId,
    required this.status,
    required this.cancelAtPeriodEnd,
    this.currentPeriodEnd,
    this.subscribedPackageSnapshot,
  });

  final String id;
  final String userId;
  final String? therapistId;
  final String productId;
  final String status;
  final bool cancelAtPeriodEnd;
  final DateTime? currentPeriodEnd;
  final TherapyPackage? subscribedPackageSnapshot;

  bool get isActive => status == 'active' || status == 'trialing' || status == 'grace_period';

  factory UserSubscription.fromMap(String id, Map<String, dynamic> data) {
    final pkgData = data['subscribedPackageSnapshot'];
    return UserSubscription(
      id: id,
      userId: (data['userId'] ?? '').toString(),
      therapistId: data['therapistId']?.toString(),
      productId: (data['productId'] ?? '').toString(),
      status: (data['status'] ?? 'inactive').toString(),
      cancelAtPeriodEnd: data['cancelAtPeriodEnd'] == true,
      currentPeriodEnd: dateTimeFromFirestore(data['currentPeriodEnd']),
      subscribedPackageSnapshot: pkgData != null && pkgData is Map<String, dynamic>
          ? TherapyPackage.fromMap(pkgData)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'therapistId': therapistId,
      'productId': productId,
      'status': status,
      'cancelAtPeriodEnd': cancelAtPeriodEnd,
      'currentPeriodEnd': currentPeriodEnd != null ? Timestamp.fromDate(currentPeriodEnd!) : null,
      'subscribedPackageSnapshot': subscribedPackageSnapshot?.toMap(),
    };
  }
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.audience,
    required this.version,
    required this.title,
    required this.body,
    required this.isActive,
  });

  final String id;
  final String audience;
  final String version;
  final String title;
  final String body;
  final bool isActive;

  factory LegalDocument.fromMap(String id, Map<String, dynamic> data) {
    return LegalDocument(
      id: id,
      audience: (data['audience'] ?? '').toString(),
      version: (data['version'] ?? 'v1').toString(),
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      isActive: data['isActive'] != false,
    );
  }
}

class SettingsEntry {
  const SettingsEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.routeKey,
    required this.targetRole,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String title;
  final String subtitle;
  final String routeKey;
  final String targetRole;
  final int sortOrder;
  final bool isActive;

  factory SettingsEntry.fromMap(String id, Map<String, dynamic> data) {
    return SettingsEntry(
      id: id,
      title: (data['title'] ?? '').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      routeKey: (data['routeKey'] ?? '').toString(),
      targetRole: (data['targetRole'] ?? '').toString(),
      sortOrder: intFrom(data['sortOrder']),
      isActive: data['isActive'] != false,
    );
  }
}

class ClinicalNote {
  const ClinicalNote({
    required this.id,
    required this.therapistId,
    required this.parentId,
    required this.childId,
    required this.therapistName,
    required this.childName,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String therapistId;
  final String parentId;
  final String childId;
  final String therapistName;
  final String childName;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ClinicalNote.fromMap(String id, Map<String, dynamic> data) {
    return ClinicalNote(
      id: id,
      therapistId: (data['therapistId'] ?? '').toString(),
      parentId: (data['parentId'] ?? '').toString(),
      childId: (data['childId'] ?? '').toString(),
      therapistName: (data['therapistName'] ?? '').toString(),
      childName: (data['childName'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'therapistId': therapistId,
      'parentId': parentId,
      'childId': childId,
      'therapistName': therapistName,
      'childName': childName,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class AppointmentSlot {
  const AppointmentSlot({
    required this.id,
    required this.therapistId,
    required this.dateTime,
    required this.durationMinutes,
    required this.status, // 'available', 'booked', 'cancelled'
    this.bookedByParentId,
    this.bookedForChildId,
    this.bookedForChildName,
    this.notes,
    required this.createdAt,
    this.packageTitle,
    this.assignedToParentId,
    this.sessionCompleted = false,
    this.clinicalNote,
  });

  final String id;
  final String therapistId;
  final DateTime dateTime;
  final int durationMinutes;
  final String status;
  final String? bookedByParentId;
  final String? bookedForChildId;
  final String? bookedForChildName;
  final String? notes;
  final DateTime createdAt;
  final String? packageTitle;
  final String? assignedToParentId;
  final bool sessionCompleted;
  final String? clinicalNote;

  factory AppointmentSlot.fromMap(String id, Map<String, dynamic> data) {
    return AppointmentSlot(
      id: id,
      therapistId: (data['therapistId'] ?? '').toString(),
      dateTime: data['dateTime'] != null
          ? (data['dateTime'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
      durationMinutes: intFrom(data['durationMinutes']) > 0 ? intFrom(data['durationMinutes']) : 60,
      status: (data['status'] ?? 'available').toString(),
      bookedByParentId: data['bookedByParentId']?.toString(),
      bookedForChildId: data['bookedForChildId']?.toString(),
      bookedForChildName: data['bookedForChildName']?.toString(),
      notes: data['notes']?.toString(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
      packageTitle: data['packageTitle']?.toString(),
      assignedToParentId: data['assignedToParentId']?.toString(),
      sessionCompleted: data['sessionCompleted'] == true,
      clinicalNote: data['clinicalNote']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'therapistId': therapistId,
      'dateTime': Timestamp.fromDate(dateTime),
      'durationMinutes': durationMinutes,
      'status': status,
      'bookedByParentId': bookedByParentId,
      'bookedForChildId': bookedForChildId,
      'bookedForChildName': bookedForChildName,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'packageTitle': packageTitle,
      'assignedToParentId': assignedToParentId,
      'sessionCompleted': sessionCompleted,
      'clinicalNote': clinicalNote,
    };
  }
}

class SlotRequest {
  const SlotRequest({
    required this.id,
    required this.parentId,
    required this.parentName,
    required this.therapistId,
    required this.packageTitle,
    required this.preferredDateTime,
    required this.status, // 'pending', 'approved', 'declined'
    this.declineReason,
    required this.createdAt,
  });

  final String id;
  final String parentId;
  final String parentName;
  final String therapistId;
  final String packageTitle;
  final DateTime preferredDateTime;
  final String status;
  final String? declineReason;
  final DateTime createdAt;

  factory SlotRequest.fromMap(String id, Map<String, dynamic> data) {
    return SlotRequest(
      id: id,
      parentId: (data['parentId'] ?? '').toString(),
      parentName: (data['parentName'] ?? '').toString(),
      therapistId: (data['therapistId'] ?? '').toString(),
      packageTitle: (data['packageTitle'] ?? '').toString(),
      preferredDateTime: data['preferredDateTime'] != null
          ? (data['preferredDateTime'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
      status: (data['status'] ?? 'pending').toString(),
      declineReason: data['declineReason']?.toString(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate().toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'parentName': parentName,
      'therapistId': therapistId,
      'packageTitle': packageTitle,
      'preferredDateTime': Timestamp.fromDate(preferredDateTime),
      'status': status,
      'declineReason': declineReason,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

