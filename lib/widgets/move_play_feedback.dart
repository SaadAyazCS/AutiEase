import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Friendly feedback overlay for Move & Play games.
class MovePlayFeedbackOverlay extends StatelessWidget {
  const MovePlayFeedbackOverlay({
    super.key,
    required this.kind,
    required this.onPrimaryAction,
    this.primaryLabel = 'Try again',
    this.message,
    this.lowStimulationMode = false,
  });

  final MovePlayFeedbackKind kind;
  final VoidCallback onPrimaryAction;
  final String primaryLabel;
  final String? message;
  final bool lowStimulationMode;

  String get _title {
    switch (kind) {
      case MovePlayFeedbackKind.mistake:
        return 'Nice try!';
      case MovePlayFeedbackKind.success:
        return 'Great job!';
    }
  }

  String get _subtitle {
    switch (kind) {
      case MovePlayFeedbackKind.mistake:
        return message ??
            _encouragingMistakeLines[math.Random().nextInt(
              _encouragingMistakeLines.length,
            )];
      case MovePlayFeedbackKind.success:
        return message ??
            _encouragingSuccessLines[math.Random().nextInt(
              _encouragingSuccessLines.length,
            )];
    }
  }

  IconData get _icon {
    switch (kind) {
      case MovePlayFeedbackKind.mistake:
        return Icons.sentiment_satisfied_alt_rounded;
      case MovePlayFeedbackKind.success:
        return Icons.emoji_events_rounded;
    }
  }

  Color get _accent {
    switch (kind) {
      case MovePlayFeedbackKind.mistake:
        return const Color(0xFFFFA260);
      case MovePlayFeedbackKind.success:
        return const Color(0xFF4EA9E3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: lowStimulationMode ? 0.16 : 0.25),
        child: Center(
          child: Container(
            width: 330,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withValues(alpha: 0.12),
                    border: Border.all(color: _accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_icon, size: 44, color: _accent),
                ),
                const SizedBox(height: 14),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF12213D),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4B5563),
                  ),
                ),
                if (kind == MovePlayFeedbackKind.success &&
                    !lowStimulationMode) ...[
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD447),
                        size: 34,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '+1 star',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A2D4B),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPrimaryAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum MovePlayFeedbackKind { mistake, success }

const _encouragingMistakeLines = <String>[
  'That was a good try. Let’s do it again.',
  'Almost! Try one more time.',
  'No worries — you can do it!',
  'Great effort. Let’s try again.',
];

const _encouragingSuccessLines = <String>[
  'You did it! Keep going!',
  'Awesome! Let’s play the next one.',
  'Fantastic work!',
  'Woohoo! Next round!',
];
