import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/learning_metrics_service.dart';
import '../services/play_preferences_service.dart';
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
  int _wrongAttemptsThisLevel = 0;
  double? _lastTraceAccuracy;
  PlayPreferences _playPreferences = PlayPreferences.defaults;
  final PlayPreferencesService _playPreferencesService =
      const PlayPreferencesService();
  final LearningMetricsService _metricsService = const LearningMetricsService();
  final GameplayMetricsTracker _metricsTracker = GameplayMetricsTracker();

  final TtsService _tts = TtsService();
  bool _showFeedback = false;
  MovePlayFeedbackKind _feedbackKind = MovePlayFeedbackKind.mistake;
  bool _pendingAdvance = false;
  late final AnimationController _sparkleCtrl;

  _TraceLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    return _stage == _TraceGameStage.playing
        ? _instructionText()
        : 'Great Job!';
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
    final playPreferences = await _playPreferencesService.getCurrent();
    if (!mounted) return;
    setState(() => _playPreferences = playPreferences);
    if (playPreferences.lowStimulationMode) {
      _sparkleCtrl.stop();
    }
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
      _TraceLevelKind.line => 'Trace the lines',
      _TraceLevelKind.curves => 'Trace the curves',
      _TraceLevelKind.shapes => 'Trace the shapes',
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
      tolerancePx: _adaptiveTolerance(element.tolerancePx),
      minCoverage: _adaptiveMinCoverage(element.minCoverage),
      minCloseRatio: _adaptiveMinCloseRatio(element.minCloseRatio),
      minLengthRatio: _adaptiveMinLengthRatio(element.minLengthRatio),
    );
    _lastTraceAccuracy = result.insideRatio;
    _metricsTracker.markAttempt(wrong: !result.isValid);
    if (result.isValid) {
      unawaited(_recordTraceMetric(outcome: 'trace_completed'));
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
    _wrongAttemptsThisLevel += 1;
    unawaited(_recordTraceMetric(outcome: 'trace_missed'));
    setState(() {
      _tracePoints.clear();
      _activeElementIndex = null;
    });
    _pendingAdvance = false;
    _showOverlay(MovePlayFeedbackKind.mistake);
  }

  double _adaptiveTolerance(double base) {
    final delta = _adaptiveTraceDelta;
    return (base + (-delta * 2)).clamp(10.0, 22.0).toDouble();
  }

  double _adaptiveMinCoverage(double base) {
    final delta = _adaptiveTraceDelta;
    return (base + delta * 0.04).clamp(0.62, 0.90).toDouble();
  }

  double _adaptiveMinCloseRatio(double base) {
    final delta = _adaptiveTraceDelta;
    return (base + delta * 0.04).clamp(0.58, 0.84).toDouble();
  }

  double _adaptiveMinLengthRatio(double base) {
    final delta = _adaptiveTraceDelta;
    return (base + delta * 0.04).clamp(0.56, 0.88).toDouble();
  }

  int get _adaptiveTraceDelta => _playPreferences.adaptiveDelta(
    wrongAttempts: _wrongAttemptsThisLevel,
    successCount: _starsEarned,
  );

  Future<void> _recordTraceMetric({required String outcome}) {
    return _metricsService.recordGameplayMetric(
      childId: widget.childId,
      gameType: 'trace_game',
      moduleId: widget.module.id,
      roundId: 'trace-${_levelIndex + 1}-${_activeElementIndex ?? 0}',
      outcome: outcome,
      attempts: _metricsTracker.attempts,
      wrongSelections: _metricsTracker.wrongSelections,
      responseTimeMs: _metricsTracker.responseTimeMs,
      traceAccuracy: _lastTraceAccuracy,
      difficulty: _playPreferences.difficulty,
      lowStimulationMode: _playPreferences.lowStimulationMode,
      adaptiveLevel: _adaptiveTraceDelta,
      metadata: {
        'prompt': _currentLevel.prompt,
        'completedElements': _completedElements.length,
      },
    );
  }

  String get _traceWrongHint {
    return switch (_currentLevel.kind) {
      _TraceLevelKind.line =>
        'Good try. Start from the green dot and follow the line to the red dot.',
      _TraceLevelKind.curves =>
        'Good try. Follow the arrows from the green dot.',
      _TraceLevelKind.shapes =>
        'Good try. Trace one shape from its green dot to its red dot.',
    };
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
        metadata: const {'source': 'trace_game'},
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
      _lastTraceAccuracy = null;
      _metricsTracker.reset();
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
          trophyColor: const Color(0xFFFFD700),
          replayLabel: 'Replay Trace Game',
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
                          sparkleT: _playPreferences.lowStimulationMode
                              ? 0
                              : _sparkleCtrl.value,
                          seed: _shuffleSeed,
                          lowStimulationMode:
                              _playPreferences.lowStimulationMode,
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
            primaryLabel: _feedbackKind == MovePlayFeedbackKind.success
                ? 'Next'
                : 'Try again',
            message: _feedbackKind == MovePlayFeedbackKind.mistake
                ? _traceWrongHint
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
                  _completedElements.clear();
                  _tracePoints.clear();
                  _activeElementIndex = null;
                  _wrongAttemptsThisLevel = 0;
                  _lastTraceAccuracy = null;
                  _metricsTracker.reset();
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
    required this.lowStimulationMode,
  });

  final _TraceLevelKind kind;
  final List<Offset> tracePoints;
  final Set<int> completedElements;
  final int? activeElementIndex;
  final double sparkleT;
  final int seed;
  final bool lowStimulationMode;

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
        final midCurve = Path()
          ..moveTo(42, 60)
          ..cubicTo(30, 38, 52, 22, 70, 34)
          ..cubicTo(92, 48, 102, 24, 120, 30)
          ..cubicTo(144, 38, 118, 76, 98, 88)
          ..cubicTo(82, 100, 74, 124, 82, 136)
          ..cubicTo(92, 150, 124, 148, 142, 138);
        _drawDashedPath(
          canvas,
          midCurve,
          completedElements.contains(0) ? done : dash,
        );
        _drawArrow(
          canvas,
          const Offset(142, 138),
          const Offset(160, 132),
          black,
        );

        final bottomPath = Path()
          ..moveTo(42, 220)
          ..lineTo(42, 302)
          ..quadraticBezierTo(42, 312, 52, 312)
          ..lineTo(154, 312);
        _drawDashedPath(
          canvas,
          bottomPath,
          completedElements.contains(1) ? done : dash,
        );
        _drawArrow(
          canvas,
          const Offset(154, 312),
          const Offset(170, 312),
          black,
        );

        final zigZagPath = Path()
          ..moveTo(222, 202)
          ..lineTo(262, 242)
          ..lineTo(222, 282)
          ..lineTo(262, 322)
          ..lineTo(222, 362)
          ..lineTo(262, 402);
        _drawDashedPath(
          canvas,
          zigZagPath,
          completedElements.contains(2) ? done : dash,
        );
        _drawArrow(
          canvas,
          const Offset(262, 402),
          const Offset(280, 402),
          black,
        );
        break;
      case _TraceLevelKind.shapes:
        final square = Path()..addRect(const Rect.fromLTWH(20, 80, 160, 160));
        _drawDashedPath(
          canvas,
          square,
          completedElements.contains(0) ? done : dash,
          dashLength: 16,
          gapLength: 8,
        );

        final triangle = Path()
          ..moveTo(240, 260)
          ..lineTo(180, 340)
          ..lineTo(300, 340)
          ..close();
        _drawDashedPath(
          canvas,
          triangle,
          completedElements.contains(1) ? done : dash,
          dashLength: 16,
          gapLength: 8,
        );

        final dots = Paint()
          ..style = PaintingStyle.fill
          ..color = completedElements.contains(2)
              ? const Color(0xFF9AA4B2)
              : Colors.black;
        final center = const Offset(82, 320);
        for (var i = 0; i < 14; i++) {
          final theta = (math.pi * 2 * i) / 14;
          final point = Offset(
            center.dx + math.cos(theta) * 46,
            center.dy + math.sin(theta) * 46,
          );
          canvas.drawCircle(point, 6, dots);
        }
        break;
    }

    _drawStartEndGuides(canvas);
    _drawActivePathFill(canvas);

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

      if (!lowStimulationMode) {
        final tip = tracePoints.last;
        final sparkle = Paint()
          ..style = PaintingStyle.fill
          ..color = Color.lerp(
            const Color(0xFFFFD447),
            const Color(0xFF7BC9FF),
            (sparkleT * 2) % 1.0,
          )!.withValues(alpha: 0.9);
        canvas.drawCircle(
          tip,
          6.5 + math.sin(sparkleT * math.pi * 2) * 1.2,
          sparkle,
        );
        canvas.drawCircle(
          tip,
          2.8,
          Paint()..color = Colors.white.withValues(alpha: 0.9),
        );
      }
    }

    _drawCompletionTicks(canvas);
  }

  void _drawStartEndGuides(Canvas canvas) {
    final elements = _elementsForLevel(kind, seed: seed);
    final startPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF2EBD68);
    final endPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE85252);
    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4EA9E3);

    for (var i = 0; i < elements.length; i++) {
      if (completedElements.contains(i)) {
        continue;
      }
      final points = elements[i].expectedPolyline;
      if (points.length < 2) {
        continue;
      }
      final isClosedPath = (points.first - points.last).distance <= 1.5;
      canvas.drawCircle(points.first, 7, startPaint);
      if (!isClosedPath) {
        canvas.drawCircle(points.last, 7, endPaint);
      }
      if (!lowStimulationMode) {
        final arrowStart = points[math.max(0, points.length ~/ 2 - 1)];
        final arrowEnd =
            points[math.min(points.length - 1, points.length ~/ 2)];
        _drawArrow(canvas, arrowStart, arrowEnd, arrowPaint);
      }
    }
  }

  void _drawActivePathFill(Canvas canvas) {
    final active = activeElementIndex;
    if (active == null || tracePoints.length < 2) {
      return;
    }
    final elements = _elementsForLevel(kind, seed: seed);
    if (active < 0 || active >= elements.length) {
      return;
    }
    final points = elements[active].expectedPolyline;
    if (points.length < 2) {
      return;
    }
    final expectedLength = TracePathValidator.strokeLengthForMetrics(points);
    if (expectedLength <= 0) {
      return;
    }
    final progress =
        (TracePathValidator.strokeLengthForMetrics(tracePoints) /
                expectedLength)
            .clamp(0.0, 1.0)
            .toDouble();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF4EA9E3).withValues(alpha: 0.28);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
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
        if (completedElements.contains(0)) tickAt(const Offset(142, 138));
        if (completedElements.contains(1)) tickAt(const Offset(154, 312));
        if (completedElements.contains(2)) tickAt(const Offset(262, 402));
      case _TraceLevelKind.shapes:
        if (completedElements.contains(0)) tickAt(const Offset(180, 160));
        if (completedElements.contains(1)) tickAt(const Offset(240, 340));
        if (completedElements.contains(2)) tickAt(const Offset(82, 320));
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
        oldDelegate.sparkleT != sparkleT ||
        oldDelegate.lowStimulationMode != lowStimulationMode;
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

