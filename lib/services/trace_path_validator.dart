import 'package:flutter/material.dart';

enum TracePathKind { line, curves, shapes }

class TracePathValidationResult {
  const TracePathValidationResult({
    required this.isValid,
    required this.strokeLength,
    required this.insideRatio,
    required this.coveredSegments,
  });

  final bool isValid;
  final double strokeLength;
  final double insideRatio;
  final int coveredSegments;
}

class TracePathValidator {
  TracePathValidator._();

  static TracePathValidationResult validate(
    List<Offset> points,
    TracePathKind kind,
  ) {
    if (points.length < 2) {
      return const TracePathValidationResult(
        isValid: false,
        strokeLength: 0,
        insideRatio: 0,
        coveredSegments: 0,
      );
    }

    final profile = _profileFor(kind);
    final segments = _segmentsFor(kind);
    final totalLength = _strokeLength(points);

    var insideCount = 0;
    final insidePoints = <Offset>[];
    final touched = List<bool>.filled(segments.length, false);
    final segmentHitCounts = List<int>.filled(segments.length, 0);
    for (final point in points) {
      var inAnySegment = false;
      for (var i = 0; i < segments.length; i++) {
        if (segments[i](point)) {
          inAnySegment = true;
          touched[i] = true;
          segmentHitCounts[i] += 1;
        }
      }
      if (inAnySegment) {
        insideCount++;
        insidePoints.add(point);
      }
    }

    final startsInside = segments.any((segment) => segment(points.first));
    final endsInside = segments.any((segment) => segment(points.last));
    final insideRatio = insideCount / points.length;
    final coveredSegments = touched.where((value) => value).length;
    final dominantHits = segmentHitCounts.fold<int>(
      0,
      (best, count) => count > best ? count : best,
    );
    final dominantRatio = dominantHits / points.length;
    final touchedCells = _touchedCellCount(insidePoints, cellSize: 22);
    final endToEndDistance = (points.last - points.first).distance;
    final horizontalSpan = _axisSpan(insidePoints, isHorizontal: true);
    final verticalSpan = _axisSpan(insidePoints, isHorizontal: false);

    final meetsLength = totalLength >= profile.minStrokeLength;
    final meetsCoverage = insideRatio >= profile.minInsideRatio;
    final meetsSegments = coveredSegments >= profile.minCoveredSegments;
    final meetsDominant = dominantRatio >= profile.minDominantRatio;
    final meetsCells = touchedCells >= profile.minTouchedCells;
    final meetsEndToEnd = endToEndDistance >= profile.minEndToEndDistance;
    final meetsHorizontalSpan =
        profile.minHorizontalSpan == null ||
        horizontalSpan >= profile.minHorizontalSpan!;
    final meetsVerticalSpan =
        profile.maxVerticalSpan == null ||
        verticalSpan <= profile.maxVerticalSpan!;
    final meetsEnd = endsInside || insideRatio >= profile.relaxedEndInsideRatio;

    return TracePathValidationResult(
      isValid:
          startsInside &&
          meetsLength &&
          meetsCoverage &&
          meetsSegments &&
          meetsDominant &&
          meetsCells &&
          meetsEndToEnd &&
          meetsHorizontalSpan &&
          meetsVerticalSpan &&
          meetsEnd,
      strokeLength: totalLength,
      insideRatio: insideRatio,
      coveredSegments: coveredSegments,
    );
  }

