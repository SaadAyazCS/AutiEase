import 'package:flutter_test/flutter_test.dart';

import 'package:autiease/services/trace_path_validator.dart';

void main() {
  group('TracePathValidator', () {
    test('rejects random scribble for line level', () {
      final scribble = <Offset>[
        const Offset(250, 60),
        const Offset(280, 90),
        const Offset(300, 120),
        const Offset(280, 140),
        const Offset(260, 110),
        const Offset(300, 180),
      ];

      final result = TracePathValidator.validate(scribble, TracePathKind.line);
      expect(result.isValid, isFalse);
    });

    test('accepts a valid line trace with enough coverage', () {
      final points = <Offset>[
        const Offset(40, 150),
        const Offset(90, 150),
        const Offset(140, 150),
        const Offset(190, 150),
        const Offset(240, 150),
        const Offset(280, 150),
      ];

      final result = TracePathValidator.validate(points, TracePathKind.line);
      expect(result.isValid, isTrue);
      expect(result.coveredSegments, greaterThanOrEqualTo(1));
    });

    test('rejects short traces even when inside target zones', () {
      final shortTrace = <Offset>[
        const Offset(40, 150),
        const Offset(70, 150),
        const Offset(90, 150),
      ];

      final result = TracePathValidator.validate(
        shortTrace,
        TracePathKind.line,
      );
      expect(result.isValid, isFalse);
    });

    test('rejects zig-zag scribble in line lane', () {
      final scribble = <Offset>[
        const Offset(40, 150),
        const Offset(90, 168),
        const Offset(130, 140),
        const Offset(170, 170),
        const Offset(220, 138),
        const Offset(280, 172),
      ];

      final result = TracePathValidator.validate(scribble, TracePathKind.line);
      expect(result.isValid, isFalse);
    });
  });
}
