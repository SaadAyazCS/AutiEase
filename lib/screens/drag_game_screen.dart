import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
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
      prompt: 'Apple',
      answerKey: 'apple',
      target: _DragPiece(
        key: 'apple',
        kind: _DragPieceKind.fruitFilled,
        fruit: _FruitKind.apple,
        left: 144,
        top: 18,
      ),
      options: <_DragPiece>[
        _DragPiece(
          key: 'banana',
          kind: _DragPieceKind.fruitOutline,
          fruit: _FruitKind.banana,
          left: 40,
          top: 150,
        ),
        _DragPiece(
          key: 'orange',
          kind: _DragPieceKind.fruitOutline,
          fruit: _FruitKind.orange,
          left: 196,
          top: 150,
        ),
        _DragPiece(
          key: 'grapes',
          kind: _DragPieceKind.fruitOutline,
          fruit: _FruitKind.grapes,
          left: 118,
          top: 244,
        ),
        _DragPiece(
          key: 'apple',
          kind: _DragPieceKind.fruitOutline,
          fruit: _FruitKind.apple,
          left: 52,
          top: 318,
        ),
        _DragPiece(
          key: 'mango',
          kind: _DragPieceKind.fruitOutline,
          fruit: _FruitKind.mango,
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
    if (!mounted) return;
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
      return 'Drag the black and white shape of number $n to the colored shape of number $n';
    }
    final name = _currentLevel.prompt.trim().toLowerCase();
    return 'Drag the black and white shape of $name to the colored shape of $name';
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
      setState(() {
        _targetHovering = false;
        _activeOptions = _shuffledOptionsForLevel();
      });
      _pendingAdvance = false;
      _showOverlay(MovePlayFeedbackKind.mistake);
      return;
    }

    setState(() {
      _targetHovering = false;
      _earnedPoints += 100;
    });
    _starsEarned += 1;
    _pendingAdvance = true;
    _showOverlay(MovePlayFeedbackKind.success);
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
    final items = List<_DragPiece>.from(level.options);

    final seed = (_rnd[levelIndexMod] + _shuffleSeed * 997) ^ (level.answerKey.hashCode);
    final r = math.Random(seed);
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
    required this.onHoverChanged,
    required this.onDrop,
  });

  final _DragLevel level;
  final List<_DragPiece> options;
  final bool targetHovering;
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
              left: 108,
              top: 2,
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
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: targetHovering
                          ? const Color(0x1F4FC3F7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: targetHovering
                            ? const Color(0xFF4EA9E3)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(child: _DragPieceView(piece: level.target)),
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
                      scale: 1.04,
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
    switch (piece.kind) {
      case _DragPieceKind.icon:
        return Icon(piece.icon!, size: 86, color: piece.color);
      case _DragPieceKind.number:
        return Text(
          piece.numberText!,
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            color: piece.color,
          ),
        );
      case _DragPieceKind.numberOutline:
        return _OutlinedText(
          value: piece.numberText!,
          fontSize: 76,
          strokeColor: Colors.black,
          fillColor: Colors.white,
          strokeWidth: 2.3,
        );
      case _DragPieceKind.fruitOutline:
        return SizedBox(
          width: 96,
          height: 96,
          child: CustomPaint(
            painter: _FruitPainter(kind: piece.fruit!, filled: false),
          ),
        );
      case _DragPieceKind.fruitFilled:
        return SizedBox(
          width: 96,
          height: 96,
          child: CustomPaint(
            painter: _FruitPainter(kind: piece.fruit!, filled: true),
          ),
        );
    }
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

enum _DragPieceKind { icon, number, numberOutline, fruitOutline, fruitFilled }

enum _FruitKind { apple, banana, orange, grapes, mango }

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
    this.fruit,
    this.color = Colors.black,
  });

  final String key;
  final _DragPieceKind kind;
  final double left;
  final double top;
  final IconData? icon;
  final String? numberText;
  final _FruitKind? fruit;
  final Color color;

  _DragPiece copyWith({
    double? left,
    double? top,
  }) {
    return _DragPiece(
      key: key,
      kind: kind,
      left: left ?? this.left,
      top: top ?? this.top,
      icon: icon,
      numberText: numberText,
      fruit: fruit,
      color: color,
    );
  }
}

class _FruitPainter extends CustomPainter {
  const _FruitPainter({required this.kind, required this.filled});