  /// Validates against custom "traceable" segment hit tests.
  /// Used by Trace Game to require tracing multiple separate elements per round.
  static TracePathValidationResult validateCustom(
    List<Offset> points, {
    required List<bool Function(Offset)> segments,
    required TraceValidationProfile profile,
  }) {
    if (points.length < 2) {
      return const TracePathValidationResult(
        isValid: false,
        strokeLength: 0,
        insideRatio: 0,
        coveredSegments: 0,
      );
    }

    final totalLength = _strokeLength(points);

    var insideCount = 0;
    final insidePoints = <Offset>[];
    final touched = List<bool>.filled(segments.length, false);
    final segmentHitCounts = List<int>.filled(segments.length, 0);
    for (final point in points) {
      var inAnySegment = false;
      for (var i = 0; i < segments.length; i++) {
        if (segments[i](point)) {
          inAnySegment = true;
          touched[i] = true;
          segmentHitCounts[i] += 1;
        }
      }
      if (inAnySegment) {
        insideCount++;
        insidePoints.add(point);
      }
    }

    final startsInside = segments.any((segment) => segment(points.first));
    final endsInside = segments.any((segment) => segment(points.last));
    final insideRatio = insideCount / points.length;
    final coveredSegments = touched.where((value) => value).length;
    final dominantHits = segmentHitCounts.fold<int>(
      0,
      (best, count) => count > best ? count : best,
    );
    final dominantRatio = dominantHits / points.length;
    final touchedCells = _touchedCellCount(insidePoints, cellSize: 22);
    final endToEndDistance = (points.last - points.first).distance;
    final horizontalSpan = _axisSpan(insidePoints, isHorizontal: true);
    final verticalSpan = _axisSpan(insidePoints, isHorizontal: false);

    final meetsLength = totalLength >= profile.minStrokeLength;
    final meetsCoverage = insideRatio >= profile.minInsideRatio;
    final meetsSegments = coveredSegments >= profile.minCoveredSegments;
    final meetsDominant = dominantRatio >= profile.minDominantRatio;
    final meetsCells = touchedCells >= profile.minTouchedCells;
    final meetsEndToEnd = endToEndDistance >= profile.minEndToEndDistance;
    final meetsHorizontalSpan =
        profile.minHorizontalSpan == null ||
        horizontalSpan >= profile.minHorizontalSpan!;
    final meetsVerticalSpan =
        profile.maxVerticalSpan == null ||
        verticalSpan <= profile.maxVerticalSpan!;
    final meetsEnd = endsInside || insideRatio >= profile.relaxedEndInsideRatio;

    return TracePathValidationResult(
      isValid:
          startsInside &&
          meetsLength &&
          meetsCoverage &&
          meetsSegments &&
          meetsDominant &&
          meetsCells &&
          meetsEndToEnd &&
          meetsHorizontalSpan &&
          meetsVerticalSpan &&
          meetsEnd,
      strokeLength: totalLength,
      insideRatio: insideRatio,
      coveredSegments: coveredSegments,
    );
  }

  /// Strict "follow the path" validator.
  ///
  /// Prevents completing a shape by scribbling inside an area or tracing only a
  /// small part of it. A stroke must:
  /// - stay close to the expected polyline (within [tolerancePx])
  /// - cover enough of the expected path (coverage)
  /// - have sufficient length
  static TracePathValidationResult validateFollowPath(
    List<Offset> points, {
    required List<Offset> expectedPolyline,
    double tolerancePx = 14,
    double minCoverage = 0.78,
    double minCloseRatio = 0.72,
    double minLengthRatio = 0.70,
  }) {
    if (points.length < 2 || expectedPolyline.length < 2) {
      return const TracePathValidationResult(
        isValid: false,
        strokeLength: 0,
        insideRatio: 0,
        coveredSegments: 0,
      );
    }

    final strokeLen = _strokeLength(points);
    final expectedLen = _strokeLength(expectedPolyline);
    final samples = _resamplePolyline(expectedPolyline, step: 8);
    if (samples.length < 8) {
      return const TracePathValidationResult(
        isValid: false,
        strokeLength: 0,
        insideRatio: 0,
        coveredSegments: 0,
      );
    }

    final covered = List<bool>.filled(samples.length, false);
    var closeCount = 0;
    for (final p in points) {
      var bestI = -1;
      var bestD2 = double.infinity;
      for (var i = 0; i < samples.length; i++) {
        final d2 = (p - samples[i]).distanceSquared;
        if (d2 < bestD2) {
          bestD2 = d2;
          bestI = i;
        }
      }
      final within = bestD2 <= tolerancePx * tolerancePx;
      if (within) {
        closeCount++;
        covered[bestI] = true;
      }
    }

    // Smooth coverage: allow small gaps to still count (kids draw imperfectly).
    final smoothed = List<bool>.from(covered);
    for (var i = 1; i < smoothed.length - 1; i++) {
      if (!smoothed[i] && smoothed[i - 1] && smoothed[i + 1]) {
        smoothed[i] = true;
      }
    }

    final closeRatio = closeCount / points.length;
    final coverage = smoothed.where((v) => v).length / smoothed.length;
    final lengthOk = expectedLen <= 0 ? true : strokeLen >= expectedLen * minLengthRatio;

    return TracePathValidationResult(
      isValid: closeRatio >= minCloseRatio && coverage >= minCoverage && lengthOk,
      strokeLength: strokeLen,
      insideRatio: closeRatio,
      coveredSegments: (coverage * 10).round(),
    );
  }

  static List<Offset> _resamplePolyline(
    List<Offset> polyline, {
    required double step,
  }) {
    if (polyline.length < 2) return polyline;
    final out = <Offset>[polyline.first];
    var carry = 0.0;
    for (var i = 1; i < polyline.length; i++) {
      final a = polyline[i - 1];
      final b = polyline[i];
      final seg = b - a;
      final len = seg.distance;
      if (len <= 0.001) continue;
      final dir = seg / len;
      var t = carry;
      while (t + step <= len) {
        t += step;
        out.add(a + dir * t);
      }
      carry = (t + step) - len;
      if (carry.isNaN || carry.isInfinite) carry = 0;
      if (carry < 0) carry = 0;
      if (carry > step) carry = step;
    }
    if ((out.last - polyline.last).distance > 0.1) {
      out.add(polyline.last);
    }
    return out;
  }

