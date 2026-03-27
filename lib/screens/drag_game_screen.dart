import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
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

enum _DragGameStage { playing, wrongOption, levelCompleted, allLevelsCompleted }

class _DragGameScreenState extends State<DragGameScreen> {
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
        kind: _DragPieceKind.emoji,
        emoji: '🍎',
        left: 144,
        top: 18,
      ),
      options: <_DragPiece>[
        _DragPiece(
          key: 'banana',
          kind: _DragPieceKind.fruitOutline,
          fruitOutlineType: _FruitOutlineType.banana,
          left: 40,
          top: 150,
        ),
        _DragPiece(
          key: 'watermelon',
          kind: _DragPieceKind.fruitOutline,
          fruitOutlineType: _FruitOutlineType.watermelon,
          left: 196,
          top: 150,
        ),
        _DragPiece(
          key: 'grapes',
          kind: _DragPieceKind.fruitOutline,
          fruitOutlineType: _FruitOutlineType.grapes,
          left: 118,
          top: 244,
        ),
        _DragPiece(
          key: 'apple',
          kind: _DragPieceKind.fruitOutline,
          fruitOutlineType: _FruitOutlineType.apple,
          left: 52,
          top: 318,
        ),
        _DragPiece(
          key: 'lemon',
          kind: _DragPieceKind.fruitOutline,
          fruitOutlineType: _FruitOutlineType.lemon,
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

  _DragLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    if (_stage == _DragGameStage.playing) {
      return 'Drag to "${_currentLevel.prompt}"';
    }
    if (_stage == _DragGameStage.wrongOption) {
      return 'Drag Game';
    }
    return 'Great Job!';
  }

  Future<void> _handleDrop(String pieceKey) async {
    if (_stage != _DragGameStage.playing) {
      return;
    }
    if (pieceKey != _currentLevel.answerKey) {
      setState(() {
        _targetHovering = false;
        _stage = _DragGameStage.wrongOption;
      });
      return;
    }

    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _targetHovering = false;
        _earnedPoints += 100;
        _stage = _DragGameStage.levelCompleted;
      });
      return;
    }

    setState(() {
      _targetHovering = false;
      _earnedPoints += 100;
      _stage = _DragGameStage.allLevelsCompleted;
    });
    await _saveProgressIfNeeded();
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

  void _retryLevel() {
    setState(() {
      _stage = _DragGameStage.playing;
    });
  }

  void _replayCurrentLevel() {
    setState(() {
      _stage = _DragGameStage.playing;
    });
  }

  void _nextLevel() {
    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _levelIndex += 1;
        _targetHovering = false;
        _stage = _DragGameStage.playing;
      });
      return;
    }
    setState(() {
      _stage = _DragGameStage.allLevelsCompleted;
    });
  }

  void _goHome() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
    switch (_stage) {
      case _DragGameStage.playing:
        return _DragLevelBoard(
          level: _currentLevel,
          targetHovering: _targetHovering,
          onHoverChanged: (hovering) {
            if (_targetHovering != hovering) {
              setState(() {
                _targetHovering = hovering;
              });
            }
          },
          onDrop: _handleDrop,
        );
      case _DragGameStage.wrongOption:
        return _WrongOptionCard(onTryAgain: _retryLevel);
      case _DragGameStage.levelCompleted:
        return _LevelCompletedCard(
          levelNumber: _levelIndex + 1,
          onReplay: _replayCurrentLevel,
          onNextLevel: _nextLevel,
        );
      case _DragGameStage.allLevelsCompleted:
        return _AllLevelsCompletedCard(
          isSavingProgress: _isSavingProgress,
          onHome: _goHome,
        );
    }
  }
}

class _DragLevelBoard extends StatelessWidget {
  const _DragLevelBoard({
    required this.level,
    required this.targetHovering,
    required this.onHoverChanged,
    required this.onDrop,
  });

  final _DragLevel level;
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
                            ? AppColors.primaryBlue
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(child: _DragPieceView(piece: level.target)),
                  );
                },
              ),
            ),
            for (final piece in level.options)
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
      case _DragPieceKind.emoji:
        return Text(piece.emoji!, style: const TextStyle(fontSize: 58));
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
          width: 92,
          height: 92,
          child: CustomPaint(
            painter: _FruitOutlinePainter(type: piece.fruitOutlineType!),
          ),
        );
    }
  }
}

class _FruitOutlinePainter extends CustomPainter {
  const _FruitOutlinePainter({required this.type});

