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

class DragGameScreen extends StatefulWidget {
  const DragGameScreen({
    super.key,
    required this.childId,
    required this.module,
  });

  final String childId;
  final LearningModuleModel module;

  @override
  State<DragGameScreen> createState() => _DragGameScreenState();
}

enum _DragGameStage { playing, celebration }

class _DragGameScreenState extends State<DragGameScreen> {
  static const _rnd = <int>[4021, 9137, 1193, 6619, 2879, 7711];
  static const _levels = <_DragLevel>[
    _DragLevel(
      prompt: 'Circle',
      answerKey: 'circle',
      target: _DragPiece(
        key: 'circle',
        kind: _DragPieceKind.icon,
        icon: Icons.circle_rounded,
        color: Color(0xFFF14D4D),
        left: 136,
        top: 18,
      ),
      options: <_DragPiece>[
        _DragPiece(
          key: 'triangle',
          kind: _DragPieceKind.icon,
          icon: Icons.change_history_outlined,
          color: Colors.black,
          left: 58,
          top: 144,
        ),
        _DragPiece(
          key: 'rectangle',
          kind: _DragPieceKind.icon,
          icon: Icons.rectangle_outlined,
          color: Colors.black,
          left: 196,
          top: 150,
        ),
        _DragPiece(
          key: 'star',
          kind: _DragPieceKind.icon,
          icon: Icons.star_outline_rounded,
          color: Colors.black,
          left: 128,
          top: 238,
        ),
        _DragPiece(
          key: 'heart',
          kind: _DragPieceKind.icon,
          icon: Icons.favorite_border_rounded,
          color: Colors.black,
          left: 56,
          top: 292,
        ),
        _DragPiece(
          key: 'circle',
          kind: _DragPieceKind.icon,
          icon: Icons.circle_outlined,
          color: Colors.black,
          left: 216,
          top: 326,
        ),
      ],
    ),
    _DragLevel(
      prompt: 'Sun',
      answerKey: 'sun',
      target: _DragPiece(
        key: 'sun',
        kind: _DragPieceKind.icon,
        icon: Icons.wb_sunny_rounded,
        color: Color(0xFFFFB300),
        left: 144,
        top: 18,
      ),
      options: <_DragPiece>[
        _DragPiece(
          key: 'cloud',
          kind: _DragPieceKind.icon,
          icon: Icons.cloud_outlined,
          color: Colors.black,
          left: 40,
          top: 150,
        ),
        _DragPiece(
          key: 'moon',
          kind: _DragPieceKind.icon,
          icon: Icons.nightlight_outlined,
          color: Colors.black,
          left: 196,
          top: 150,
        ),
        _DragPiece(
          key: 'rain',
          kind: _DragPieceKind.icon,
          icon: Icons.umbrella_outlined,
          color: Colors.black,
          left: 118,
          top: 244,
        ),
        _DragPiece(
          key: 'sun',
          kind: _DragPieceKind.icon,
          icon: Icons.wb_sunny_outlined,
          color: Colors.black,
          left: 52,
          top: 318,
        ),
        _DragPiece(
          key: 'flower',
          kind: _DragPieceKind.icon,
          icon: Icons.local_florist_outlined,
          color: Colors.black,
          left: 210,
          top: 318,
        ),
      ],
    ),
    _DragLevel(
      prompt: 'Number',
      answerKey: '2',
      target: _DragPiece(
        key: '2',
        kind: _DragPieceKind.number,
        numberText: '2',
        color: Color(0xFFF58436),
        left: 154,
        top: 8,
      ),
      options: <_DragPiece>[
        _DragPiece(
          key: '5',
          kind: _DragPieceKind.numberOutline,
          numberText: '5',
          color: Colors.black,
          left: 54,
          top: 164,
        ),
        _DragPiece(
          key: '1',
          kind: _DragPieceKind.numberOutline,
          numberText: '1',
          color: Colors.black,
          left: 208,
          top: 154,
        ),
        _DragPiece(
          key: '2',
          kind: _DragPieceKind.numberOutline,
          numberText: '2',
          color: Colors.black,
          left: 144,
          top: 246,
        ),
        _DragPiece(
          key: '3',
          kind: _DragPieceKind.numberOutline,
          numberText: '3',
          color: Colors.black,
          left: 64,
          top: 324,
        ),
        _DragPiece(
          key: '9',
          kind: _DragPieceKind.numberOutline,
          numberText: '9',
          color: Colors.black,
          left: 212,
          top: 334,
        ),
      ],
    ),
  ];

