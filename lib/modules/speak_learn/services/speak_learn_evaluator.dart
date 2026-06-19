import '../models/speak_learn_level_kind.dart';

/// Normalizes recognized speech and checks against the expected phrase.
class SpeakLearnEvaluator {
  SpeakLearnEvaluator._();

  static String normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s']"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isCorrect({
    required SpeakLearnLevelKind kind,
    required String expected,
    required String heard,
  }) {
    final e = normalize(expected);
    final h = normalize(heard);
    if (h.isEmpty) {
      return false;
    }
    switch (kind) {
      case SpeakLearnLevelKind.alphabets:
        final symbol = expected.trim().toUpperCase();
        if (symbol.length == 1) {
          final first = h.replaceAll(' ', '');
          if (first.isEmpty) {
            return false;
          }
          // "a", "the alphabet a", "the letter a" (legacy phrasing still accepted)
          if (first.startsWith(symbol.toLowerCase())) {
            return true;
          }
          if (h.contains('alphabet $symbol'.toLowerCase())) {
            return true;
          }
          if (h.contains('letter $symbol'.toLowerCase())) {
            return true;
          }
          if (h == symbol.toLowerCase()) {
            return true;
          }
        }
        return h.contains(e) || e.contains(h);
      case SpeakLearnLevelKind.words:
        return h.contains(e) || e.split(' ').every((w) => w.isEmpty || h.contains(w));
      case SpeakLearnLevelKind.sentences:
        final expTokens = e.split(' ').where((t) => t.length > 1).toList();
        if (expTokens.isEmpty) {
          return h.contains(e);
        }
        var hits = 0;
        for (final t in expTokens) {
          if (h.contains(t)) {
            hits++;
          }
        }
        final ratio = hits / expTokens.length;
        return ratio >= 0.65 || h.contains(e);
    }
  }

  static String guidanceHint({
    required SpeakLearnLevelKind kind,
    required String expected,
  }) {
    switch (kind) {
      case SpeakLearnLevelKind.alphabets:
        final symbol = expected.trim().toUpperCase();
        if (symbol.length == 1) {
          return "Try saying 'the alphabet $symbol'";
        }
        return "Try saying '$expected'";
      case SpeakLearnLevelKind.words:
        return 'Try saying the word clearly: $expected';
      case SpeakLearnLevelKind.sentences:
        return 'Try saying the full sentence clearly.';
    }
  }
}