  final _FruitKind kind;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF121212)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = switch (kind) {
        _FruitKind.apple => const Color(0xFFE84B4B),
        _FruitKind.banana => const Color(0xFFFFD447),
        _FruitKind.orange => const Color(0xFFFF8C00),
        _FruitKind.grapes => const Color(0xFF7E57C2),
        _FruitKind.mango => const Color(0xFFFFA500),
      };

    void drawPath(Path p) {
      if (filled) canvas.drawPath(p, fill);
      canvas.drawPath(p, stroke);
    }

    switch (kind) {
      case _FruitKind.apple:
        final p = Path()
          ..moveTo(size.width * 0.50, size.height * 0.20)
          ..cubicTo(
            size.width * 0.30,
            size.height * 0.20,
            size.width * 0.25,
            size.height * 0.40,
            size.width * 0.30,
            size.height * 0.55,
          )
          ..cubicTo(
            size.width * 0.35,
            size.height * 0.75,
            size.width * 0.65,
            size.height * 0.75,
            size.width * 0.70,
            size.height * 0.55,
          )
          ..cubicTo(
            size.width * 0.75,
            size.height * 0.40,
            size.width * 0.70,
            size.height * 0.20,
            size.width * 0.50,
            size.height * 0.20,
          );
        drawPath(p);
        canvas.drawLine(
          Offset(size.width * 0.50, size.height * 0.20),
          Offset(size.width * 0.50, size.height * 0.10),
          stroke,
        );
        final leaf = Path()
          ..moveTo(size.width * 0.50, size.height * 0.20)
          ..cubicTo(
            size.width * 0.50,
            size.height * 0.10,
            size.width * 0.60,
            size.height * 0.10,
            size.width * 0.60,
            size.height * 0.20,
          );
        canvas.drawPath(leaf, stroke);
        break;
      case _FruitKind.banana:
        final p = Path()
          ..moveTo(size.width * 0.20, size.height * 0.60)
          ..cubicTo(
            size.width * 0.40,
            size.height * 0.10,
            size.width * 0.80,
            size.height * 0.10,
            size.width * 0.85,
            size.height * 0.40,
          )
          ..cubicTo(
            size.width * 0.70,
            size.height * 0.70,
            size.width * 0.40,
            size.height * 0.80,
            size.width * 0.20,
            size.height * 0.60,
          )
          ..close();
        drawPath(p);
        break;
      case _FruitKind.orange:
        final p = Path()
          ..moveTo(size.width * 0.50, size.height * 0.20)
          ..cubicTo(
            size.width * 0.20,
            size.height * 0.20,
            size.width * 0.20,
            size.height * 0.80,
            size.width * 0.50,
            size.height * 0.80,
          )
          ..cubicTo(
            size.width * 0.80,
            size.height * 0.80,
            size.width * 0.80,
            size.height * 0.20,
            size.width * 0.50,
            size.height * 0.20,
          )
          ..close();
        drawPath(p);
        break;
      case _FruitKind.grapes:
        for (final c in <Offset>[
          Offset(size.width * 0.40, size.height * 0.30),
          Offset(size.width * 0.60, size.height * 0.30),
          Offset(size.width * 0.50, size.height * 0.50),
        ]) {
          final r = size.width * 0.10;
          final o = Path()
            ..moveTo(c.dx - r, c.dy)
            ..cubicTo(
              c.dx - r, c.dy - r,
              c.dx + r, c.dy - r,
              c.dx + r, c.dy,
            )
            ..cubicTo(
              c.dx + r, c.dy + r,
              c.dx - r, c.dy + r,
              c.dx - r, c.dy,
            )
            ..close();
          drawPath(o);
        }
        break;
      case _FruitKind.mango:
        final p = Path()
          ..moveTo(size.width * 0.50, size.height * 0.20)
          ..cubicTo(
            size.width * 0.30,
            size.height * 0.25,
            size.width * 0.25,
            size.height * 0.50,
            size.width * 0.35,
            size.height * 0.70,
          )
          ..cubicTo(
            size.width * 0.45,
            size.height * 0.85,
            size.width * 0.70,
            size.height * 0.75,
            size.width * 0.75,
            size.height * 0.50,
          )
          ..cubicTo(
            size.width * 0.80,
            size.height * 0.25,
            size.width * 0.60,
            size.height * 0.15,
            size.width * 0.50,
            size.height * 0.20,
          )
          ..close();
        drawPath(p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FruitPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.filled != filled;
}
