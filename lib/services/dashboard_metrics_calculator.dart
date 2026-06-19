import 'dart:math' as math;

import '../models/app_models.dart';

class DashboardMetricsCalculator {
  static const int _weeklyWindowDays = 7;
  static const int _monthlyWindowDays = 30;
  static const int _defaultModuleMinutes = 6;
  static const int _fallbackMinutes = 1;
  static const double _communicationTapMinutes = 0.4;
  static const double _gameLevelMinutes = 0.8;
  static const double _gameSessionMinutes = 4.0;
  static const double _moduleCoverageWeight = 0.7;
  static const double _engagementWeight = 0.3;

  DashboardMetrics build({
    required String childId,
    required List<ActivityProgressEntry> activityEvents,
    required List<MoodLogEntry> moodLogs,
    required List<LearningModuleModel> assignedModules,
    required List<DailyActivityTemplate> assignedTemplates,
    List<CustomDailyActivity> customActivities = const <CustomDailyActivity>[],
    int totalDailyActivitiesAssigned = 0,
    DateTime? now,
  }) {
    final generatedAt = now ?? DateTime.now();
    final todayStart = DateTime(
      generatedAt.year,
      generatedAt.month,
      generatedAt.day,
    );
    final weeklyStart = generatedAt.subtract(
      const Duration(days: _weeklyWindowDays),
    );
    final monthlyStart = generatedAt.subtract(
      const Duration(days: _monthlyWindowDays),
    );

    final monthlyEvents = activityEvents
        .where((event) => _isOnOrAfter(event.completedAt, monthlyStart))
        .toList();
    final weeklyEvents = monthlyEvents
        .where((event) => _isOnOrAfter(event.completedAt, weeklyStart))
        .toList();
    final todayEvents = weeklyEvents
        .where((event) => _isOnOrAfter(event.completedAt, todayStart))
        .toList();

    final weeklyMinutes = _sumMinutes(
      weeklyEvents,
      assignedModules: assignedModules,
      assignedTemplates: assignedTemplates,
      customActivities: customActivities,
    );
    final monthlyMinutes = _sumMinutes(
      monthlyEvents,
      assignedModules: assignedModules,
      assignedTemplates: assignedTemplates,
      customActivities: customActivities,
    );

    final weeklyMove = _progressForCategory(
      key: 'move_play',
      events: weeklyEvents,
      assignedModules: assignedModules,
    );
    final weeklyTalk = _progressForCategory(
      key: 'speak_learn',
      events: weeklyEvents,
      assignedModules: assignedModules,
    );
    final weeklyFocus = _progressForCategory(
      key: 'focus_games',
      events: weeklyEvents,
      assignedModules: assignedModules,
    );

    final monthlyMove = _progressForCategory(
      key: 'move_play',
      events: monthlyEvents,
      assignedModules: assignedModules,
    );
    final monthlyTalk = _progressForCategory(
      key: 'speak_learn',
      events: monthlyEvents,
      assignedModules: assignedModules,
    );
    final monthlyFocus = _progressForCategory(
      key: 'focus_games',
      events: monthlyEvents,
      assignedModules: assignedModules,
    );

    final mood = _resolveMood(
      moods: moodLogs,
      events: weeklyEvents.isNotEmpty ? weeklyEvents : monthlyEvents,
    );

    // --- New metrics ---
    final streakDays = _computeStreak(activityEvents, today: generatedAt);

    // Daily activities completed today (source: 'daily_activity' or matching assigned template/custom IDs)
    final assignedDailyIds = <String>{
      for (final t in assignedTemplates) t.id,
      for (final c in customActivities) c.id,
    };
    final dailyActivitiesToday = _countDailyActivitiesToday(
      todayEvents,
      assignedDailyIds: assignedDailyIds,
    );
    final dailyActivitiesTotal = totalDailyActivitiesAssigned > 0
        ? totalDailyActivitiesAssigned
        : assignedDailyIds.length;

    // Communication taps this week: unique item IDs whose source is aac_sentence
    final communicationTapsThisWeek = _countCommunicationTaps(weeklyEvents);

    final weeklyHours = weeklyMinutes / 60.0;
    final monthlyHours = monthlyMinutes / 60.0;
    final weeklyRecommendations = _recommendations(
      move: weeklyMove,
      talk: weeklyTalk,
      focus: weeklyFocus,
      hours: weeklyHours,
    );
    final monthlyRecommendations = _recommendations(
      move: monthlyMove,
      talk: monthlyTalk,
      focus: monthlyFocus,
      hours: monthlyHours,
    );

    return DashboardMetrics(
      childId: childId,
      completedActivities: _countUniqueActivities(weeklyEvents),
      weeklyMinutes: weeklyMinutes,
      monthlyCompletedActivities: _countUniqueActivities(monthlyEvents),
      monthlyMinutes: monthlyMinutes,
      activityLevel: _activityLevel(weeklyMinutes),
      moodLabel: mood,
      movePlayProgress: weeklyMove,
      talkExpressProgress: weeklyTalk,
      focusGamesProgress: weeklyFocus,
      streakDays: streakDays,
      dailyActivitiesToday: dailyActivitiesToday,
      dailyActivitiesTotal: dailyActivitiesTotal,
      communicationTapsThisWeek: communicationTapsThisWeek,
      weeklyReport: DashboardReport(
        title: 'Weekly Progress Report',
        dateLabel: _formatDate(generatedAt),
        summarySubtitle: 'Progress',
        summaryText:
            'Great job! You are on a $streakDays day learning streak! In the last $_weeklyWindowDays days, ${weeklyEvents.length} activities were completed with ${weeklyHours.toStringAsFixed(1)} hours of learning.',
        sections: [
          _section(
            title: 'Move & Play',
            progressValue: weeklyMove,
            detail:
                'Motor and play routines are tracking ${_percentText(weeklyMove)} this week.',
          ),
          _section(
            title: 'Talk & Express',
            progressValue: weeklyTalk,
            detail:
                'Speech and expression targets are tracking ${_percentText(weeklyTalk)} this week. $communicationTapsThisWeek unique vocabulary items were practiced.',
          ),
          _section(
            title: 'Focus Games',
            progressValue: weeklyFocus,
            detail:
                'Attention and focus activities are tracking ${_percentText(weeklyFocus)} this week.',
          ),
        ],
        recommendations: weeklyRecommendations,
      ),
      monthlyReport: DashboardReport(
        title: 'Monthly Assessment',
        dateLabel: _formatDate(generatedAt),
        summarySubtitle: 'Assessment',
        summaryText:
            'Consistent effort! You are currently on a $streakDays day learning streak. In the last $_monthlyWindowDays days, ${monthlyEvents.length} activities were completed with ${monthlyHours.toStringAsFixed(1)} hours of learning.',
        sections: [
          _section(
            title: 'Move & Play',
            progressValue: monthlyMove,
            detail:
                'Motor and play routines are tracking ${_percentText(monthlyMove)} this month.',
          ),
          _section(
            title: 'Talk & Express',
            progressValue: monthlyTalk,
            detail:
                'Speech and expression targets are tracking ${_percentText(monthlyTalk)} this month. Consistent daily communication is key.',
          ),
          _section(
            title: 'Focus Games',
            progressValue: monthlyFocus,
            detail:
                'Attention and focus activities are tracking ${_percentText(monthlyFocus)} this month.',
          ),
        ],
        recommendations: monthlyRecommendations,
      ),
      generatedAt: generatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Streak computation
  // ---------------------------------------------------------------------------

  /// Returns how many consecutive calendar days (ending today or yesterday)
  /// had at least one completed activity event.
  int _computeStreak(
    List<ActivityProgressEntry> allEvents, {
    required DateTime today,
  }) {
    if (allEvents.isEmpty) return 0;

    // Build a set of calendar day strings that have at least one event.
    final activeDays = <String>{};
    for (final event in allEvents) {
      final dt = event.completedAt;
      if (dt == null) continue;
      activeDays.add(_dayKey(dt));
    }

    // Walk backwards from today counting consecutive active days.
    var streak = 0;
    var cursor = DateTime(today.year, today.month, today.day);

    while (true) {
      if (activeDays.contains(_dayKey(cursor))) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        // Allow a one-day gap only at the start (today might have no events yet)
        if (streak == 0) {
          // Today has no activity — check yesterday before giving up
          cursor = cursor.subtract(const Duration(days: 1));
          if (activeDays.contains(_dayKey(cursor))) {
            streak += 1;
            cursor = cursor.subtract(const Duration(days: 1));
          } else {
            break;
          }
        } else {
          break;
        }
      }
    }
    return streak;
  }

  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Daily activity count helpers
  // ---------------------------------------------------------------------------

  int _countDailyActivitiesToday(
    List<ActivityProgressEntry> todayEvents, {
    required Set<String> assignedDailyIds,
  }) {
    // Count unique itemIds from today that are either:
    //   (a) in the assigned daily IDs set, or
    //   (b) have source == 'daily_activity' in their metadata (future-proofing)
    final completed = <String>{};
    for (final event in todayEvents) {
      final itemId = event.itemId.trim();
      if (assignedDailyIds.contains(itemId)) {
        completed.add(itemId);
      }
    }
    return completed.length;
  }

  int _countCommunicationTaps(List<ActivityProgressEntry> weeklyEvents) {
    // Communication events: moduleId matches a board keyword and itemId is a vocab item id.
    // We count unique itemIds that belong to the speak_learn category.
    return weeklyEvents
        .where(
          (event) =>
              _categoryForEvent(event) == 'speak_learn' &&
              !_isLevelEvent(event.itemId.trim()),
        )
        .map((event) => event.itemId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  // ---------------------------------------------------------------------------
  // Section builder
  // ---------------------------------------------------------------------------

  DashboardReportSection _section({
    required String title,
    required double progressValue,
    required String detail,
  }) {
    return DashboardReportSection(
      title: title,
      progressValue: progressValue,
      body: detail,
      statusLabel: _statusLabel(progressValue),
    );
  }

  // ---------------------------------------------------------------------------
  // Minutes summation (now includes custom activities)
  // ---------------------------------------------------------------------------

  int _sumMinutes(
    List<ActivityProgressEntry> events, {
    required List<LearningModuleModel> assignedModules,
    required List<DailyActivityTemplate> assignedTemplates,
    List<CustomDailyActivity> customActivities = const <CustomDailyActivity>[],
  }) {
    final templateMinutesById = <String, int>{
      for (final template in assignedTemplates)
        template.id: template.estimatedMinutes > 0
            ? template.estimatedMinutes
            : _fallbackMinutes,
      // Also map custom activities by their ID
      for (final custom in customActivities)
        custom.id: custom.durationMinutes > 0
            ? custom.durationMinutes
            : _fallbackMinutes,
    };
    final moduleMinutesById = <String, int>{};
    for (final module in assignedModules) {
      final minutes = assignedTemplates
          .where((template) => template.moduleRefs.contains(module.id))
          .map((template) => template.estimatedMinutes)
          .where((minutes) => minutes > 0)
          .toList();
      if (minutes.isNotEmpty) {
        final total = minutes.reduce((a, b) => a + b);
        moduleMinutesById[module.id] = (total / minutes.length).round();
      } else {
        moduleMinutesById[module.id] = _defaultModuleMinutes;
      }
    }

    final moduleCategoryById = <String, String>{
      for (final module in assignedModules)
        module.id.trim(): _normalizeKey(module.learningCategoryKey),
    };

    var totalMinutes = 0.0;
    for (final event in events) {
      final moduleId = (event.moduleId ?? '').trim();
      final itemId = event.itemId.trim();
      if (_isLevelEvent(itemId)) {
        totalMinutes += _gameLevelMinutes;
        continue;
      }
      if (moduleId.isNotEmpty && templateMinutesById.containsKey(moduleId)) {
        totalMinutes += templateMinutesById[moduleId]!.toDouble();
        continue;
      }
      if (itemId.isNotEmpty && templateMinutesById.containsKey(itemId)) {
        totalMinutes += templateMinutesById[itemId]!.toDouble();
        continue;
      }
      if (moduleId.isNotEmpty && moduleMinutesById.containsKey(moduleId)) {
        totalMinutes += moduleMinutesById[moduleId]!.toDouble();
        continue;
      }
      if (itemId.isNotEmpty && moduleMinutesById.containsKey(itemId)) {
        totalMinutes += moduleMinutesById[itemId]!.toDouble();
        continue;
      }
      totalMinutes += _estimatedMinutesForUnmappedEvent(
        event,
        moduleCategoryById: moduleCategoryById,
      );
    }
    if (totalMinutes <= 0) {
      return 0;
    }
    return totalMinutes.ceil();
  }

  // ---------------------------------------------------------------------------
  // Category progress
  // ---------------------------------------------------------------------------

  double _progressForCategory({
    required String key,
    required List<ActivityProgressEntry> events,
    required List<LearningModuleModel> assignedModules,
  }) {
    final normalizedKey = _normalizeKey(key);
    final categoryModules = assignedModules
        .where(
          (module) =>
              _normalizeKey(module.learningCategoryKey) == normalizedKey,
        )
        .toList();

    final categoryEvents = events
        .where(
          (event) =>
              _categoryForEvent(event, assignedModules: assignedModules) ==
              normalizedKey,
        )
        .toList();
    final uniqueEngagementCount = categoryEvents
        .map(
          (event) =>
              _engagementUnitKey(event, categoryKey: normalizedKey) ??
              event.id.trim(),
        )
        .where((key) => key.isNotEmpty)
        .toSet()
        .length;

    final engagementProgress = _engagementProgress(
      categoryKey: normalizedKey,
      eventCount: uniqueEngagementCount,
    );

    if (categoryModules.isEmpty) {
      return engagementProgress;
    }

    final completedIds = <String>{};
    for (final event in categoryEvents) {
      final moduleId = event.moduleId?.trim();
      if (moduleId != null && moduleId.isNotEmpty) {
        completedIds.add(moduleId);
      }
      if (event.itemId.trim().isNotEmpty) {
        completedIds.add(event.itemId.trim());
      }
    }
    var completedCount = 0;
    for (final module in categoryModules) {
      if (completedIds.contains(module.id)) {
        completedCount += 1;
      }
    }
    final moduleCoverage = completedCount / categoryModules.length;
    final blended =
        (moduleCoverage * _moduleCoverageWeight) +
        (engagementProgress * _engagementWeight);
    return _clamp01(blended);
  }

  double _estimatedMinutesForUnmappedEvent(
    ActivityProgressEntry event, {
    required Map<String, String> moduleCategoryById,
  }) {
    if (_isLevelEvent(event.itemId.trim())) {
      return _gameLevelMinutes;
    }
    final category = _categoryForEvent(
      event,
      moduleCategoryById: moduleCategoryById,
    );
    if (category == 'speak_learn') {
      return _communicationTapMinutes;
    }
    if (category == 'move_play' || category == 'focus_games') {
      return _gameSessionMinutes;
    }
    return _fallbackMinutes.toDouble();
  }

  String? _categoryForEvent(
    ActivityProgressEntry event, {
    List<LearningModuleModel> assignedModules = const <LearningModuleModel>[],
    Map<String, String> moduleCategoryById = const <String, String>{},
  }) {
    final localModuleCategoryById = moduleCategoryById.isNotEmpty
        ? moduleCategoryById
        : <String, String>{
            for (final module in assignedModules)
              module.id.trim(): _normalizeKey(module.learningCategoryKey),
          };
    final moduleId = (event.moduleId ?? '').trim();
    if (moduleId.isNotEmpty && localModuleCategoryById.containsKey(moduleId)) {
      return localModuleCategoryById[moduleId];
    }

    final raw = '${event.itemId} ${event.moduleId ?? ''}'.toLowerCase();

    if (_matchesAny(raw, _talkEventKeywords)) {
      return 'speak_learn';
    }
    if (_matchesAny(raw, _moveEventKeywords)) {
      return 'move_play';
    }
    if (_matchesAny(raw, _focusEventKeywords)) {
      return 'focus_games';
    }
    return null;
  }

  bool _matchesAny(String raw, Set<String> needles) {
    for (final needle in needles) {
      if (raw.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  double _engagementProgress({
    required String categoryKey,
    required int eventCount,
  }) {
    if (eventCount <= 0) {
      return 0;
    }
    final target = switch (categoryKey) {
      'speak_learn' => 12,
      'move_play' => 8,
      'focus_games' => 8,
      _ => 10,
    };
    final ratio = eventCount / target;
    return _clamp01(ratio);
  }

  int _countUniqueActivities(List<ActivityProgressEntry> events) {
    final units = events
        .map(_activityUnitKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    return units.length;
  }

  String _activityUnitKey(ActivityProgressEntry event) {
    final itemId = event.itemId.trim().toLowerCase();
    if (itemId.isNotEmpty) {
      return itemId;
    }
    final moduleId = (event.moduleId ?? '').trim().toLowerCase();
    if (moduleId.isNotEmpty) {
      return moduleId;
    }
    return event.id.trim().toLowerCase();
  }

  String? _engagementUnitKey(
    ActivityProgressEntry event, {
    required String categoryKey,
  }) {
    final itemId = event.itemId.trim().toLowerCase();
    final moduleId = (event.moduleId ?? '').trim().toLowerCase();
    if (categoryKey == 'speak_learn') {
      if (itemId.isNotEmpty) {
        return itemId;
      }
      if (moduleId.isNotEmpty) {
        return moduleId;
      }
      return null;
    }
    if (_isLevelEvent(itemId)) {
      return itemId;
    }
    if (moduleId.isNotEmpty) {
      return moduleId;
    }
    if (itemId.isNotEmpty) {
      return itemId;
    }
    return null;
  }

  bool _isLevelEvent(String itemId) {
    return itemId.toLowerCase().contains('-level-');
  }

  double _clamp01(double value) => math.min(1.0, math.max(0.0, value));

  // Keywords for category detection — extended with explicit game-type names
  static const Set<String> _talkEventKeywords = <String>{
    'speak',
    'talk',
    'express',
    'alphabet',
    'word',
    'sentence',
    'letter-',
    'color-',
    'num-',
    'animal-',
    'emotion-',
    'cloth-',
    'family-',
    'food-',
    'shape-',
    'emergency-',
    'colors',
    'numbers',
    'animals',
    'feelings',
    'alphabets',
    'clothes',
    'family',
    'food',
    'shapes',
    'emotions',
    'emergency',
    'aac_sentence',
    'speak_learn',
  };

  static const Set<String> _moveEventKeywords = <String>{
    'move',
    'play',
    'motor',
    'tap',
    'drag',
    'trace',
    'tracing',
    'tap_game',
    'drag_game',
    'trace_game',
    'move_play',
  };

  static const Set<String> _focusEventKeywords = <String>{
    'focus',
    'find',
    'match',
    'hold',
    'attention',
    'find_it',
    'match_it',
    'hold_it',
    'focus_game',
    'focus_games',
    'findit',
    'matchit',
    'holdit',
  };

  // ---------------------------------------------------------------------------
  // Mood resolution
  // ---------------------------------------------------------------------------

  String _resolveMood({
    required List<MoodLogEntry> moods,
    required List<ActivityProgressEntry> events,
  }) {
    final normalizedMoods =
        moods.where((entry) => entry.emotion.trim().isNotEmpty).toList()
          ..sort((a, b) {
            final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
    if (normalizedMoods.isNotEmpty) {
      return _normalizeMoodLabel(normalizedMoods.first.emotion);
    }

    final sortedEvents = [...events]
      ..sort((a, b) {
        final left = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    for (final event in sortedEvents) {
      final merged = '${event.itemId} ${event.moduleId ?? ''}'.toLowerCase();
      if (merged.contains('happy')) {
        return 'Happy';
      }
      if (merged.contains('sad')) {
        return 'Sad';
      }
      if (merged.contains('angry') || merged.contains('mad')) {
        return 'Angry';
      }
      if (merged.contains('serious') || merged.contains('focused')) {
        return 'Serious';
      }
      if (merged.contains('emotion') || merged.contains('feeling')) {
        return 'Engaged';
      }
    }
    return 'Not set';
  }

  String _normalizeMoodLabel(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return 'Not set';
    }
    if (lower.contains('happy')) {
      return 'Happy';
    }
    if (lower.contains('sad')) {
      return 'Sad';
    }
    if (lower.contains('angry') || lower.contains('mad')) {
      return 'Angry';
    }
    if (lower.contains('serious')) {
      return 'Serious';
    }
    if (lower.contains('excited')) {
      return 'Excited';
    }
    if (lower.contains('calm')) {
      return 'Calm';
    }
    return _titleCase(lower);
  }

  String _activityLevel(int weeklyMinutes) {
    if (weeklyMinutes < 120) {
      return 'Low';
    }
    if (weeklyMinutes < 300) {
      return 'Medium';
    }
    return 'High';
  }

  List<String> _recommendations({
    required double move,
    required double talk,
    required double focus,
    required double hours,
  }) {
    final recommendations = <String>[];
    if (talk < 0.5) {
      recommendations.add(
        'Schedule short daily Talk & Express sessions to improve communication consistency.',
      );
    }
    if (move < 0.5) {
      recommendations.add(
        'Increase Move & Play practice with one guided motor game each day.',
      );
    }
    if (focus < 0.5) {
      recommendations.add(
        'Add brief Focus Games blocks with breaks to improve attention endurance.',
      );
    }
    if (hours < 2.0) {
      recommendations.add(
        'Aim for at least 15-20 minutes of learning activities every day this week.',
      );
    }
    if (recommendations.isEmpty) {
      recommendations.add(
        'Maintain current routine and gradually increase challenge across all modules.',
      );
      recommendations.add(
        'Review Learning Planner weekly to keep activities aligned with progress.',
      );
    }
    return recommendations.take(4).toList();
  }

  String _statusLabel(double progress) {
    if (progress >= 0.8) {
      return 'Excellent Progress';
    }
    if (progress >= 0.6) {
      return 'Good Progress';
    }
    if (progress >= 0.35) {
      return 'Needs Support';
    }
    return 'Needs Improvement';
  }

  String _percentText(double value) => '${(value * 100).round()}%';

  bool _isOnOrAfter(DateTime? value, DateTime threshold) {
    if (value == null) {
      return false;
    }
    return !value.isBefore(threshold);
  }

  String _normalizeKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1).toLowerCase() : ''}',
        )
        .join(' ');
  }

  String _formatDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