  final _FruitOutlineType type;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _FruitOutlineType.banana:
        void drawBanana(double dx, double dy, double scale) {
          final w = size.width * 0.34 * scale;
          final h = size.height * 0.34 * scale;
          final path = Path()
            ..moveTo(dx + w * 0.08, dy + h * 0.76)
            ..quadraticBezierTo(
              dx + w * 0.48,
              dy + h * 0.02,
              dx + w * 0.96,
              dy + h * 0.56,
            )
            ..quadraticBezierTo(
              dx + w * 0.62,
              dy + h * 0.88,
              dx + w * 0.08,
              dy + h * 0.76,
            )
            ..moveTo(dx + w * 0.14, dy + h * 0.67)
            ..quadraticBezierTo(
              dx + w * 0.46,
              dy + h * 0.12,
              dx + w * 0.86,
              dy + h * 0.55,
            );
          canvas.drawPath(path, stroke);
        }

        drawBanana(size.width * 0.04, size.height * 0.34, 1.0);
        drawBanana(size.width * 0.24, size.height * 0.28, 1.06);
        drawBanana(size.width * 0.46, size.height * 0.34, 1.0);
        break;
      case _FruitOutlineType.watermelon:
        final rindRect = Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.28,
          size.width * 0.78,
          size.height * 0.56,
        );
        canvas.drawArc(rindRect, 0.32, 2.58, false, stroke);
        canvas.drawLine(
          Offset(size.width * 0.18, size.height * 0.68),
          Offset(size.width * 0.84, size.height * 0.54),
          stroke,
        );
        canvas.drawLine(
          Offset(size.width * 0.24, size.height * 0.73),
          Offset(size.width * 0.88, size.height * 0.58),
          stroke,
        );
        for (final seed in <Offset>[
          Offset(size.width * 0.43, size.height * 0.56),
          Offset(size.width * 0.56, size.height * 0.52),
          Offset(size.width * 0.68, size.height * 0.49),
          Offset(size.width * 0.61, size.height * 0.62),
        ]) {
          canvas.drawCircle(seed, 2.3, stroke);
        }
        break;
      case _FruitOutlineType.grapes:
        for (final center in <Offset>[
          Offset(size.width * 0.28, size.height * 0.38),
          Offset(size.width * 0.42, size.height * 0.35),
          Offset(size.width * 0.56, size.height * 0.36),
          Offset(size.width * 0.7, size.height * 0.39),
          Offset(size.width * 0.22, size.height * 0.52),
          Offset(size.width * 0.36, size.height * 0.5),
          Offset(size.width * 0.5, size.height * 0.5),
          Offset(size.width * 0.64, size.height * 0.52),
          Offset(size.width * 0.3, size.height * 0.65),
          Offset(size.width * 0.44, size.height * 0.64),
          Offset(size.width * 0.58, size.height * 0.65),
          Offset(size.width * 0.49, size.height * 0.79),
        ]) {
          canvas.drawCircle(center, size.width * 0.088, stroke);
        }
        canvas.drawLine(
          Offset(size.width * 0.46, size.height * 0.18),
          Offset(size.width * 0.39, size.height * 0.3),
          stroke,
        );
        final leaf = Path()
          ..moveTo(size.width * 0.49, size.height * 0.2)
          ..quadraticBezierTo(
            size.width * 0.66,
            size.height * 0.13,
            size.width * 0.61,
            size.height * 0.31,
          )
          ..quadraticBezierTo(
            size.width * 0.48,
            size.height * 0.29,
            size.width * 0.49,
            size.height * 0.2,
          );
        canvas.drawPath(leaf, stroke);
        break;
      case _FruitOutlineType.apple:
        final apple = Path()
          ..moveTo(size.width * 0.5, size.height * 0.26)
          ..cubicTo(
            size.width * 0.24,
            size.height * 0.2,
            size.width * 0.16,
            size.height * 0.58,
            size.width * 0.5,
            size.height * 0.82,
          )
          ..cubicTo(
            size.width * 0.84,
            size.height * 0.58,
            size.width * 0.76,
            size.height * 0.2,
            size.width * 0.5,
            size.height * 0.26,
          );
        canvas.drawPath(apple, stroke);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.24),
          Offset(size.width * 0.56, size.height * 0.12),
          stroke,
        );
        final leaf = Path()
          ..moveTo(size.width * 0.58, size.height * 0.15)
          ..quadraticBezierTo(
            size.width * 0.76,
            size.height * 0.08,
            size.width * 0.69,
            size.height * 0.24,
          );
        canvas.drawPath(leaf, stroke);
        break;
      case _FruitOutlineType.lemon:
        final lemon = Path()
          ..moveTo(size.width * 0.16, size.height * 0.53)
          ..quadraticBezierTo(
            size.width * 0.5,
            size.height * 0.2,
            size.width * 0.84,
            size.height * 0.53,
          )
          ..quadraticBezierTo(
            size.width * 0.5,
            size.height * 0.85,
            size.width * 0.16,
            size.height * 0.53,
          );
        canvas.drawPath(lemon, stroke);
        for (final dot in <Offset>[
          Offset(size.width * 0.42, size.height * 0.48),
          Offset(size.width * 0.51, size.height * 0.55),
          Offset(size.width * 0.58, size.height * 0.46),
          Offset(size.width * 0.46, size.height * 0.63),
        ]) {
          canvas.drawCircle(dot, 1.8, stroke);
        }
        canvas.drawLine(
          Offset(size.width * 0.58, size.height * 0.25),
          Offset(size.width * 0.67, size.height * 0.15),
          stroke,
        );
        final leaf = Path()
          ..moveTo(size.width * 0.67, size.height * 0.16)
          ..quadraticBezierTo(
            size.width * 0.81,
            size.height * 0.15,
            size.width * 0.74,
            size.height * 0.27,
          );
        canvas.drawPath(leaf, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FruitOutlinePainter oldDelegate) {
    return oldDelegate.type != type;
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

class _WrongOptionCard extends StatelessWidget {
  const _WrongOptionCard({required this.onTryAgain});

  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFDCDCDC),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wrong Option',
              style: TextStyle(fontSize: 38 / 2, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black54, width: 2),
              ),
              child: const Center(
                child: Icon(
                  Icons.close_rounded,
                  color: AppColors.errorRed,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onTryAgain,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA260),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCompletedCard extends StatelessWidget {
  const _LevelCompletedCard({
    required this.levelNumber,
    required this.onReplay,
    required this.onNextLevel,
  });

  final int levelNumber;
  final VoidCallback onReplay;
  final VoidCallback onNextLevel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 330,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 70,
              color: Color(0xFFF5B700),
            ),
            const SizedBox(height: 14),
            Text(
              'Level $levelNumber Completed',
              style: const TextStyle(
                fontSize: 30 / 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: Color(0xFFFF7043), size: 36),
                SizedBox(width: 3),
                Icon(Icons.star, color: Color(0xFFFFB74D), size: 36),
                SizedBox(width: 3),
                Icon(Icons.star, color: Color(0xFFFBC02D), size: 36),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'You have earned 100 points',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 30 / 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            _ActionWideButton(
              label: 'Replay',
              backgroundColor: const Color(0xFFF4A9AD),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.replay,
              onTap: onReplay,
            ),
            const SizedBox(height: 14),
            _ActionWideButton(
              label: levelNumber == 3 ? 'Next' : 'Next Level',
              backgroundColor: const Color(0xFF76ED67),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.arrow_forward,
              onTap: onNextLevel,
            ),
          ],
        ),
      ),
    );
  }
}

class _AllLevelsCompletedCard extends StatelessWidget {
  const _AllLevelsCompletedCard({
    required this.isSavingProgress,
    required this.onHome,
  });

  final bool isSavingProgress;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 330,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 72,
              color: Color(0xFFF5B700),
            ),
            const SizedBox(height: 12),
            const Text(
              'You have completed\nDrag Games',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 34 / 2,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (isSavingProgress)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(),
              ),
            _ActionWideButton(
              label: 'Home',
              backgroundColor: const Color(0xFFF4A9AD),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.replay,
              onTap: onHome,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionWideButton extends StatelessWidget {
  const _ActionWideButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.trailingIcon,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 30 / 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Icon(trailingIcon),
          ],
        ),
      ),
    );
  }
}

enum _DragPieceKind { icon, emoji, number, numberOutline, fruitOutline }

enum _FruitOutlineType { banana, watermelon, grapes, apple, lemon }

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
    this.emoji,
    this.numberText,
    this.fruitOutlineType,
    this.color = Colors.black,
  });

  final String key;
  final _DragPieceKind kind;
  final double left;
  final double top;
  final IconData? icon;
  final String? emoji;
  final String? numberText;
  final _FruitOutlineType? fruitOutlineType;
  final Color color;
}