  int _levelIndex = 0;
  _DragGameStage _stage = _DragGameStage.playing;
  int _earnedPoints = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;
  bool _targetHovering = false;
  int _starsEarned = 0;
  int _shuffleSeed = 0;
  int _wrongAttemptsThisLevel = 0;
  PlayPreferences _playPreferences = PlayPreferences.defaults;
  final PlayPreferencesService _playPreferencesService =
      const PlayPreferencesService();
  final LearningMetricsService _metricsService = const LearningMetricsService();
  final GameplayMetricsTracker _metricsTracker = GameplayMetricsTracker();
  late List<_DragPiece> _activeOptions;

  final TtsService _tts = TtsService();
  bool _showFeedback = false;
  MovePlayFeedbackKind _feedbackKind = MovePlayFeedbackKind.mistake;
  bool _pendingAdvance = false;

  _DragLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    if (_stage != _DragGameStage.playing) return 'Great Job!';
    if (_currentLevel.answerKey == '2') return 'Drag the number';
    return 'Drag the ${_currentLevel.prompt.toLowerCase()}';
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
    if (RegExp(r'^\d+$').hasMatch(_currentLevel.answerKey)) {
      final n = _currentLevel.answerKey;
      return 'Drag $n into the box with $n';
    }
    final name = _currentLevel.prompt.trim().toLowerCase();
    return 'Drag the $name into the box with the $name';
  }

  void _speakInstruction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _DragGameStage.playing) return;
      _tts.speak(_instructionText());
    });
  }

  void _showOverlay(MovePlayFeedbackKind kind) {
    if (_showFeedback) return;
    setState(() {
      _showFeedback = true;
      _feedbackKind = kind;
    });
  }

  Future<void> _handleDrop(String pieceKey) async {
    if (_stage != _DragGameStage.playing || _showFeedback) {
      return;
    }
    if (pieceKey != _currentLevel.answerKey) {
      _wrongAttemptsThisLevel += 1;
      _metricsTracker.markAttempt(wrong: true);
      unawaited(_recordDragMetric(outcome: 'wrong'));
      setState(() {
        _targetHovering = false;
        _activeOptions = _shuffledOptionsForLevel();
      });
      _pendingAdvance = false;
      _showOverlay(MovePlayFeedbackKind.mistake);
      return;
    }

    _metricsTracker.markAttempt();
    unawaited(_recordDragMetric(outcome: 'correct'));
    setState(() {
      _targetHovering = false;
      _earnedPoints += 100;
    });
    _starsEarned += 1;
    _pendingAdvance = true;
    _showOverlay(MovePlayFeedbackKind.success);
  }

  Future<void> _recordDragMetric({required String outcome}) {
    return _metricsService.recordGameplayMetric(
      childId: widget.childId,
      gameType: 'drag_game',
      moduleId: widget.module.id,
      roundId: 'drag-${_levelIndex + 1}',
      outcome: outcome,
      attempts: _metricsTracker.attempts,
      wrongSelections: _metricsTracker.wrongSelections,
      responseTimeMs: _metricsTracker.responseTimeMs,
      difficulty: _playPreferences.difficulty,
      lowStimulationMode: _playPreferences.lowStimulationMode,
      adaptiveLevel: _adaptiveChoiceDelta,
      metadata: {
        'prompt': _currentLevel.prompt,
        'answerKey': _currentLevel.answerKey,
      },
    );
  }

  int get _adaptiveChoiceDelta => _playPreferences.adaptiveDelta(
    wrongAttempts: _wrongAttemptsThisLevel,
    successCount: _starsEarned,
  );

  String get _wrongHint {
    if (_currentLevel.answerKey == '2') {
      return 'Nice try. Put 2 in the box with 2.';
    }
    final name = _currentLevel.prompt.toLowerCase();
    return 'Nice try. Put the $name in the box with the $name.';
  }

  Future<void> _saveProgressIfNeeded() async {
    if (_savedCompletion || _isSavingProgress) {
      return;
    }

    setState(() {
      _isSavingProgress = true;
    });
    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: widget.module.id,
        moduleId: widget.module.id,
        score: _earnedPoints,
        metadata: {
          'source': 'drag_game',
          'gameName': widget.module.title,
        },
      );
      _savedCompletion = true;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProgress = false;
        });
      }
    }
  }

  void _replayAll() {
    setState(() {
      _levelIndex = 0;
      _earnedPoints = 0;
      _starsEarned = 0;
      _wrongAttemptsThisLevel = 0;
      _metricsTracker.reset();
      _targetHovering = false;
      _showFeedback = false;
      _savedCompletion = false;
      _stage = _DragGameStage.playing;
      _shuffleSeed++;
      _activeOptions = _shuffledOptionsForLevel();
    });
    _speakInstruction();
  }

  void _goBackToMoveAndPlay() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    if (_stage == _DragGameStage.celebration) {
      return SessionGuard(
        role: SessionGuardRole.parent,
        child: MovePlayCelebration(
          title: 'Amazing work!',
          subtitle: 'You finished all Drag rounds. Keep shining!',
          starsEarned: _starsEarned,
          starsTotal: _levels.length,
          badgeLabel: 'Silver Badge',
          trophyColor: const Color(0xFFC0C0C0),
          replayLabel: 'Replay Drag Game',
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
        _DragLevelBoard(
          level: _currentLevel,
          options: _activeOptions,
          targetHovering: _targetHovering,
          lowStimulationMode: _playPreferences.lowStimulationMode,
          onHoverChanged: (hovering) {
            if (_targetHovering != hovering) {
              setState(() => _targetHovering = hovering);
            }
          },
          onDrop: _handleDrop,
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
                  _metricsTracker.reset();
                  _shuffleSeed++;
                  _activeOptions = _shuffledOptionsForLevel();
                });
                _speakInstruction();
              } else {
                setState(() => _stage = _DragGameStage.celebration);
                _saveProgressIfNeeded();
              }
            },
          ),
      ],
    );
  }

  List<_DragPiece> _shuffledOptionsForLevel() {
    final level = _currentLevel;
    // Use the original positions as "slots" but shuffle which item uses which slot.
    final slots = level.options
        .map((p) => Offset(p.left, p.top))
        .toList(growable: false);
    final correct = level.options
        .where((piece) => piece.key == level.answerKey)
        .toList();
    final distractors = level.options
        .where((piece) => piece.key != level.answerKey)
        .toList();

    final seed =
        (_rnd[levelIndexMod] + _shuffleSeed * 997) ^ (level.answerKey.hashCode);
    final r = math.Random(seed);
    distractors.shuffle(r);
    final choiceCount = _playPreferences
        .choiceCountForRound(_levelIndex, min: 2, max: 5)
        .clamp(correct.length + 1, level.options.length)
        .toInt();
    final items = <_DragPiece>[
      ...correct,
      ...distractors.take(choiceCount - correct.length),
    ];
    items.shuffle(r);
    final out = <_DragPiece>[];
    for (var i = 0; i < items.length; i++) {
      final s = slots[i % slots.length];
      out.add(items[i].copyWith(left: s.dx, top: s.dy));
    }
    return out;
  }

  int get levelIndexMod => _levelIndex % _rnd.length;
}

