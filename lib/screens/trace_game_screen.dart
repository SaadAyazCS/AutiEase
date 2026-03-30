import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/trace_path_validator.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class TraceGameScreen extends StatefulWidget {
  const TraceGameScreen({
    super.key,
    required this.childId,
    required this.module,
  });

  final String childId;
  final LearningModuleModel module;

  @override
  State<TraceGameScreen> createState() => _TraceGameScreenState();
}

enum _TraceGameStage {
  playing,
  wrongOption,
  levelCompleted,
  allLevelsCompleted,
}

class _TraceGameScreenState extends State<TraceGameScreen> {
  static const _levels = <_TraceLevel>[
    _TraceLevel(prompt: 'Line', kind: _TraceLevelKind.line),
    _TraceLevel(prompt: 'Curves', kind: _TraceLevelKind.curves),
    _TraceLevel(prompt: 'shapes', kind: _TraceLevelKind.shapes),
  ];

  final List<Offset> _tracePoints = <Offset>[];
  final GlobalKey _boardKey = GlobalKey();

  int _levelIndex = 0;
  _TraceGameStage _stage = _TraceGameStage.playing;
  int _earnedPoints = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;

  _TraceLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    if (_stage == _TraceGameStage.playing) {
      return 'Trace on "${_currentLevel.prompt}"';
    }
    if (_stage == _TraceGameStage.wrongOption) {
      return 'Trace Game';
    }
    return 'Great Job!';
  }

  void _onPanStart(DragStartDetails details) {
    final local = _globalToBoard(details.globalPosition);
    if (local == null) {
      return;
    }
    setState(() {
      _tracePoints
        ..clear()
        ..add(local);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final local = _globalToBoard(details.globalPosition);
    if (local == null) {
      return;
    }
    setState(() {
      _tracePoints.add(local);
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_stage != _TraceGameStage.playing) {
      return;
    }
    final result = TracePathValidator.validate(
      List<Offset>.from(_tracePoints),
      _kindForLevel(_currentLevel.kind),
    );
    if (result.isValid) {
      await _markSuccess();
      return;
    }
    setState(() {
      _stage = _TraceGameStage.wrongOption;
      _tracePoints.clear();
    });
  }

  Offset? _globalToBoard(Offset global) {
    final renderObject = _boardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    return renderObject.globalToLocal(global);
  }

  TracePathKind _kindForLevel(_TraceLevelKind kind) {
    switch (kind) {
      case _TraceLevelKind.line:
        return TracePathKind.line;
      case _TraceLevelKind.curves:
        return TracePathKind.curves;
      case _TraceLevelKind.shapes:
        return TracePathKind.shapes;
    }
  }

  Future<void> _markSuccess() async {
    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _earnedPoints += 100;
        _stage = _TraceGameStage.levelCompleted;
        _tracePoints.clear();
      });
      return;
    }

    setState(() {
      _earnedPoints += 100;
      _stage = _TraceGameStage.allLevelsCompleted;
      _tracePoints.clear();
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
      _stage = _TraceGameStage.playing;
      _tracePoints.clear();
    });
  }

  void _replayCurrentLevel() {
    setState(() {
      _stage = _TraceGameStage.playing;
      _tracePoints.clear();
    });
  }

  void _nextLevel() {
    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _levelIndex += 1;
        _stage = _TraceGameStage.playing;
        _tracePoints.clear();
      });
      return;
    }
    setState(() {
      _stage = _TraceGameStage.allLevelsCompleted;
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
      case _TraceGameStage.playing:
        return Center(
          child: SizedBox(
            key: _boardKey,
            width: 330,
            height: 440,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                painter: _TraceGuidePainter(
                  kind: _currentLevel.kind,
                  tracePoints: _tracePoints,
                ),
              ),
            ),
          ),
        );
      case _TraceGameStage.wrongOption:
        return _WrongOptionCard(onTryAgain: _retryLevel);
      case _TraceGameStage.levelCompleted:
        return _LevelCompletedCard(
          levelNumber: _levelIndex + 1,
          onReplay: _replayCurrentLevel,
          onNextLevel: _nextLevel,
        );
      case _TraceGameStage.allLevelsCompleted:
        return _AllLevelsCompletedCard(
          isSavingProgress: _isSavingProgress,
          onHome: _goHome,
        );
    }
  }
}

enum _TraceLevelKind { line, curves, shapes }

class _TraceLevel {
  const _TraceLevel({required this.prompt, required this.kind});

  final String prompt;
  final _TraceLevelKind kind;
}

class _TraceGuidePainter extends CustomPainter {
  const _TraceGuidePainter({required this.kind, required this.tracePoints});

  final _TraceLevelKind kind;
  final List<Offset> tracePoints;

