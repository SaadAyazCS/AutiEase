import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
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
  ];

  int _levelIndex = 0;
  _TapGameStage _stage = _TapGameStage.playing;
  bool _isSavingProgress = false;
  final Set<int> _recordedLevelNumbers = <int>{};
  int _starsEarned = 0;

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
    if (!mounted) return;
    _speakInstruction();
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  String _instructionText() {
    final raw = _currentLevel.prompt.trim();
    final lower = raw.toLowerCase();
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

    if (option.key != _currentLevel.prompt.toLowerCase()) {
      _pendingAdvance = false;
      setState(() => _activeOptions = _shuffledOptionsForLevel());
      _showOverlay(MovePlayFeedbackKind.mistake);
      return;
    }

    final completedLevel = _levelIndex + 1;
    _starsEarned += 1;
    await _recordLevelCompletion(completedLevel);
    _pendingAdvance = true;
    _showOverlay(MovePlayFeedbackKind.success);
  }

  Future<void> _recordLevelCompletion(int levelNumber) async {
    if (_isSavingProgress || _recordedLevelNumbers.contains(levelNumber)) {
      return;
    }

    setState(() {
      _isSavingProgress = true;
    });
    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: '${widget.module.id}-level-$levelNumber',
        moduleId: widget.module.id,
        score: levelNumber * 100,
      );
      _recordedLevelNumbers.add(levelNumber);
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
      _starsEarned = 0;
      _showFeedback = false;
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
        _TapLevelBoard(level: _currentLevel, options: _activeOptions, onTapOption: _handleTap),
        if (_showFeedback)
          MovePlayFeedbackOverlay(
            kind: _feedbackKind,
            primaryLabel:
                _feedbackKind == MovePlayFeedbackKind.success ? 'Next' : 'Try again',
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
                  _shuffleSeed++;
                  _activeOptions = _shuffledOptionsForLevel();
                });
                _speakInstruction();
              } else {
                setState(() => _stage = _TapGameStage.celebration);
              }
            },
          ),
      ],
    );
  }

  List<_TapOption> _shuffledOptionsForLevel() {
    final slots = List<Offset>.from(_slots);
    final items = List<_TapOption>.from(_currentLevel.options);
    final r = math.Random((_shuffleSeed * 997) ^ _levelIndex ^ _starsEarned);
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
    required this.onTapOption,
  });

  final _TapLevel level;
  final List<_TapOption> options;
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
                  child: _TapOptionView(option: option),
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
    switch (option.kind) {
      case _TapOptionKind.icon:
        return Icon(option.icon!, size: 86, color: option.color);
      case _TapOptionKind.emoji:
        return Text(option.emoji!, style: const TextStyle(fontSize: 58));
      case _TapOptionKind.number:
        return Text(
          option.numberText!,
          style: TextStyle(
            fontSize: 82,
            fontWeight: FontWeight.w700,
            color: option.color,
          ),
        );
    }
  }
}

enum _TapOptionKind { icon, emoji, number }

class _TapLevel {
  const _TapLevel({required this.prompt, required this.options});

  final String prompt;
  final List<_TapOption> options;
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
    );
  }
}
