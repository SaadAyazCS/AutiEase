import '../../../repositories/app_repositories.dart';
import '../models/speak_learn_level_kind.dart';

/// Persists Speak & Learn outcomes into [activity_progress] for dashboard metrics.
class SpeakLearnAnalytics {
  SpeakLearnAnalytics._();

  static Future<void> recordLevelCompletion({
    required String childId,
    required SpeakLearnLevelKind kind,
    required String moduleId,
    required int starRating,
    required int totalItems,
    required int correctItems,
    required int failedAttemptsTotal,
  }) async {
    final badge = kind.badgeKey;
    final itemId =
        'speak_learn:${kind.name}:complete:${moduleId.hashCode & 0x7fffffff}';

    await AppRepositories.planner.recordActivityCompletion(
      childId: childId,
      itemId: itemId,
      moduleId: moduleId,
      score: starRating,
      metadata: {
        'source': 'speak_learn',
        'speakLearnLevel': kind.name,
        'speakLearnBadge': badge,
        'starRating': starRating,
        'speakLearnComplete': true,
        'speakLearnTotalItems': totalItems,
        'speakLearnCorrectItems': correctItems,
        'speakLearnFailedAttempts': failedAttemptsTotal,
      },
    );
  }
}
