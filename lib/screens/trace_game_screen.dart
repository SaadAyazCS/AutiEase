import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/tts_service.dart';
import '../services/trace_path_validator.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/move_play_celebration.dart';
import '../widgets/move_play_feedback.dart';
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

enum _TraceGameStage { playing, celebration }

class _TraceGameScreenState extends State<TraceGameScreen>
    with SingleTickerProviderStateMixin {
  static const _levels = <_TraceLevel>[
    _TraceLevel(prompt: 'Line', kind: _TraceLevelKind.line),
    _TraceLevel(prompt: 'Curves', kind: _TraceLevelKind.curves),
    _TraceLevel(prompt: 'shapes', kind: _TraceLevelKind.shapes),
  ];

  final List<Offset> _tracePoints = <Offset>[];
  final GlobalKey _boardKey = GlobalKey();
  int? _activeElementIndex;
  final Set<int> _completedElements = <int>{};

  int _levelIndex = 0;
  _TraceGameStage _stage = _TraceGameStage.playing;
  int _earnedPoints = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;
  int _starsEarned = 0;
  int _shuffleSeed = 0;

  final TtsService _tts = TtsService();
  bool _showFeedback = false;
  MovePlayFeedbackKind _feedbackKind = MovePlayFeedbackKind.mistake;
  bool _pendingAdvance = false;
  late final AnimationController _sparkleCtrl;

  _TraceLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    return _stage == _TraceGameStage.playing ? _instructionText() : 'Great Job!';
  }

  @override
  void initState() {
    super.initState();
    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
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
    _sparkleCtrl.dispose();
    super.dispose();
  }

  String _instructionText() {
    return switch (_currentLevel.kind) {
      _TraceLevelKind.line => 'Trace the lines one by one.',
      _TraceLevelKind.curves => 'Trace the curves carefully.',
      _TraceLevelKind.shapes => 'Trace the shapes.',
    };
  }

  void _speakInstruction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _TraceGameStage.playing) return;
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

  void _onPanStart(DragStartDetails details) {
    if (_stage != _TraceGameStage.playing || _showFeedback) {
      return;
    }
    final local = _globalToBoard(details.globalPosition);
    if (local == null) {
      return;
    }
    final elements = _elementsForLevel(_currentLevel.kind, seed: _shuffleSeed);
    int? picked;
    for (var i = 0; i < elements.length; i++) {
      if (_completedElements.contains(i)) continue;
      if (elements[i].hitTest(local)) {
        picked = i;
        break;
      }
    }
    if (picked == null) {
      return;
    }
    setState(() {
      _activeElementIndex = picked;
      _tracePoints
        ..clear()
        ..add(local);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeElementIndex == null) return;
    final local = _globalToBoard(details.globalPosition);
    if (local == null) {
      return;
    }
    setState(() {
      _tracePoints.add(local);
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_stage != _TraceGameStage.playing || _activeElementIndex == null) {
      return;
    }
    final active = _activeElementIndex!;
    final elements = _elementsForLevel(_currentLevel.kind, seed: _shuffleSeed);
    final element = elements[active];
    final result = TracePathValidator.validateFollowPath(
      List<Offset>.from(_tracePoints),
      expectedPolyline: element.expectedPolyline,
      tolerancePx: element.tolerancePx,
      minCoverage: element.minCoverage,
      minCloseRatio: element.minCloseRatio,
      minLengthRatio: element.minLengthRatio,
    );
    if (result.isValid) {
      setState(() {
        _completedElements.add(active);
        _tracePoints.clear();
        _activeElementIndex = null;
      });
      if (_completedElements.length == elements.length) {
        await _finishRound();
      }
      return;
    }
    setState(() {
      _tracePoints.clear();
      _activeElementIndex = null;
    });
    _pendingAdvance = false;
    _showOverlay(MovePlayFeedbackKind.mistake);
  }

  Offset? _globalToBoard(Offset global) {
    final renderObject = _boardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    return renderObject.globalToLocal(global);
  }

  Future<void> _finishRound() async {
    setState(() {
      _earnedPoints += 100;
      _starsEarned += 1;
    });
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
      _savedCompletion = false;
      _completedElements.clear();
      _tracePoints.clear();
      _activeElementIndex = null;
      _showFeedback = false;
      _stage = _TraceGameStage.playing;
      _shuffleSeed++;
    });
    _speakInstruction();
  }

  void _goBackToMoveAndPlay() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    if (_stage == _TraceGameStage.celebration) {
      return SessionGuard(
        role: SessionGuardRole.parent,
        child: MovePlayCelebration(
          title: 'Wow — you did it!',
          subtitle: 'You finished all Trace rounds. Celebrate this win!',
          starsEarned: _starsEarned,
          starsTotal: _levels.length,
          badgeLabel: 'Gold Badge',
          trophyLabel: 'Gold Trophy',
          trophyColor: const Color(0xFFFFD700),
          replayLabel: 'Replay Trace Game',
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
        Center(
          child: SizedBox(
            key: _boardKey,
            width: 330,
            height: 440,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Stack(
                children: [
                  // Trace stroke, sparkle tip, and ticks.
                  AnimatedBuilder(
                    animation: _sparkleCtrl,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _TraceGuidePainter(
                          kind: _currentLevel.kind,
                          tracePoints: _tracePoints,
                          completedElements: _completedElements,
                          activeElementIndex: _activeElementIndex,
                          sparkleT: _sparkleCtrl.value,
                          seed: _shuffleSeed,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
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
                  _completedElements.clear();
                  _tracePoints.clear();
                  _activeElementIndex = null;
                  _shuffleSeed++;
                });
                _speakInstruction();
              } else {
                setState(() => _stage = _TraceGameStage.celebration);
                _saveProgressIfNeeded();
              }
            },
          ),
      ],
    );
  }
}