class _DragLevelBoard extends StatelessWidget {
  const _DragLevelBoard({
    required this.level,
    required this.options,
    required this.targetHovering,
    required this.lowStimulationMode,
    required this.onHoverChanged,
    required this.onDrop,
  });

  final _DragLevel level;
  final List<_DragPiece> options;
  final bool targetHovering;
  final bool lowStimulationMode;
  final void Function(bool hovering) onHoverChanged;
  final void Function(String pieceKey) onDrop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 330,
        height: 430,
        child: Stack(
          children: [
            Positioned(
              left: 78,
              top: 0,
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) {
                  onHoverChanged(true);
                  return true;
                },
                onLeave: (_) => onHoverChanged(false),
                onAcceptWithDetails: (details) {
                  onHoverChanged(false);
                  onDrop(details.data);
                },
                builder: (context, candidateData, rejectedData) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 178,
                    height: 136,
                    decoration: BoxDecoration(
                      color: targetHovering
                          ? const Color(0x1F4FC3F7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: targetHovering
                            ? const Color(0xFF4EA9E3)
                            : const Color(0x334EA9E3),
                        width: targetHovering ? 3 : 1.5,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: 0.16,
                          child: Transform.scale(
                            scale: 1.18,
                            child: _DragPieceView(
                              piece: level.target.copyWithGuideColor(),
                            ),
                          ),
                        ),
                        _DragPieceView(piece: level.target),
                      ],
                    ),
                  );
                },
              ),
            ),
            for (final piece in options)
              Positioned(
                left: piece.left,
                top: piece.top,
                child: Draggable<String>(
                  data: piece.key,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Transform.scale(
                      scale: lowStimulationMode ? 1.0 : 1.04,
                      child: _DragPieceView(piece: piece),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.26,
                    child: _DragPieceView(piece: piece),
                  ),
                  child: _DragPieceView(piece: piece),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DragPieceView extends StatelessWidget {
  const _DragPieceView({required this.piece});

  final _DragPiece piece;

  @override
  Widget build(BuildContext context) {
    final displayColor = piece.color == Colors.black
        ? _outlineColorForKey(piece.key)
        : piece.color;
    switch (piece.kind) {
      case _DragPieceKind.icon:
        return Icon(piece.icon!, size: 86, color: displayColor);
      case _DragPieceKind.number:
        return Text(
          piece.numberText!,
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            color: displayColor,
          ),
        );
      case _DragPieceKind.numberOutline:
        return _OutlinedText(
          value: piece.numberText!,
          fontSize: 76,
          strokeColor: displayColor,
          fillColor: Colors.white,
          strokeWidth: 2.3,
        );
    }
  }

  Color _outlineColorForKey(String key) {
    return switch (key) {
      'circle' => const Color(0xFFF14D4D),
      'triangle' => const Color(0xFF5DAA2A),
      'rectangle' => const Color(0xFFFF0E8A),
      'star' => const Color(0xFFE9B126),
      'heart' => const Color(0xFFE36BA7),
      'sun' => const Color(0xFFFFB300),
      'cloud' => const Color(0xFF7BA7C9),
      'moon' => const Color(0xFF7E8BEA),
      'rain' => const Color(0xFF4EA9E3),
      'flower' => const Color(0xFFDD6B9A),
      '1' => const Color(0xFF59B086),
      '2' => const Color(0xFFF58436),
      '3' => const Color(0xFFF7746A),
      '5' => const Color(0xFFE9B126),
      '9' => const Color(0xFFEF5755),
      _ => Colors.black87,
    };
  }
}

class _OutlinedText extends StatelessWidget {
  const _OutlinedText({
    required this.value,
    required this.fontSize,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  final String value;
  final double fontSize;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: fillColor,
          ),
        ),
      ],
    );
  }
}

enum _DragPieceKind { icon, number, numberOutline }

class _DragLevel {
  const _DragLevel({
    required this.prompt,
    required this.answerKey,
    required this.target,
    required this.options,
  });

  final String prompt;
  final String answerKey;
  final _DragPiece target;
  final List<_DragPiece> options;
}

class _DragPiece {
  const _DragPiece({
    required this.key,
    required this.kind,
    required this.left,
    required this.top,
    this.icon,
    this.numberText,
    this.color = Colors.black,
  });

  final String key;
  final _DragPieceKind kind;
  final double left;
  final double top;
  final IconData? icon;
  final String? numberText;
  final Color color;

  _DragPiece copyWith({double? left, double? top, Color? color}) {
    return _DragPiece(
      key: key,
      kind: kind,
      left: left ?? this.left,
      top: top ?? this.top,
      icon: icon,
      numberText: numberText,
      color: color ?? this.color,
    );
  }

  _DragPiece copyWithGuideColor() {
    return copyWith(color: color.withValues(alpha: 0.75));
  }
}