  static double _strokeLength(List<Offset> points) {
    var distance = 0.0;
    for (var i = 1; i < points.length; i++) {
      distance += (points[i] - points[i - 1]).distance;
    }
    return distance;
  }

  static TraceValidationProfile _profileFor(TracePathKind kind) {
    switch (kind) {
      case TracePathKind.line:
        return const TraceValidationProfile(
          minStrokeLength: 90,
          minInsideRatio: 0.60,
          minCoveredSegments: 1,
          relaxedEndInsideRatio: 0.85,
          minDominantRatio: 0.45,
          minTouchedCells: 6,
          minEndToEndDistance: 120,
          minHorizontalSpan: 120,
          maxVerticalSpan: 48,
        );
      case TracePathKind.curves:
        return const TraceValidationProfile(
          minStrokeLength: 120,
          minInsideRatio: 0.52,
          minCoveredSegments: 1,
          relaxedEndInsideRatio: 0.78,
          minDominantRatio: 0.36,
          minTouchedCells: 6,
          minEndToEndDistance: 36,
        );
      case TracePathKind.shapes:
        return const TraceValidationProfile(
          minStrokeLength: 110,
          minInsideRatio: 0.50,
          minCoveredSegments: 1,
          relaxedEndInsideRatio: 0.76,
          minDominantRatio: 0.30,
          minTouchedCells: 5,
          minEndToEndDistance: 0,
        );
    }
  }

  static List<bool Function(Offset)> _segmentsFor(TracePathKind kind) {
    switch (kind) {
      case TracePathKind.line:
        return <bool Function(Offset)>[
          (point) => const Rect.fromLTWH(96, 18, 128, 30).contains(point),
          (point) => const Rect.fromLTWH(32, 136, 266, 34).contains(point),
          (point) => const Rect.fromLTWH(32, 196, 266, 34).contains(point),
          (point) => const Rect.fromLTWH(32, 256, 266, 34).contains(point),
          (point) => const Rect.fromLTWH(32, 316, 266, 34).contains(point),
        ];
      case TracePathKind.curves:
        return <bool Function(Offset)>[
          (point) => const Rect.fromLTWH(116, 34, 120, 72).contains(point),
          (point) => const Rect.fromLTWH(30, 116, 194, 188).contains(point),
          (point) => const Rect.fromLTWH(30, 294, 280, 138).contains(point),
        ];
      case TracePathKind.shapes:
        return <bool Function(Offset)>[
          (point) => const Rect.fromLTWH(132, 30, 98, 92).contains(point),
          (point) => const Rect.fromLTWH(16, 156, 168, 178).contains(point),
          (point) => (point - const Offset(255, 262)).distance <= 58,
          (point) => const Rect.fromLTWH(126, 372, 178, 46).contains(point),
          (point) {
            final distance = (point - const Offset(146, 410)).distance;
            return distance >= 36 && distance <= 68;
          },
        ];
    }
  }

  static int _touchedCellCount(
    List<Offset> points, {
    required double cellSize,
  }) {
    if (points.isEmpty) {
      return 0;
    }
    final buckets = <String>{};
    for (final point in points) {
      final x = (point.dx / cellSize).floor();
      final y = (point.dy / cellSize).floor();
      buckets.add('$x:$y');
    }
    return buckets.length;
  }

  static double _axisSpan(List<Offset> points, {required bool isHorizontal}) {
    if (points.isEmpty) {
      return 0;
    }
    var min = isHorizontal ? points.first.dx : points.first.dy;
    var max = min;
    for (final point in points.skip(1)) {
      final value = isHorizontal ? point.dx : point.dy;
      if (value < min) {
        min = value;
      }
      if (value > max) {
        max = value;
      }
    }
    return max - min;
  }
}

class TraceValidationProfile {
  const TraceValidationProfile({
    required this.minStrokeLength,
    required this.minInsideRatio,
    required this.minCoveredSegments,
    required this.relaxedEndInsideRatio,
    required this.minDominantRatio,
    required this.minTouchedCells,
    required this.minEndToEndDistance,
    this.minHorizontalSpan,
    this.maxVerticalSpan,
  });

  final double minStrokeLength;
  final double minInsideRatio;
  final int minCoveredSegments;
  final double relaxedEndInsideRatio;
  final double minDominantRatio;
  final int minTouchedCells;
  final double minEndToEndDistance;
  final double? minHorizontalSpan;
  final double? maxVerticalSpan;
}