  @override
  void paint(Canvas canvas, Size size) {
    final black = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dash = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _TraceLevelKind.line:
        canvas.drawLine(const Offset(110, 34), const Offset(210, 34), black);
        _drawDashedLine(
          canvas,
          const Offset(40, 150),
          const Offset(290, 150),
          dash,
        );
        _drawDashedLine(
          canvas,
          const Offset(40, 210),
          const Offset(290, 210),
          dash,
        );
        _drawDashedLine(
          canvas,
          const Offset(40, 270),
          const Offset(290, 270),
          dash,
        );
        _drawDashedLine(
          canvas,
          const Offset(40, 330),
          const Offset(290, 330),
          dash,
        );
      case _TraceLevelKind.curves:
        final topWave = Path()
          ..moveTo(142, 44)
          ..cubicTo(150, 10, 166, 80, 176, 44)
          ..cubicTo(186, 10, 198, 74, 218, 44);
        canvas.drawPath(topWave, black);
        _drawArrow(canvas, const Offset(218, 44), const Offset(230, 44), black);

        final midCurve = Path()
          ..moveTo(42, 154)
          ..cubicTo(30, 132, 52, 116, 70, 128)
          ..cubicTo(92, 142, 102, 118, 120, 124)
          ..cubicTo(144, 132, 118, 170, 98, 182)
          ..cubicTo(82, 194, 74, 218, 82, 230)
          ..cubicTo(92, 244, 124, 242, 142, 232);
        _drawDashedPath(canvas, midCurve, dash);
        _drawArrow(
          canvas,
          const Offset(142, 232),
          const Offset(160, 226),
          black,
        );

        final bottomPath = Path()
          ..moveTo(42, 320)
          ..lineTo(42, 402)
          ..quadraticBezierTo(42, 412, 52, 412)
          ..lineTo(154, 412);
        _drawDashedPath(canvas, bottomPath, dash);
        _drawArrow(
          canvas,
          const Offset(154, 412),
          const Offset(170, 412),
          black,
        );

        final loopPath = Path()
          ..moveTo(222, 302)
          ..cubicTo(266, 298, 292, 314, 292, 336)
          ..cubicTo(292, 356, 260, 366, 248, 384)
          ..cubicTo(240, 396, 244, 410, 256, 416);
        _drawDashedPath(canvas, loopPath, dash);
        _drawArrow(
          canvas,
          const Offset(292, 336),
          const Offset(310, 332),
          black,
        );
      case _TraceLevelKind.shapes:
        final topTriangle = Path()
          ..moveTo(172, 44)
          ..lineTo(158, 68)
          ..lineTo(186, 68)
          ..close();
        canvas.drawPath(topTriangle, black);
        canvas.drawRect(const Rect.fromLTWH(144, 80, 32, 32), black);
        canvas.drawCircle(const Offset(200, 96), 16, black);

        final square = Path()..addRect(const Rect.fromLTWH(20, 170, 160, 160));
        _drawDashedPath(canvas, square, dash, dashLength: 16, gapLength: 8);

        final ring = Path()
          ..addOval(
            Rect.fromCircle(center: Offset(size.width - 46, 262), radius: 30),
          );
        _drawDashedPath(canvas, ring, dash, dashLength: 12, gapLength: 8);

        _drawDashedLine(
          canvas,
          const Offset(130, 392),
          const Offset(300, 392),
          dash,
        );

        final dots = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.black;
        final center = const Offset(146, 410);
        for (var i = 0; i < 14; i++) {
          final theta = (math.pi * 2 * i) / 14;
          final point = Offset(
            center.dx + math.cos(theta) * 46,
            center.dy + math.sin(theta) * 46,
          );
          canvas.drawCircle(point, 6, dots);
        }
    }

    if (tracePoints.length > 1) {
      final trace = Paint()
        ..color = AppColors.primaryBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(tracePoints.first.dx, tracePoints.first.dy);
      for (final point in tracePoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, trace);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLength = 16,
    double gapLength = 10,
  }) {
    final totalLength = (end - start).distance;
    final direction = (end - start) / totalLength;
    var distance = 0.0;
    while (distance < totalLength) {
      final dashStart = start + direction * distance;
      final dashEnd =
          start + direction * math.min(distance + dashLength, totalLength);
      canvas.drawLine(dashStart, dashEnd, paint);
      distance += dashLength + gapLength;
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path source,
    Paint paint, {
    double dashLength = 14,
    double gapLength = 10,
  }) {
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        final extract = metric.extractPath(distance, next);
        canvas.drawPath(extract, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const size = 7.0;
    final p1 = Offset(
      end.dx - math.cos(angle - math.pi / 6) * size,
      end.dy - math.sin(angle - math.pi / 6) * size,
    );
    final p2 = Offset(
      end.dx - math.cos(angle + math.pi / 6) * size,
      end.dy - math.sin(angle + math.pi / 6) * size,
    );
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _TraceGuidePainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.tracePoints != tracePoints;
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
              'You have completed\nTracing Games',
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
