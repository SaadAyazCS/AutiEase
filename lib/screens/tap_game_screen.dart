import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/learning_metrics_service.dart';
import '../services/play_preferences_service.dart';
import '../services/tts_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/move_play_celebration.dart';
import '../widgets/move_play_feedback.dart';
import '../widgets/session_guard.dart';

class TapGameScreen extends StatefulWidget {
  const TapGameScreen({super.key, required this.childId, required this.module});

  final String childId;
  final LearningModuleModel module;

  @override
  State<TapGameScreen> createState() => _TapGameScreenState();
}

enum _TapGameStage { playing, celebration }

class _TapGameScreenState extends State<TapGameScreen> {
  static const _slots = <Offset>[
    Offset(26, 20),
    Offset(190, 36),
    Offset(104, 104),
    Offset(26, 196),
    Offset(178, 204),
  ];
  static const _levels = <_TapLevel>[
    _TapLevel(
      prompt: 'Circle',
      options: <_TapOption>[
        _TapOption(
          key: 'triangle',
          label: 'Triangle',
          kind: _TapOptionKind.icon,
          icon: Icons.change_history_rounded,
          color: Color(0xFF5DAA2A),
          left: 26,
          top: 20,
        ),
        _TapOption(
          key: 'rectangle',
          label: 'Rectangle',
          kind: _TapOptionKind.icon,
          icon: Icons.rectangle_rounded,
          color: Color(0xFFFF0E8A),
          left: 190,
          top: 36,
        ),
        _TapOption(
          key: 'star',
          label: 'Star',
          kind: _TapOptionKind.icon,
          icon: Icons.star_rounded,
          color: Color(0xFFF7C926),
          left: 104,
          top: 104,
        ),
        _TapOption(
          key: 'heart',
          label: 'Heart',
          kind: _TapOptionKind.icon,
          icon: Icons.favorite_rounded,
          color: Color(0xFFE36BA7),
          left: 26,
          top: 196,
        ),
        _TapOption(
          key: 'circle',
          label: 'Circle',
          kind: _TapOptionKind.icon,
          icon: Icons.circle_rounded,
          color: Color(0xFFF14D4D),
          left: 178,
          top: 204,
        ),
      ],
    ),
    _TapLevel(
      prompt: 'Apple',
      options: <_TapOption>[
        _TapOption(
          key: 'banana',
          label: 'Banana',
          kind: _TapOptionKind.emoji,
          emoji: '🍌',
          left: 70,
          top: 36,
        ),
        _TapOption(
          key: 'watermelon',
          label: 'Watermelon',
          kind: _TapOptionKind.emoji,
          emoji: '🍉',
          left: 194,
          top: 68,
        ),
        _TapOption(
          key: 'grapes',
          label: 'Grapes',
          kind: _TapOptionKind.emoji,
          emoji: '🍇',
          left: 104,
          top: 142,
        ),
        _TapOption(
          key: 'apple',
          label: 'Apple',
          kind: _TapOptionKind.emoji,
          emoji: '🍎',
          left: 48,
          top: 240,
        ),
        _TapOption(
          key: 'lemon',
          label: 'Lemon',
          kind: _TapOptionKind.emoji,
          emoji: '🍋',
          left: 194,
          top: 240,
        ),
      ],
    ),
    _TapLevel(
      prompt: '2',
      options: <_TapOption>[
        _TapOption(
          key: '1',
          label: '1',
          kind: _TapOptionKind.number,
          numberText: '1',
          color: Color(0xFF59B086),
          left: 162,
          top: 42,
        ),
        _TapOption(
          key: '5',
          label: '5',
          kind: _TapOptionKind.number,
          numberText: '5',
          color: Color(0xFFE9B126),
          left: 96,
          top: 86,
        ),
        _TapOption(
          key: '9',
          label: '9',
          kind: _TapOptionKind.number,
          numberText: '9',
          color: Color(0xFFEF5755),
          left: 128,
          top: 190,
        ),
        _TapOption(
          key: '2',
          label: '2',
          kind: _TapOptionKind.number,
          numberText: '2',
          color: Color(0xFFF58436),
          left: 228,
          top: 182,
        ),
        _TapOption(
          key: '3',
          label: '3',
          kind: _TapOptionKind.number,
          numberText: '3',
          color: Color(0xFFF7746A),
          left: 28,
          top: 262,
        ),
      ],
    ),
    _TapLevel(
      prompt: 'Tap all fruits',
      correctKeys: <String>['apple', 'banana', 'grapes'],
      hint: 'Look for the fruit emojis.',
      options: <_TapOption>[
        _TapOption(
          key: 'apple',
          label: 'Apple',
          kind: _TapOptionKind.emoji,
          emoji: '🍎',
          left: 36,
          top: 40,
        ),
        _TapOption(
          key: 'car',
          label: 'Car',
          kind: _TapOptionKind.emoji,
          emoji: '🚗',
          left: 186,
          top: 48,
        ),
        _TapOption(
          key: 'banana',
          label: 'Banana',
          kind: _TapOptionKind.emoji,
          emoji: '🍌',
          left: 94,
          top: 140,
        ),
        _TapOption(
          key: 'grapes',
          label: 'Grapes',
          kind: _TapOptionKind.emoji,
          emoji: '🍇',
          left: 36,
          top: 244,
        ),
        _TapOption(
          key: 'book',
          label: 'Book',
          kind: _TapOptionKind.emoji,
          emoji: '📘',
          left: 194,
          top: 244,
        ),
      ],
    ),
    _TapLevel(
      prompt: 'Tap only red things',
      correctKeys: <String>['red-circle', 'apple'],
      hint: 'Look for the red objects.',
      options: <_TapOption>[
        _TapOption(
          key: 'red-circle',
          label: 'Red circle',
          kind: _TapOptionKind.icon,
          icon: Icons.circle_rounded,
          color: Color(0xFFF14D4D),
          left: 36,
          top: 40,
        ),
        _TapOption(
          key: 'blue-circle',
          label: 'Blue circle',
          kind: _TapOptionKind.icon,
          icon: Icons.circle_rounded,
          color: Color(0xFF4EA9E3),
          left: 190,
          top: 50,
        ),
        _TapOption(
          key: 'apple',
          label: 'Apple',
          kind: _TapOptionKind.emoji,
          emoji: '🍎',
          left: 104,
          top: 150,
        ),
        _TapOption(
          key: 'banana',
          label: 'Banana',
          kind: _TapOptionKind.emoji,
          emoji: '🍌',
          left: 38,
          top: 250,
        ),
        _TapOption(
          key: 'green-square',
          label: 'Green square',
          kind: _TapOptionKind.icon,
          icon: Icons.square_rounded,
          color: Color(0xFF59B086),
          left: 196,
          top: 252,
        ),
      ],
    ),
    _TapLevel(
      prompt: 'Tap the bigger object',
      correctKeys: <String>['big-star'],
      hint: 'Look for the bigger star.',
      options: <_TapOption>[
        _TapOption(
          key: 'small-star',
          label: 'Small star',
          kind: _TapOptionKind.icon,
          icon: Icons.star_rounded,
          color: Color(0xFFF7C926),
          scale: 0.72,
          left: 60,
          top: 92,
        ),
        _TapOption(
          key: 'big-star',
          label: 'Big star',
          kind: _TapOptionKind.icon,
          icon: Icons.star_rounded,
          color: Color(0xFFF7C926),
          scale: 1.22,
          left: 190,
          top: 180,
        ),
      ],
    ),
  ];