List<_TraceElement> _elementsForLevel(
  _TraceLevelKind kind, {
  required int seed,
}) {
  // Small deterministic jitter to avoid static layouts while preserving playability.
  final r = math.Random(
    (_TraceLevelKind.values.indexOf(kind) * 997) ^ (seed * 7919),
  );
  Offset j(double maxDx, double maxDy) => Offset(
    (r.nextDouble() * 2 - 1) * maxDx,
    (r.nextDouble() * 2 - 1) * maxDy,
  );

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
      final o0 = j(4, 4);
      final o1 = j(4, 4);
      final o2 = j(4, 4);
      return [
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(40, 30, 200, 120).shift(o0),
          expectedPolyline: [
            Offset(42, 60),
            Offset(70, 34),
            Offset(120, 30),
            Offset(98, 88),
            Offset(82, 136),
            Offset(142, 138),
          ].map((p) => p + o0).toList(growable: false),
          tolerancePx: 20,
          minCoverage: 0.75,
          minCloseRatio: 0.70,
          minLengthRatio: 0.70,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(40, 220, 140, 100).shift(o1),
          expectedPolyline: [
            Offset(42, 220),
            Offset(42, 302),
            Offset(52, 312),
            Offset(154, 312),
          ].map((p) => p + o1).toList(growable: false),
          tolerancePx: 20,
          minCoverage: 0.73,
          minCloseRatio: 0.68,
          minLengthRatio: 0.68,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(210, 200, 70, 210).shift(o2),
          expectedPolyline: [
            Offset(222, 202),
            Offset(262, 242),
            Offset(222, 282),
            Offset(262, 322),
            Offset(222, 362),
            Offset(262, 402),
          ].map((p) => p + o2).toList(growable: false),
          tolerancePx: 22,
          minCoverage: 0.68,
          minCloseRatio: 0.65,
          minLengthRatio: 0.62,
        ),
      ];
    case _TraceLevelKind.shapes:
      final o0 = j(8, 8);
      final o1 = j(8, 8);
      final o2 = j(8, 8);
      return [
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(20, 80, 160, 160).shift(o0),
          expectedPolyline: [
            Offset(20, 80) + o0,
            Offset(180, 80) + o0,
            Offset(180, 240) + o0,
            Offset(20, 240) + o0,
            Offset(20, 80) + o0,
          ],
          tolerancePx: 18,
          minCoverage: 0.75,
          minCloseRatio: 0.70,
          minLengthRatio: 0.68,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(180, 260, 120, 80).shift(o1),
          expectedPolyline: [
            Offset(240, 260) + o1,
            Offset(180, 340) + o1,
            Offset(300, 340) + o1,
            Offset(240, 260) + o1,
          ],
          tolerancePx: 18,
          minCoverage: 0.75,
          minCloseRatio: 0.70,
          minLengthRatio: 0.68,
        ),
        _TraceElement(
          hitTestRect: const Rect.fromLTWH(36, 274, 92, 92).shift(o2),
          expectedPolyline: List<Offset>.generate(14, (i) {
            final theta = (math.pi * 2 * i) / 14;
            final center = const Offset(82, 320) + o2;
            return Offset(
              center.dx + math.cos(theta) * 46,
              center.dy + math.sin(theta) * 46,
            );
          }),
          tolerancePx: 18,
          minCoverage: 0.70,
          minCloseRatio: 0.65,
          minLengthRatio: 0.62,
        ),
      ];
  }
}
