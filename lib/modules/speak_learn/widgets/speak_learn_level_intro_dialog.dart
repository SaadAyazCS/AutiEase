import 'package:flutter/material.dart';

import '../models/speak_learn_level_kind.dart';

/// Shown before starting a Speak & Learn level (after hub tap or completion replay).
Future<bool> showSpeakLearnLevelIntroDialog(
  BuildContext context, {
  required SpeakLearnLevelKind kind,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _titleFor(kind),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Color(0xFF12213D),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tips for everyone:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF1A2D4B),
                ),
              ),
              const SizedBox(height: 8),
              _bullet('Speak clearly and a little louder than normal.'),
              _bullet('Sit in a quiet place so the app can hear you.'),
              _bullet('Make sure microphone permission is turned on for this app.'),
              const SizedBox(height: 14),
              Text(
                _levelHeading(kind),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF1A2D4B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _levelBody(kind),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Pro tip:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF1A2D4B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _proTipForKind(kind),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4EA9E3),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: const Text("Let's go!"),
          ),
        ],
      );
    },
  );
  return result == true;
}

String _titleFor(SpeakLearnLevelKind kind) {
  return switch (kind) {
    SpeakLearnLevelKind.alphabets => 'Ready for alphabets?',
    SpeakLearnLevelKind.words => 'Ready for words?',
    SpeakLearnLevelKind.sentences => 'Ready for sentences?',
  };
}

String _levelHeading(SpeakLearnLevelKind kind) {
  return switch (kind) {
    SpeakLearnLevelKind.alphabets => 'For alphabets:',
    SpeakLearnLevelKind.words => 'For words:',
    SpeakLearnLevelKind.sentences => 'For sentences:',
  };
}

String _levelBody(SpeakLearnLevelKind kind) {
  return switch (kind) {
    SpeakLearnLevelKind.alphabets =>
      'Say each alphabet sound clearly. Take a breath between each one if you need to.',
    SpeakLearnLevelKind.words =>
      'Say the whole word slowly and clearly. Take your time — clear beats fast.',
    SpeakLearnLevelKind.sentences =>
      'Say the full sentence in a natural, steady pace. Try not to skip small words.',
  };
}

String _proTipForKind(SpeakLearnLevelKind kind) {
  return switch (kind) {
    SpeakLearnLevelKind.alphabets =>
      'If the app does not recognize you, try a short phrase such as “the alphabet A” or “it is A” instead of only saying “A”.',
    SpeakLearnLevelKind.words =>
      'If a word is missed, try tucking it into a short phrase — for example “the word is apple” or “I said apple” — then say the word again clearly.',
    SpeakLearnLevelKind.sentences =>
      'If the sentence is missed, say it once more slowly. You can also start with “I want to say…” and then speak the full sentence.',
  };
}

Widget _bullet(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: TextStyle(fontWeight: FontWeight.w800)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
      ],
    ),
  );
}
