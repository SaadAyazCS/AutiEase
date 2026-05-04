import 'package:flutter/foundation.dart';

/// One practice target (alphabet, word, or sentence).
@immutable
class SpeakLearnItem {
  const SpeakLearnItem({
    required this.id,
    required this.displayText,
    required this.speakText,
    this.tag,
    this.imageUrl,
    this.iconEmoji,
  });

  final String id;
  final String displayText;
  final String speakText;
  /// Small label above sentence card (design: e.g. REQUESTS).
  final String? tag;
  final String? imageUrl;
  final String? iconEmoji;
}
