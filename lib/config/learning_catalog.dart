import 'package:flutter/material.dart';

class LearningCategoryDefinition {
  const LearningCategoryDefinition({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String key;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
}

class LearningCatalog {
  LearningCatalog._();

  static const orderedCategoryKeys = <String>[
    'move_play',
    'speak_learn',
    'focus_games',
  ];

  static const definitions = <String, LearningCategoryDefinition>{
    'move_play': LearningCategoryDefinition(
      key: 'move_play',
      title: 'Move & Play',
      subtitle: 'Tap, drag, and trace style activities',
      color: Color(0xFFF3B7B8),
      icon: Icons.touch_app_outlined,
    ),
    'speak_learn': LearningCategoryDefinition(
      key: 'speak_learn',
      title: 'Speak & Learn',
      subtitle: 'Alphabets, words, and sentence practice',
      color: Color(0xFFB6EE9A),
      icon: Icons.record_voice_over_outlined,
    ),
    'focus_games': LearningCategoryDefinition(
      key: 'focus_games',
      title: 'Focus Games',
      subtitle: 'Find it, match it, and hold it',
      color: Color(0xFFC1E8D9),
      icon: Icons.center_focus_strong_outlined,
    ),
  };

  static LearningCategoryDefinition forKey(
    String key, {
    String? fallbackTitle,
  }) {
    final normalized = key.trim().toLowerCase();
    return definitions[normalized] ??
        LearningCategoryDefinition(
          key: normalized,
          title: fallbackTitle?.trim().isNotEmpty == true
              ? fallbackTitle!.trim()
              : 'Other',
          subtitle: 'Assigned learning games',
          color: const Color(0xFFE8E8E8),
          icon: Icons.games_outlined,
        );
  }
}