enum _TraceLevelKind { line, curves, shapes }

class _TraceLevel {
  const _TraceLevel({required this.prompt, required this.kind});

  final String prompt;
  final _TraceLevelKind kind;
}

class _TraceGuidePainter extends CustomPainter {
  const _TraceGuidePainter({
    required this.kind,
    required this.tracePoints,
    required this.completedElements,
    required this.activeElementIndex,
    required this.sparkleT,
    required this.seed,
  });

  final _TraceLevelKind kind;
  final List<Offset> tracePoints;
  final Set<int> completedElements;
  final int? activeElementIndex;
  final double sparkleT;
  final int seed;

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

    final done = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _TraceLevelKind.line:
        // Reference (not traceable) at top.
        canvas.drawLine(const Offset(110, 34), const Offset(210, 34), black);
        _drawLineElement(
          canvas,
          const Offset(40, 150),
          const Offset(290, 150),
          isDone: completedElements.contains(0),
          dash: dash,
          done: done,
        );
        _drawLineElement(
          canvas,
          const Offset(40, 210),
          const Offset(290, 210),
          isDone: completedElements.contains(1),
          dash: dash,
          done: done,
        );
        _drawLineElement(
          canvas,
          const Offset(40, 270),
          const Offset(290, 270),
          isDone: completedElements.contains(2),
          dash: dash,
          done: done,
        );
        _drawLineElement(
          canvas,
          const Offset(40, 330),
          const Offset(290, 330),
          isDone: completedElements.contains(3),
          dash: dash,
          done: done,
        );
      case _TraceLevelKind.curves:
        _drawReferenceWave(canvas, black);
        _drawElementsFromPolylines(canvas);
        break;
      case _TraceLevelKind.shapes:
        _drawElementsFromPolylines(canvas);
        break;
    }

    if (tracePoints.length > 1) {
      final trace = Paint()
        ..color = const Color(0xFF4EA9E3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(tracePoints.first.dx, tracePoints.first.dy);
      for (final point in tracePoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, trace);

      // Sparkle tip effect following the finger.
      final tip = tracePoints.last;
      final sparkle = Paint()
        ..style = PaintingStyle.fill
        ..color = Color.lerp(
          const Color(0xFFFFD447),
          const Color(0xFF7BC9FF),
          (sparkleT * 2) % 1.0,
        )!.withValues(alpha: 0.9);
      canvas.drawCircle(tip, 6.5 + math.sin(sparkleT * math.pi * 2) * 1.2, sparkle);
      canvas.drawCircle(tip, 2.8, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }

    _drawCompletionTicks(canvas);
  }

  void _drawReferenceWave(Canvas canvas, Paint paint) {
    final topWave = Path()
      ..moveTo(142, 44)
      ..cubicTo(150, 10, 166, 80, 176, 44)
      ..cubicTo(186, 10, 198, 74, 218, 44);
    canvas.drawPath(topWave, paint);
  }

  void _drawElementsFromPolylines(Canvas canvas) {
    final elements = _elementsForLevel(kind, seed: seed);

    final p = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final done = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < elements.length; i++) {
      final poly = elements[i].expectedPolyline;
      if (poly.length < 2) continue;
      final path = Path()..moveTo(poly.first.dx, poly.first.dy);
      for (final pt in poly.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      final isDone = completedElements.contains(i);
      canvas.drawPath(isDone ? path : _dashed(path), isDone ? done : p);
    }
  }

  Path _dashed(Path source) {
    // Cheap dashed effect by sampling path metrics and drawing small segments.
    final out = Path();
    for (final m in source.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final next = math.min(d + 14, m.length);
        out.addPath(m.extractPath(d, next), Offset.zero);
        d += 24;
      }
    }
    return out;
  }

  void _drawCompletionTicks(Canvas canvas) {
    final tickPaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void tickAt(Offset c) {
      final p = Path()
        ..moveTo(c.dx - 10, c.dy + 2)
        ..lineTo(c.dx - 2, c.dy + 10)
        ..lineTo(c.dx + 14, c.dy - 8);
      canvas.drawPath(p, tickPaint);
    }

    switch (kind) {
      case _TraceLevelKind.line:
        if (completedElements.contains(0)) tickAt(const Offset(300, 150));
        if (completedElements.contains(1)) tickAt(const Offset(300, 210));
        if (completedElements.contains(2)) tickAt(const Offset(300, 270));
        if (completedElements.contains(3)) tickAt(const Offset(300, 330));
      case _TraceLevelKind.curves:
        if (completedElements.contains(0)) tickAt(const Offset(210, 170));
        if (completedElements.contains(1)) tickAt(const Offset(178, 392));
        if (completedElements.contains(2)) tickAt(const Offset(308, 336));
      case _TraceLevelKind.shapes:
        if (completedElements.contains(0)) tickAt(const Offset(198, 212));
        if (completedElements.contains(1)) tickAt(const Offset(308, 192));
        if (completedElements.contains(2)) tickAt(const Offset(300, 328));
        if (completedElements.contains(3)) tickAt(const Offset(320, 308));
    }
  }

  void _drawLineElement(
    Canvas canvas,
    Offset start,
    Offset end, {
    required bool isDone,
    required Paint dash,
    required Paint done,
  }) {
    if (isDone) {
      canvas.drawLine(start, end, done);
    } else {
      _drawDashedLine(canvas, start, end, dash);
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

  @override
  bool shouldRepaint(covariant _TraceGuidePainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.tracePoints != tracePoints ||
        oldDelegate.completedElements != completedElements ||
        oldDelegate.activeElementIndex != activeElementIndex ||
        oldDelegate.sparkleT != sparkleT;
  }
}

class _TraceElement {
  const _TraceElement({
    required this.hitTestRect,
    required this.expectedPolyline,
    this.tolerancePx = 14,
    this.minCoverage = 0.78,
    this.minCloseRatio = 0.72,
    this.minLengthRatio = 0.70,
  });

  final Rect hitTestRect;
  final List<Offset> expectedPolyline;
  final double tolerancePx;
  final double minCoverage;
  final double minCloseRatio;
  final double minLengthRatio;

  bool hitTest(Offset p) => hitTestRect.contains(p);
}

List<_TraceElement> _elementsForLevel(_TraceLevelKind kind, {required int seed}) {
  // Small deterministic jitter to avoid static layouts while preserving playability.
  final r = math.Random((_TraceLevelKind.values.indexOf(kind) * 997) ^ (seed * 7919));
  Offset j(double maxDx, double maxDy) =>
      Offset((r.nextDouble() * 2 - 1) * maxDx, (r.nextDouble() * 2 - 1) * maxDy);

  switch (kind) {
    case _TraceLevelKind.line:
      final o0 = j(6, 4);
      final o1 = j(6, 4);
      final o2 = j(6, 4);
      final o3 = j(6, 4);
      return [
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(32, 136, 266, 34).shift(o0),
          expectedPolyline: [Offset(40, 150) + o0, Offset(290, 150) + o0],
          tolerancePx: 12,
          minCoverage: 0.86,
          minCloseRatio: 0.80,
          minLengthRatio: 0.85,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(32, 196, 266, 34).shift(o1),
          expectedPolyline: [Offset(40, 210) + o1, Offset(290, 210) + o1],
          tolerancePx: 12,
          minCoverage: 0.86,
          minCloseRatio: 0.80,
          minLengthRatio: 0.85,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(32, 256, 266, 34).shift(o2),
          expectedPolyline: [Offset(40, 270) + o2, Offset(290, 270) + o2],
          tolerancePx: 12,
          minCoverage: 0.86,
          minCloseRatio: 0.80,
          minLengthRatio: 0.85,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(32, 316, 266, 34).shift(o3),
          expectedPolyline: [Offset(40, 330) + o3, Offset(290, 330) + o3],
          tolerancePx: 12,
          minCoverage: 0.86,
          minCloseRatio: 0.80,
          minLengthRatio: 0.85,
        ),
      ];
    case _TraceLevelKind.curves:
      final o0 = j(8, 8);
      final o1 = j(8, 8);
      final o2 = j(8, 8);
      return [
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(36, 120, 190, 190).shift(o0),
          expectedPolyline: [
            Offset(70, 210),
            Offset(44, 178),
            Offset(72, 140),
            Offset(118, 160),
            Offset(140, 170),
            Offset(128, 206),
            Offset(102, 216),
            Offset(80, 226),
            Offset(84, 252),
            Offset(106, 258),
            Offset(132, 266),
            Offset(166, 246),
            Offset(186, 198),
          ].map((p) => p + o0).toList(growable: false),
          tolerancePx: 16,
          minCoverage: 0.75,
          minCloseRatio: 0.70,
          minLengthRatio: 0.68,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(30, 290, 200, 140).shift(o1),
          expectedPolyline: [
            Offset(42, 330),
            Offset(70, 300),
            Offset(108, 360),
            Offset(136, 330),
            Offset(162, 300),
            Offset(198, 360),
            Offset(226, 330),
            Offset(250, 306),
            Offset(278, 344),
            Offset(300, 330),
          ].map((p) => p + o1).toList(growable: false),
          tolerancePx: 16,
          minCoverage: 0.74,
          minCloseRatio: 0.70,
          minLengthRatio: 0.66,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(206, 276, 124, 170).shift(o2),
          expectedPolyline: [
            Offset(240, 292) + o2,
            Offset(240, 408) + o2,
            Offset(312, 408) + o2,
          ],
          tolerancePx: 16,
          minCoverage: 0.82,
          minCloseRatio: 0.70,
          minLengthRatio: 0.78,
        ),
      ];
    case _TraceLevelKind.shapes:
      final o0 = j(8, 8);
      final o1 = j(8, 8);
      final o2 = j(8, 6);
      final o3 = j(8, 8);
      return [
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(30, 112, 180, 180).shift(o0),
          expectedPolyline: [
            Offset(116, 120),
            Offset(70, 140),
            Offset(56, 196),
            Offset(76, 252),
            Offset(132, 268),
            Offset(176, 246),
            Offset(186, 194),
            Offset(164, 142),
            Offset(116, 120),
          ].map((p) => p + o0).toList(growable: false),
          tolerancePx: 16,
          minCoverage: 0.78,
          minCloseRatio: 0.72,
          minLengthRatio: 0.70,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(218, 132, 110, 110).shift(o1),
          expectedPolyline: List<Offset>.generate(40, (i) {
            final t = (math.pi * 2 * i) / 40;
            final c = const Offset(272, 186) + o1;
            return Offset(c.dx + math.cos(t) * 36, c.dy + math.sin(t) * 36);
          }),
          tolerancePx: 16,
          minCoverage: 0.74,
          minCloseRatio: 0.70,
          minLengthRatio: 0.66,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(50, 296, 250, 70).shift(o2),
          expectedPolyline: [Offset(70, 328) + o2, Offset(298, 328) + o2],
          tolerancePx: 14,
          minCoverage: 0.84,
          minCloseRatio: 0.78,
          minLengthRatio: 0.80,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(200, 270, 130, 140).shift(o3),
          expectedPolyline: [
            Offset(220, 290) + o3,
            Offset(320, 290) + o3,
            Offset(320, 390) + o3,
            Offset(220, 390) + o3,
            Offset(220, 290) + o3,
          ],
          tolerancePx: 16,
          minCoverage: 0.78,
          minCloseRatio: 0.72,
          minLengthRatio: 0.70,
        ),
      ];
  }
}
