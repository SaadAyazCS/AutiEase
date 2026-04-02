import 'package:flutter_test/flutter_test.dart';

import 'package:autiease/models/app_models.dart';
import 'package:autiease/services/dashboard_metrics_calculator.dart';

void main() {
  final calculator = DashboardMetricsCalculator();

  group('DashboardMetricsCalculator', () {
    test('computes weekly metrics and category progress from events', () {
      final now = DateTime(2026, 4, 2, 12);
      final metrics = calculator.build(
        childId: 'child-1',
        activityEvents: [
          ActivityProgressEntry(
            id: '1',
            childId: 'child-1',
            itemId: 'move-play-tap',
            moduleId: 'move-play-tap',
            status: 'completed',
            score: 100,
            attempts: 1,
            completedAt: now.subtract(const Duration(days: 1)),
          ),
          ActivityProgressEntry(
            id: '2',
            childId: 'child-1',
            itemId: 'speak-learn-alphabets',
            moduleId: 'speak-learn-alphabets',
            status: 'completed',
            score: 100,
            attempts: 1,
            completedAt: now.subtract(const Duration(days: 2)),
          ),
          ActivityProgressEntry(
            id: '3',
            childId: 'child-1',
            itemId: 'focus-find-it',
            moduleId: 'focus-find-it',
            status: 'completed',
            score: 100,
            attempts: 1,
            completedAt: now.subtract(const Duration(days: 14)),
          ),
        ],
        moodLogs: const [],
        assignedModules: const [
          LearningModuleModel(
            id: 'move-play-tap',
            title: 'Tap Game',
            description: '',
            type: 'learning',
            learningCategoryKey: 'move_play',
            learningCategoryTitle: 'Move & Play',
            gameTypeKey: 'tap_game',
            levelRange: 'L1',
            assetRefs: [],
            sortOrder: 1,
            isActive: true,
          ),
          LearningModuleModel(
            id: 'speak-learn-alphabets',
            title: 'Alphabets',
            description: '',
            type: 'learning',
            learningCategoryKey: 'speak_learn',
            learningCategoryTitle: 'Speak & Learn',
            gameTypeKey: 'alphabets',
            levelRange: 'L1',
            assetRefs: [],
            sortOrder: 2,
            isActive: true,
          ),
          LearningModuleModel(
            id: 'focus-find-it',
            title: 'Find it',
            description: '',
            type: 'learning',
            learningCategoryKey: 'focus_games',
            learningCategoryTitle: 'Focus Games',
            gameTypeKey: 'find_it',
            levelRange: 'L1',
            assetRefs: [],
            sortOrder: 3,
            isActive: true,
          ),
        ],
        assignedTemplates: const [
          DailyActivityTemplate(
            id: 'morning-routine',
            title: 'Morning Routine',
            description: '',
            moduleRefs: ['move-play-tap'],
            estimatedMinutes: 15,
            difficulty: 'easy',
            isActive: true,
          ),
        ],
        now: now,
      );

      expect(metrics.completedActivities, 2);
      expect(metrics.weeklyMinutes, 21);
      expect(metrics.movePlayProgress, closeTo(0.74, 0.01));
      expect(metrics.talkExpressProgress, closeTo(0.72, 0.01));
      expect(metrics.focusGamesProgress, 0.0);
      expect(metrics.activityLevel, 'Low');
    });

    test(
      'derives category progress from event patterns without assignments',
      () {
        final now = DateTime(2026, 4, 2, 12);
        final metrics = calculator.build(
          childId: 'child-3',
          activityEvents: [
            ActivityProgressEntry(
              id: '1',
              childId: 'child-3',
              itemId: 'color-red',
              moduleId: 'colors',
              status: 'completed',
              score: 1,
              attempts: 1,
              completedAt: now.subtract(const Duration(hours: 1)),
            ),
            ActivityProgressEntry(
              id: '2',
              childId: 'child-3',
              itemId: 'move-play-tap-level-1',
              moduleId: 'move-play-tap',
              status: 'completed',
              score: 100,
              attempts: 1,
              completedAt: now.subtract(const Duration(minutes: 30)),
            ),
          ],
          moodLogs: const [],
          assignedModules: const [],
          assignedTemplates: const [],
          now: now,
        );

        expect(metrics.movePlayProgress, closeTo(0.125, 0.001));
        expect(metrics.talkExpressProgress, closeTo(0.083, 0.001));
        expect(metrics.focusGamesProgress, 0.0);
        expect(metrics.weeklyMinutes, 2);
        expect(metrics.completedActivities, 2);
      },
    );

    test(
      'does not increase move progress when the same tap levels are replayed',
      () {
        final now = DateTime(2026, 4, 2, 12);
        DashboardMetrics buildWithLevelRepeats(int repeats) {
          final events = <ActivityProgressEntry>[];
          var id = 0;
          for (var run = 0; run < repeats; run += 1) {
            for (var level = 1; level <= 3; level += 1) {
              id += 1;
              events.add(
                ActivityProgressEntry(
                  id: '$id',
                  childId: 'child-4',
                  itemId: 'move-play-tap-level-$level',
                  moduleId: 'move-play-tap',
                  status: 'completed',
                  score: 100,
                  attempts: 1,
                  completedAt: now.subtract(Duration(minutes: id)),
                ),
              );
            }
          }
          return calculator.build(
            childId: 'child-4',
            activityEvents: events,
            moodLogs: const [],
            assignedModules: const [],
            assignedTemplates: const [],
            now: now,
          );
        }

        final oneRun = buildWithLevelRepeats(1);
        final twoRuns = buildWithLevelRepeats(2);

        expect(oneRun.movePlayProgress, closeTo(0.375, 0.001));
        expect(twoRuns.movePlayProgress, closeTo(0.375, 0.001));
        expect(oneRun.weeklyMinutes, 3);
        expect(twoRuns.weeklyMinutes, 5);
        expect(oneRun.completedActivities, 3);
        expect(twoRuns.completedActivities, 3);
      },
    );

    test(
      'infers mood from emotion-tagged events when mood logs are absent',
      () {
        final now = DateTime(2026, 4, 2, 12);
        final metrics = calculator.build(
          childId: 'child-2',
          activityEvents: [
            ActivityProgressEntry(
              id: '1',
              childId: 'child-2',
              itemId: 'emotion-happy-alt',
              moduleId: 'feelings',
              status: 'completed',
              score: 1,
              attempts: 1,
              completedAt: now.subtract(const Duration(hours: 2)),
            ),
          ],
          moodLogs: const [],
          assignedModules: const [],
          assignedTemplates: const [],
          now: now,
        );

        expect(metrics.moodLabel, 'Happy');
        expect(metrics.weeklyReport.sections, hasLength(3));
        expect(metrics.weeklyReport.title, 'Weekly Progress Report');
        expect(metrics.monthlyReport.title, 'Monthly Assessment');
      },
    );
  });
}