  int _levelIndex = 0;
  _TapGameStage _stage = _TapGameStage.playing;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;
  final Set<int> _recordedLevelNumbers = <int>{};
  int _starsEarned = 0;
  int _wrongAttemptsThisLevel = 0;
  final Set<String> _completedTargets = <String>{};
  PlayPreferences _playPreferences = PlayPreferences.defaults;
  final PlayPreferencesService _playPreferencesService =
      const PlayPreferencesService();
  final LearningMetricsService _metricsService = const LearningMetricsService();
  final GameplayMetricsTracker _metricsTracker = GameplayMetricsTracker();

  final TtsService _tts = TtsService();
  bool _showFeedback = false;
  MovePlayFeedbackKind _feedbackKind = MovePlayFeedbackKind.mistake;
  bool _pendingAdvance = false;
  int _shuffleSeed = 0;
  late List<_TapOption> _activeOptions;

  _TapLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    return _stage == _TapGameStage.playing ? _instructionText() : 'Great Job!';
  }

  @override
  void initState() {
    super.initState();
    _activeOptions = _shuffledOptionsForLevel();
    _initTtsAndSpeak();
  }

  Future<void> _initTtsAndSpeak() async {
    await _tts.init();
    final playPreferences = await _playPreferencesService.getCurrent();
    if (!mounted) return;
    setState(() {
      _playPreferences = playPreferences;
      _activeOptions = _shuffledOptionsForLevel();
    });
    _speakInstruction();
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  String _instructionText() {
    final raw = _currentLevel.prompt.trim();
    if (_currentLevel.isMultiTarget) {
      return raw;
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('tap ')) {
      return raw;
    }
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      return 'Tap on number $raw';
    }
    if (lower == 'apple' ||
        lower == 'banana' ||
        lower == 'grapes' ||
        lower == 'watermelon' ||
        lower == 'lemon') {
      return 'Tap on the $lower';
    }
    return 'Tap on the $lower';
  }

  void _speakInstruction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _TapGameStage.playing) return;
      _tts.speak(_title);
    });
  }

  void _showOverlay(MovePlayFeedbackKind kind) {
    if (_showFeedback) return;
    setState(() {
      _showFeedback = true;
      _feedbackKind = kind;
    });
  }

  Future<void> _handleTap(_TapOption option) async {
    if (_stage != _TapGameStage.playing || _showFeedback) {
      return;
    }

    _metricsTracker.markAttempt(
      wrong: !_currentLevel.targets.contains(option.key),
    );

    if (!_currentLevel.targets.contains(option.key)) {
      _wrongAttemptsThisLevel += 1;
      unawaited(_recordTapMetric(outcome: 'wrong'));
      _pendingAdvance = false;
      setState(() => _activeOptions = _shuffledOptionsForLevel());
      _showOverlay(MovePlayFeedbackKind.mistake);
      return;
    }

    _completedTargets.add(option.key);
    if (_currentLevel.isMultiTarget &&
        !_completedTargets.containsAll(_currentLevel.targets)) {
      setState(() {});
      return;
    }

    unawaited(_recordTapMetric(outcome: 'correct'));
    final completedLevel = _levelIndex + 1;
    _starsEarned += 1;
    await _recordLevelCompletion(completedLevel);
    _pendingAdvance = true;
    _showOverlay(MovePlayFeedbackKind.success);
  }

  Future<void> _recordLevelCompletion(int levelNumber) async {
    // Record per-round progress for analytics (no parent notification here).
    if (_recordedLevelNumbers.contains(levelNumber)) return;
    _recordedLevelNumbers.add(levelNumber);
    // Metrics-only: no score/notification — full game completion handles that.
  }

  Future<void> _saveProgressIfNeeded() async {
    if (_savedCompletion || _isSavingProgress) return;
    setState(() => _isSavingProgress = true);
    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: widget.module.id,
        moduleId: widget.module.id,
        score: _starsEarned * 100,
        metadata: {
          'source': 'tap_game',
          'gameName': widget.module.title,
        },
      );
      _savedCompletion = true;
    } finally {
      if (mounted) setState(() => _isSavingProgress = false);
    }
  }

  Future<void> _recordTapMetric({required String outcome}) {
    return _metricsService.recordGameplayMetric(
      childId: widget.childId,
      gameType: 'tap_game',
      moduleId: widget.module.id,
      roundId: 'tap-${_levelIndex + 1}',
      outcome: outcome,
      attempts: _metricsTracker.attempts,
      wrongSelections: _metricsTracker.wrongSelections,
      responseTimeMs: _metricsTracker.responseTimeMs,
      difficulty: _playPreferences.difficulty,
      lowStimulationMode: _playPreferences.lowStimulationMode,
      adaptiveLevel: _adaptiveChoiceDelta,
      metadata: {
        'prompt': _currentLevel.prompt,
        'targets': _currentLevel.targets.toList(),
      },
    );
  }

  int get _adaptiveChoiceDelta => _playPreferences.adaptiveDelta(
    wrongAttempts: _wrongAttemptsThisLevel,
    successCount: _starsEarned,
  );

  String get _wrongHint =>
      _currentLevel.hint ?? 'Nice try. Look for ${_currentLevel.prompt}.';

  void _replayAll() {
    setState(() {
      _levelIndex = 0;
      _starsEarned = 0;
      _wrongAttemptsThisLevel = 0;
      _completedTargets.clear();
      _metricsTracker.reset();
      _showFeedback = false;
      _savedCompletion = false;
      _stage = _TapGameStage.playing;
      _shuffleSeed++;
      _activeOptions = _shuffledOptionsForLevel();
    });
    _speakInstruction();
  }

  void _goBackToMoveAndPlay() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    if (_stage == _TapGameStage.celebration) {
      return SessionGuard(
        role: SessionGuardRole.parent,
        child: MovePlayCelebration(
          title: 'You superstar!',
          subtitle: 'You finished all Tap rounds. High five!',
          starsEarned: _starsEarned,
          starsTotal: _levels.length,
          badgeLabel: 'Bronze Badge',
          trophyColor: const Color(0xFFCD7F32),
          replayLabel: 'Replay Tap Game',
          onReplay: _replayAll,
          onBack: _goBackToMoveAndPlay,
          lowStimulationMode: _playPreferences.lowStimulationMode,
        ),
      );
    }

    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: _title,
        onBack: () => Navigator.pop(context),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        _TapLevelBoard(
          level: _currentLevel,
          options: _activeOptions,
          completedTargets: _completedTargets,
          pulseTarget:
              _wrongAttemptsThisLevel >= 2 &&
              !_playPreferences.lowStimulationMode,
          onTapOption: _handleTap,
        ),
        if (_showFeedback)
          MovePlayFeedbackOverlay(
            kind: _feedbackKind,
            primaryLabel: _feedbackKind == MovePlayFeedbackKind.success
                ? 'Next'
                : 'Try again',
            message: _feedbackKind == MovePlayFeedbackKind.mistake
                ? _wrongHint
                : null,
            lowStimulationMode: _playPreferences.lowStimulationMode,
            onPrimaryAction: () {
              if (!mounted) return;
              final kind = _feedbackKind;
              setState(() => _showFeedback = false);
              if (kind == MovePlayFeedbackKind.mistake) {
                _speakInstruction();
                return;
              }
              if (!_pendingAdvance) return;

              if (_levelIndex < _levels.length - 1) {
                setState(() {
                  _levelIndex += 1;
                  _wrongAttemptsThisLevel = 0;
                  _completedTargets.clear();
                  _metricsTracker.reset();
                  _shuffleSeed++;
                  _activeOptions = _shuffledOptionsForLevel();
                });
                _speakInstruction();
              } else {
                setState(() => _stage = _TapGameStage.celebration);
                unawaited(_saveProgressIfNeeded());
              }
            },
          ),
      ],
    );
  }

  List<_TapOption> _shuffledOptionsForLevel() {
    final slots = List<Offset>.from(_slots);
    final targets = _currentLevel.targets;
    final correct = _currentLevel.options
        .where((option) => targets.contains(option.key))
        .toList();
    final distractors = _currentLevel.options
        .where((option) => !targets.contains(option.key))
        .toList();
    final choiceCount = _playPreferences
        .choiceCountForRound(_levelIndex, min: correct.length, max: 5)
        .clamp(correct.length, _currentLevel.options.length)
        .toInt();
    final r = math.Random((_shuffleSeed * 997) ^ _levelIndex ^ _starsEarned);
    distractors.shuffle(r);
    final items = <_TapOption>[
      ...correct,
      ...distractors.take(choiceCount - correct.length),
    ];
    items.shuffle(r);
    for (var i = 0; i < items.length && i < slots.length; i++) {
      items[i] = items[i].copyWith(left: slots[i].dx, top: slots[i].dy);
    }
    return items;
  }
}

