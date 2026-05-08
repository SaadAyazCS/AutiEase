import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/app_repositories.dart';
import 'play_preferences_service.dart';

class LearningMetricsService {
  const LearningMetricsService();

  Future<void> recordGameplayMetric({
    required String childId,
    required String gameType,
    required String moduleId,
    required String roundId,
    required String outcome,
    int attempts = 0,
    int wrongSelections = 0,
    int responseTimeMs = 0,
    double? traceAccuracy,
    int speechRetries = 0,
    ParentDifficulty difficulty = ParentDifficulty.normal,
    bool lowStimulationMode = false,
    int adaptiveLevel = 0,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    await AppRepositories.firestore
        .collection(FirestoreCollections.learningMetrics)
        .add({
          'childId': childId,
          'gameType': gameType,
          'moduleId': moduleId,
          'roundId': roundId,
          'outcome': outcome,
          'attempts': attempts,
          'wrongSelections': wrongSelections,
          'responseTimeMs': responseTimeMs,
          if (traceAccuracy != null) 'traceAccuracy': traceAccuracy,
          'speechRetries': speechRetries,
          'difficulty': difficulty.key,
          'lowStimulationMode': lowStimulationMode,
          'adaptiveLevel': adaptiveLevel,
          'metadata': metadata,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }
}

class GameplayMetricsTracker {
  GameplayMetricsTracker() {
    reset();
  }

  int attempts = 0;
  int wrongSelections = 0;
  int speechRetries = 0;
  DateTime _startedAt = DateTime.now();

  void reset() {
    attempts = 0;
    wrongSelections = 0;
    speechRetries = 0;
    _startedAt = DateTime.now();
  }

  void markAttempt({bool wrong = false}) {
    attempts += 1;
    if (wrong) {
      wrongSelections += 1;
    }
  }

  void markSpeechRetry() {
    speechRetries += 1;
  }

  int get responseTimeMs =>
      DateTime.now().difference(_startedAt).inMilliseconds;
}
