import '../repositories/app_repositories.dart';

enum ParentDifficulty { easy, normal, challenge }

extension ParentDifficultyX on ParentDifficulty {
  String get key => switch (this) {
    ParentDifficulty.easy => 'easy',
    ParentDifficulty.normal => 'normal',
    ParentDifficulty.challenge => 'challenge',
  };

  String get label => switch (this) {
    ParentDifficulty.easy => 'Easy',
    ParentDifficulty.normal => 'Normal',
    ParentDifficulty.challenge => 'Challenge',
  };

  int get baseDelta => switch (this) {
    ParentDifficulty.easy => -1,
    ParentDifficulty.normal => 0,
    ParentDifficulty.challenge => 1,
  };

  static ParentDifficulty fromKey(String? key) {
    return switch ((key ?? '').trim().toLowerCase()) {
      'easy' => ParentDifficulty.easy,
      'challenge' || 'hard' => ParentDifficulty.challenge,
      _ => ParentDifficulty.normal,
    };
  }
}

class PlayPreferences {
  const PlayPreferences({
    required this.difficulty,
    required this.lowStimulationMode,
  });

  static const defaults = PlayPreferences(
    difficulty: ParentDifficulty.normal,
    lowStimulationMode: false,
  );

  final ParentDifficulty difficulty;
  final bool lowStimulationMode;

  factory PlayPreferences.fromMap(Map<String, dynamic> data) {
    return PlayPreferences(
      difficulty: ParentDifficultyX.fromKey(data['difficulty']?.toString()),
      lowStimulationMode:
          data['lowStimulationMode'] == true || data['sensoryFriendly'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'difficulty': difficulty.key,
      'lowStimulationMode': lowStimulationMode,
    };
  }

  PlayPreferences copyWith({
    ParentDifficulty? difficulty,
    bool? lowStimulationMode,
  }) {
    return PlayPreferences(
      difficulty: difficulty ?? this.difficulty,
      lowStimulationMode: lowStimulationMode ?? this.lowStimulationMode,
    );
  }

  int adaptiveDelta({required int wrongAttempts, required int successCount}) {
    var delta = difficulty.baseDelta;
    if (wrongAttempts >= 2) {
      delta -= 1;
    } else if (wrongAttempts == 0 && successCount > 0) {
      delta += 1;
    }
    if (lowStimulationMode && delta > -1) {
      delta -= 1;
    }
    return delta.clamp(-2, 2).toInt();
  }

  int choiceCountForRound(int roundIndex, {int min = 2, int max = 5}) {
    final base = switch (difficulty) {
      ParentDifficulty.easy => 2 + (roundIndex > 1 ? 1 : 0),
      ParentDifficulty.normal => 3 + (roundIndex > 0 ? 1 : 0),
      ParentDifficulty.challenge => 4 + (roundIndex > 0 ? 1 : 0),
    };
    final adjusted = lowStimulationMode ? base - 1 : base;
    return adjusted.clamp(min, max).toInt();
  }

  int holdSeconds({
    required int baseSeconds,
    required int wrongAttempts,
    required int successCount,
  }) {
    final difficultyBase = switch (difficulty) {
      ParentDifficulty.easy => 3,
      ParentDifficulty.normal => baseSeconds.clamp(5, 7).toInt(),
      ParentDifficulty.challenge => (baseSeconds + 1).clamp(7, 9).toInt(),
    };
    var seconds = difficultyBase;
    if (wrongAttempts >= 2) {
      seconds -= 1;
    } else if (wrongAttempts == 0 && successCount > 1) {
      seconds += 1;
    }
    if (lowStimulationMode) {
      seconds -= 1;
    }
    return seconds.clamp(3, 9).toInt();
  }
}

class PlayPreferencesService {
  const PlayPreferencesService();

  Future<PlayPreferences> getCurrent() async {
    final profile = await AppRepositories.users.getCurrentUserProfile();
    if (profile == null) {
      return PlayPreferences.defaults;
    }
    return PlayPreferences.fromMap(profile.playSettings);
  }

  Future<void> save(PlayPreferences preferences) async {
    await AppRepositories.users.updateCurrentUser({
      'playSettings': preferences.toMap(),
    });
  }
}