class _TapLevelBoard extends StatelessWidget {
  const _TapLevelBoard({
    required this.level,
    required this.options,
    required this.completedTargets,
    required this.pulseTarget,
    required this.onTapOption,
  });

  final _TapLevel level;
  final List<_TapOption> options;
  final Set<String> completedTargets;
  final bool pulseTarget;
  final void Function(_TapOption option) onTapOption;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 420,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final option in options)
              Positioned(
                left: option.left,
                top: option.top,
                child: GestureDetector(
                  onTap: () => onTapOption(option),
                  child: _TapOptionFrame(
                    highlight:
                        pulseTarget && level.targets.contains(option.key),
                    completed: completedTargets.contains(option.key),
                    child: _TapOptionView(option: option),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TapOptionView extends StatelessWidget {
  const _TapOptionView({required this.option});

  final _TapOption option;

  @override
  Widget build(BuildContext context) {
    final child = switch (option.kind) {
      _TapOptionKind.icon => Icon(option.icon!, size: 86, color: option.color),
      _TapOptionKind.emoji => Text(
        option.emoji!,
        style: const TextStyle(fontSize: 58),
      ),
      _TapOptionKind.number => Text(
        option.numberText!,
        style: TextStyle(
          fontSize: 82,
          fontWeight: FontWeight.w700,
          color: option.color,
        ),
      ),
    };
    return Transform.scale(scale: option.scale, child: child);
  }
}

class _TapOptionFrame extends StatefulWidget {
  const _TapOptionFrame({
    required this.child,
    required this.highlight,
    required this.completed,
  });

  final Widget child;
  final bool highlight;
  final bool completed;

  @override
  State<_TapOptionFrame> createState() => _TapOptionFrameState();
}

class _TapOptionFrameState extends State<_TapOptionFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final scale = widget.highlight ? 1 + _pulseCtrl.value * 0.07 : 1.0;
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: widget.completed ? 0.42 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: widget.highlight
                    ? Border.all(color: const Color(0xFFFFD447), width: 3)
                    : null,
                boxShadow: widget.highlight
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFFFD447,
                          ).withValues(alpha: 0.28),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Padding(padding: const EdgeInsets.all(4), child: child),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

enum _TapOptionKind { icon, emoji, number }

class _TapLevel {
  const _TapLevel({
    required this.prompt,
    required this.options,
    this.correctKeys,
    this.hint,
  });

  final String prompt;
  final List<_TapOption> options;
  final List<String>? correctKeys;
  final String? hint;

  Set<String> get targets =>
      (correctKeys ?? <String>[prompt.toLowerCase()]).toSet();

  bool get isMultiTarget => targets.length > 1;
}

class _TapOption {
  const _TapOption({
    required this.key,
    required this.label,
    required this.kind,
    required this.left,
    required this.top,
    this.icon,
    this.emoji,
    this.numberText,
    this.color = Colors.black,
    this.scale = 1,
  });

  final String key;
  final String label;
  final _TapOptionKind kind;
  final double left;
  final double top;
  final IconData? icon;
  final String? emoji;
  final String? numberText;
  final Color color;
  final double scale;

  _TapOption copyWith({double? left, double? top}) {
    return _TapOption(
      key: key,
      label: label,
      kind: kind,
      left: left ?? this.left,
      top: top ?? this.top,
      icon: icon,
      emoji: emoji,
      numberText: numberText,
      color: color,
      scale: scale,
    );
  }
}
