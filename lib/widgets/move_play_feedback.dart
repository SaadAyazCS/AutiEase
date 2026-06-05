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
    final softAccent = Color.alphaBlend(
      _accent.withValues(alpha: 0.13),
      Colors.white,
    );
    final softBlue = Color.alphaBlend(
      const Color(0xFFEAF6FF).withValues(alpha: 0.84),
      Colors.white,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 330,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, softAccent, softBlue],
          ),
        ),
        child: Stack(
          children: [
            if (!lowStimulationMode)
              Positioned(
                right: -18,
                top: -20,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 92,
                  color: _accent.withValues(alpha: 0.12),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: _accent, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.24),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 48, color: _accent),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF12213D),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF334765),
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (kind == MovePlayFeedbackKind.success &&
                      !lowStimulationMode) ...[
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD447),
                          size: 30,
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD447),
                          size: 34,
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD447),
                          size: 30,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onPrimaryAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
