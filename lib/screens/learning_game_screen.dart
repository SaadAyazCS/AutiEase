import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/tts_service.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/move_play_celebration.dart';
import '../widgets/session_guard.dart';

class LearningGameScreen extends StatefulWidget {
  const LearningGameScreen({
    super.key,
    required this.childId,
    required this.module,
  });

  final String childId;
  final LearningModuleModel module;

  @override
  State<LearningGameScreen> createState() => _LearningGameScreenState();
}

enum _LearningGameStage {
  loading,
  playing,
  wrongOption,
  levelCompleted,
  allLevelsCompleted,
  error,
}

enum _LearningGameVariant { generic, findIt, matchIt, holdIt, words, sentences }

class _LearningGameScreenState extends State<LearningGameScreen> {
  final TtsService _tts = TtsService();
  late final _LearningGameVariant _variant;

  _LearningGameStage _stage = _LearningGameStage.loading;
  List<_QuizLevel> _levels = const [];
  List<_FocusRound> _focusRounds = const [];
  int _levelIndex = 0;
  int _earnedPoints = 0;
  int _earnedStars = 0;
  int _wrongAttempts = 0;
  int _replaySeed = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;
  bool _isResolvingSelection = false;
  String? _error;

  _QuizLevel get _currentLevel => _levels[_levelIndex];
  _FocusRound get _currentFocusRound => _focusRounds[_levelIndex];
  bool get _isFocusGame =>
      _variant == _LearningGameVariant.findIt ||
      _variant == _LearningGameVariant.matchIt ||
      _variant == _LearningGameVariant.holdIt;

  @override
  void initState() {
    super.initState();
    _variant = _variantForModule(widget.module);
    _loadGame();
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  String get _title {
    switch (_stage) {
      case _LearningGameStage.playing:
        return _playingTitle();
      case _LearningGameStage.wrongOption:
        return widget.module.title;
      case _LearningGameStage.levelCompleted:
      case _LearningGameStage.allLevelsCompleted:
        return 'Great Job!';
      case _LearningGameStage.loading:
      case _LearningGameStage.error:
        return widget.module.title;
    }
  }

  Future<void> _loadGame() async {
    setState(() {
      _stage = _LearningGameStage.loading;
      _error = null;
      _levels = const [];
      _focusRounds = const [];
      _levelIndex = 0;
      _earnedPoints = 0;
      _earnedStars = 0;
      _wrongAttempts = 0;
      _savedCompletion = false;
      _isSavingProgress = false;
      _isResolvingSelection = false;
    });

    try {
      await _tts.init();
      if (_isFocusGame) {
        final focusRounds = _buildFocusRounds(_variant, _replaySeed);
        if (!mounted) {
          return;
        }
        setState(() {
          _focusRounds = focusRounds;
          _stage = _LearningGameStage.playing;
        });
        await _speakCurrentPrompt();
        return;
      }

      final allItems = await AppRepositories.content.getAllContentItems();
      final scopedItems = _resolveModuleItems(
        module: widget.module,
        allItems: allItems,
      );
      if (scopedItems.length < 2) {
        throw StateError(
          'Not enough game content. Add more content_items in Firestore.',
        );
      }

      final levels = _buildLevels(scopedItems, _variant);
      if (levels.isEmpty) {
        throw StateError('Unable to build levels for this game.');
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _levels = levels;
        _stage = _LearningGameStage.playing;
      });
      await _speakCurrentPrompt();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _stage = _LearningGameStage.error;
      });
    }
  }

  _LearningGameVariant _variantForModule(LearningModuleModel module) {
    final candidates = <String>[
      module.gameTypeKey,
      module.id,
      module.title,
    ].map(_normalizeKey).toList();

    bool has(String token) =>
        candidates.any((value) => value == token || value.contains(token));

    if (has('find_it') || has('find')) {
      return _LearningGameVariant.findIt;
    }
    if (has('match_it') || has('match')) {
      return _LearningGameVariant.matchIt;
    }
    if (has('hold_it') || has('hold')) {
      return _LearningGameVariant.holdIt;
    }
    if (has('sentence') || has('sentences')) {
      return _LearningGameVariant.sentences;
    }
    if (has('word') || has('words')) {
      return _LearningGameVariant.words;
    }
    return _LearningGameVariant.generic;
  }

  String _normalizeKey(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  List<ContentItem> _resolveModuleItems({
    required LearningModuleModel module,
    required List<ContentItem> allItems,
  }) {
    final rawRefs = module.assetRefs.map((ref) => ref.trim()).toList();
    final categoryIds = <String>{};
    final itemIds = <String>{};
    final keywords = <String>{};

    for (final ref in rawRefs) {
      if (ref.isEmpty) {
        continue;
      }
      final lowerRef = ref.toLowerCase();
      if (lowerRef.startsWith('category:')) {
        categoryIds.add(lowerRef.substring('category:'.length));
        continue;
      }
      if (lowerRef.startsWith('item:')) {
        itemIds.add(lowerRef.substring('item:'.length));
        continue;
      }
      keywords.add(lowerRef);
      categoryIds.add(lowerRef);
      itemIds.add(lowerRef);
    }

    List<ContentItem> filtered = allItems.where((item) {
      final lowerId = item.id.toLowerCase();
      final lowerCategory = item.categoryId.toLowerCase();
      return categoryIds.contains(lowerCategory) || itemIds.contains(lowerId);
    }).toList();

    if (filtered.isEmpty && keywords.isNotEmpty) {
      filtered = allItems.where((item) {
        final haystack =
            '${item.title} ${item.subtitle} ${item.audioText} ${item.tags.join(' ')}'
                .toLowerCase();
        return keywords.any(haystack.contains);
      }).toList();
    }

    if (filtered.length < 2) {
      final moduleKeywords = _moduleKeywords(module);
      if (moduleKeywords.isNotEmpty) {
        filtered = allItems.where((item) {
          final haystack =
              '${item.id} ${item.categoryId} ${item.title} ${item.subtitle} '
                      '${item.audioText} ${item.tags.join(' ')}'
                  .toLowerCase();
          return moduleKeywords.any(haystack.contains);
        }).toList();
      }
    }

    if (filtered.isEmpty) {
      filtered = List<ContentItem>.from(allItems);
    }

    final deduped = <String, ContentItem>{
      for (final item in filtered) item.id: item,
    };
    return deduped.values.toList();
  }

  List<String> _moduleKeywords(LearningModuleModel module) {
    final stopWords = <String>{
      'game',
      'games',
      'module',
      'learn',
      'learning',
      'focus',
      'speak',
      'play',
      'the',
      'and',
      'it',
    };
    final combined = '${module.id} ${module.gameTypeKey} ${module.title}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    return combined
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 2 && !stopWords.contains(token))
        .toSet()
        .toList();
  }

  List<_QuizLevel> _buildLevels(
    List<ContentItem> items,
    _LearningGameVariant variant,
  ) {
    final random = Random();
    final shuffledItems = List<ContentItem>.from(items)..shuffle(random);
    final levelCount = min(6, shuffledItems.length);
    final prompts = shuffledItems.take(levelCount).toList();

    return prompts.map((prompt) {
      final distractors = items.where((item) => item.id != prompt.id).toList()
        ..shuffle(random);
      final optionCount = variant == _LearningGameVariant.sentences
          ? min(3, items.length)
          : min(4, items.length);
      final optionItems = <ContentItem>[
        prompt,
        ...distractors.take(optionCount - 1),
      ]..shuffle(random);

      final options = variant == _LearningGameVariant.sentences
          ? optionItems
                .map(
                  (item) => _QuizOption(
                    id: item.id,
                    label: 'I see ${item.title.toLowerCase()}.',
                    subtitle: item.subtitle,
                    imageUrl: item.imageUrl,
                  ),
                )
                .toList()
          : optionItems
                .map(
                  (item) => _QuizOption(
                    id: item.id,
                    label: variant == _LearningGameVariant.words
                        ? item.title.toUpperCase()
                        : item.title,
                    subtitle: item.subtitle,
                    imageUrl: item.imageUrl,
                  ),
                )
                .toList();

      return _QuizLevel(
        promptText: _promptTextFor(variant, prompt),
        promptHint: _promptHintFor(variant, prompt),
        promptImageUrl: prompt.imageUrl,
        promptVisualKey: '${prompt.title} ${prompt.subtitle}',
        promptSpeakText: variant == _LearningGameVariant.sentences
            ? 'Choose the correct sentence.'
            : (prompt.audioText.isEmpty ? prompt.title : prompt.audioText),
        options: options,
        correctOptionIndex: options.indexWhere(
          (option) => option.id == prompt.id,
        ),
      );
    }).toList();
  }

  List<_FocusRound> _buildFocusRounds(
    _LearningGameVariant variant,
    int replaySeed,
  ) {
    switch (variant) {
      case _LearningGameVariant.findIt:
        return _buildFindItRounds(replaySeed);
      case _LearningGameVariant.matchIt:
        return _buildMatchItRounds(replaySeed);
      case _LearningGameVariant.holdIt:
        return _buildHoldItRounds(replaySeed);
      case _LearningGameVariant.generic:
      case _LearningGameVariant.words:
      case _LearningGameVariant.sentences:
        return const <_FocusRound>[];
    }
  }

  List<_FocusRound> _buildFindItRounds(int replaySeed) {
    final roundTargets = <List<_FocusEmojiItem>>[
      const [
        _FocusEmojiItem(id: 'cat', label: 'Cat', emoji: '🐱'),
        _FocusEmojiItem(id: 'ball', label: 'Ball', emoji: '⚽'),
      ],
      const [
        _FocusEmojiItem(id: 'apple', label: 'Apple', emoji: '🍎'),
        _FocusEmojiItem(id: 'triangle', label: 'Triangle', emoji: '🔺'),
        _FocusEmojiItem(id: 'banana', label: 'Banana', emoji: '🍌'),
      ],
      const [
        _FocusEmojiItem(id: 'rocket', label: 'Rocket', emoji: '🚀'),
        _FocusEmojiItem(id: 'star', label: 'Star', emoji: '⭐'),
        _FocusEmojiItem(id: 'panda', label: 'Panda', emoji: '🐼'),
      ],
    ];

    final distractorPools = <List<_FocusEmojiItem>>[
      const [
        _FocusEmojiItem(id: 'dog', label: 'Dog', emoji: '🐶'),
        _FocusEmojiItem(id: 'book', label: 'Book', emoji: '📘'),
        _FocusEmojiItem(id: 'car', label: 'Car', emoji: '🚗'),
        _FocusEmojiItem(id: 'sun', label: 'Sun', emoji: '☀️'),
        _FocusEmojiItem(id: 'teddy', label: 'Teddy', emoji: '🧸'),
        _FocusEmojiItem(id: 'drum', label: 'Drum', emoji: '🥁'),
      ],
      const [
        _FocusEmojiItem(id: 'circle', label: 'Circle', emoji: '🔵'),
        _FocusEmojiItem(id: 'square', label: 'Square', emoji: '🟩'),
        _FocusEmojiItem(id: 'grapes', label: 'Grapes', emoji: '🍇'),
        _FocusEmojiItem(id: 'lemon', label: 'Lemon', emoji: '🍋'),
        _FocusEmojiItem(id: 'watermelon', label: 'Watermelon', emoji: '🍉'),
        _FocusEmojiItem(id: 'orange', label: 'Orange', emoji: '🍊'),
        _FocusEmojiItem(id: 'diamond', label: 'Diamond', emoji: '🔷'),
      ],
      const [
        _FocusEmojiItem(id: 'lion', label: 'Lion', emoji: '🦁'),
        _FocusEmojiItem(id: 'fish', label: 'Fish', emoji: '🐟'),
        _FocusEmojiItem(id: 'duck', label: 'Duck', emoji: '🦆'),
        _FocusEmojiItem(id: 'flower', label: 'Flower', emoji: '🌼'),
        _FocusEmojiItem(id: 'moon', label: 'Moon', emoji: '🌙'),
        _FocusEmojiItem(id: 'house', label: 'House', emoji: '🏠'),
        _FocusEmojiItem(id: 'train', label: 'Train', emoji: '🚂'),
        _FocusEmojiItem(id: 'cake', label: 'Cake', emoji: '🧁'),
        _FocusEmojiItem(id: 'heart', label: 'Heart', emoji: '💛'),
        _FocusEmojiItem(id: 'rainbow', label: 'Rainbow', emoji: '🌈'),
      ],
    ];

    return List<_FocusRound>.generate(3, (index) {
      final targetPool = roundTargets[index];
      final target = targetPool[(replaySeed + index) % targetPool.length];
      final distractors = <_FocusEmojiItem>[
        ...targetPool.where((item) => item.id != target.id),
        ...distractorPools[index],
      ];
      final instruction = 'Find the ${target.label}';
      return _FocusRound(
        id: 'find-$replaySeed-$index-${target.id}',
        instructionText: instruction,
        speakText: instruction,
        successText: 'You found the ${target.label}!',
        findData: _FindRoundData(
          target: target,
          distractors: distractors,
          baseItemCount: switch (index) {
            0 => 6,
            1 => 8,
            _ => 11,
          },
          crowded: index == 2,
        ),
      );
    });
  }

  List<_FocusRound> _buildMatchItRounds(int replaySeed) {
    final livingPairs = replaySeed.isEven
        ? const [
            _MatchPair(
              id: 'dog-bone',
              leftEmoji: '🐶',
              leftLabel: 'Dog',
              rightEmoji: '🦴',
              rightLabel: 'Bone',
            ),
            _MatchPair(
              id: 'bee-flower',
              leftEmoji: '🐝',
              leftLabel: 'Bee',
              rightEmoji: '🌼',
              rightLabel: 'Flower',
            ),
            _MatchPair(
              id: 'cow-milk',
              leftEmoji: '🐮',
              leftLabel: 'Cow',
              rightEmoji: '🥛',
              rightLabel: 'Milk',
            ),
            _MatchPair(
              id: 'fish-water',
              leftEmoji: '🐟',
              leftLabel: 'Fish',
              rightEmoji: '💧',
              rightLabel: 'Water',
            ),
          ]
        : const [
            _MatchPair(
              id: 'cat-yarn',
              leftEmoji: '🐱',
              leftLabel: 'Cat',
              rightEmoji: '🧶',
              rightLabel: 'Yarn',
            ),
            _MatchPair(
              id: 'cow-milk',
              leftEmoji: '🐮',
              leftLabel: 'Cow',
              rightEmoji: '🥛',
              rightLabel: 'Milk',
            ),
            _MatchPair(
              id: 'horse-hay',
              leftEmoji: '🐴',
              leftLabel: 'Horse',
              rightEmoji: '🌾',
              rightLabel: 'Hay',
            ),
            _MatchPair(
              id: 'rabbit-carrot',
              leftEmoji: '🐰',
              leftLabel: 'Rabbit',
              rightEmoji: '🥕',
              rightLabel: 'Carrot',
            ),
          ];

    final fruitPairs = replaySeed.isEven
        ? const [
            _MatchPair(
              id: 'banana-yellow',
              leftEmoji: '🍌',
              leftLabel: 'Banana',
              rightEmoji: '🟨',
              rightLabel: 'Yellow',
            ),
            _MatchPair(
              id: 'apple-red',
              leftEmoji: '🍎',
              leftLabel: 'Apple',
              rightEmoji: '🟥',
              rightLabel: 'Red',
            ),
            _MatchPair(
              id: 'grapes-purple',
              leftEmoji: '🍇',
              leftLabel: 'Grapes',
              rightEmoji: '🟪',
              rightLabel: 'Purple',
            ),
            _MatchPair(
              id: 'peach-orange',
              leftEmoji: '🍑',
              leftLabel: 'Peach',
              rightEmoji: '🟧',
              rightLabel: 'Orange',
            ),
          ]
        : const [
            _MatchPair(
              id: 'orange-orange',
              leftEmoji: '🍊',
              leftLabel: 'Orange',
              rightEmoji: '🟧',
              rightLabel: 'Orange',
            ),
            _MatchPair(
              id: 'lemon-yellow',
              leftEmoji: '🍋',
              leftLabel: 'Lemon',
              rightEmoji: '🟨',
              rightLabel: 'Yellow',
            ),
            _MatchPair(
              id: 'cherries-red',
              leftEmoji: '🍒',
              leftLabel: 'Cherries',
              rightEmoji: '🟥',
              rightLabel: 'Red',
            ),
            _MatchPair(
              id: 'blueberries-blue',
              leftEmoji: '🫐',
              leftLabel: 'Blueberries',
              rightEmoji: '🟦',
              rightLabel: 'Blue',
            ),
          ];

    final shapePairs = replaySeed.isEven
        ? const [
            _MatchPair(
              id: 'triangle-3',
              leftEmoji: '🔺',
              leftLabel: 'Triangle',
              rightEmoji: '3',
              rightLabel: '3 sides',
            ),
            _MatchPair(
              id: 'square-4',
              leftEmoji: '🟩',
              leftLabel: 'Square',
              rightEmoji: '4',
              rightLabel: '4 sides',
            ),
            _MatchPair(
              id: 'circle-0',
              leftEmoji: '🔵',
              leftLabel: 'Circle',
              rightEmoji: '0',
              rightLabel: '0 sides',
            ),
            _MatchPair(
              id: 'pentagon-5',
              leftEmoji: '⬟',
              leftLabel: 'Pentagon',
              rightEmoji: '5',
              rightLabel: '5 sides',
            ),
          ]
        : const [
            _MatchPair(
              id: 'rectangle-4',
              leftEmoji: '▭',
              leftLabel: 'Rectangle',
              rightEmoji: '4',
              rightLabel: '4 sides',
            ),
            _MatchPair(
              id: 'star-10',
              leftEmoji: '⭐',
              leftLabel: 'Star',
              rightEmoji: '10',
              rightLabel: '10 sides',
            ),
            _MatchPair(
              id: 'hexagon-6',
              leftEmoji: '⬢',
              leftLabel: 'Hexagon',
              rightEmoji: '6',
              rightLabel: '6 sides',
            ),
            _MatchPair(
              id: 'oval-0',
              leftEmoji: '🥚',
              leftLabel: 'Oval',
              rightEmoji: '0',
              rightLabel: '0 sides',
            ),
          ];

    final rounds =
        <({String instruction, String category, List<_MatchPair> pairs})>[
          (
            instruction: 'Match the animals with their related items',
            category: 'animals',
            pairs: livingPairs,
          ),
          (
            instruction: 'Match the fruits with their colors',
            category: 'fruits',
            pairs: fruitPairs,
          ),
          (
            instruction: 'Match the shapes with their number of sides',
            category: 'shapes',
            pairs: shapePairs,
          ),
        ];

    return List<_FocusRound>.generate(rounds.length, (index) {
      final round = rounds[index];
      return _FocusRound(
        id: 'match-$replaySeed-$index',
        instructionText: round.instruction,
        speakText: round.instruction,
        successText: index == rounds.length - 1
            ? 'You matched all ${round.category}!'
            : 'Great matching!',
        matchData: _MatchRoundData(
          category: round.category,
          pairs: round.pairs,
          seed: replaySeed + index * 13,
        ),
      );
    });
  }

  List<_FocusRound> _buildHoldItRounds(int replaySeed) {
    final variations = <List<_HoldRoundData>>[
      const [
        _HoldRoundData(
          id: 'phone',
          label: 'phone',
          emoji: '📱',
          actionText: 'charge it',
          successText: 'Awesome! You charged the phone!',
          failureText: 'Oh no! The phone did not charge, try again!',
          baseSeconds: 5,
          accentColor: Color(0xFF4F9BE8),
        ),
        _HoldRoundData(
          id: 'car',
          label: 'car',
          emoji: '🚗',
          actionText: 'fuel it',
          successText: 'Awesome! You fueled the car!',
          failureText: 'Oh no! The car did not fuel up, try again!',
          baseSeconds: 7,
          accentColor: Color(0xFFF59E3D),
        ),
        _HoldRoundData(
          id: 'rocket',
          label: 'rocket',
          emoji: '🚀',
          actionText: 'launch it',
          successText: 'Awesome! You launched the rocket!',
          failureText: 'Oh no! The rocket did not launch, try again!',
          baseSeconds: 9,
          accentColor: Color(0xFFE35B8F),
        ),
      ],
      const [
        _HoldRoundData(
          id: 'tablet',
          label: 'tablet',
          emoji: '💻',
          actionText: 'charge it',
          successText: 'Awesome! You charged the tablet!',
          failureText: 'Oh no! The tablet did not charge, try again!',
          baseSeconds: 5,
          accentColor: Color(0xFF5FA8A0),
        ),
        _HoldRoundData(
          id: 'bus',
          label: 'bus',
          emoji: '🚌',
          actionText: 'fuel it',
          successText: 'Awesome! You fueled the bus!',
          failureText: 'Oh no! The bus did not fuel up, try again!',
          baseSeconds: 7,
          accentColor: Color(0xFFE0AA3E),
        ),
        _HoldRoundData(
          id: 'airplane',
          label: 'airplane',
          emoji: '✈️',
          actionText: 'fly it',
          successText: 'Awesome! You flew the airplane!',
          failureText: 'Oh no! The airplane did not fly, try again!',
          baseSeconds: 9,
          accentColor: Color(0xFF7E8BEA),
        ),
      ],
      const [
        _HoldRoundData(
          id: 'watch',
          label: 'watch',
          emoji: '⌚',
          actionText: 'charge it',
          successText: 'Awesome! You charged the watch!',
          failureText: 'Oh no! The watch did not charge, try again!',
          baseSeconds: 5,
          accentColor: Color(0xFF60A577),
        ),
        _HoldRoundData(
          id: 'train',
          label: 'train',
          emoji: '🚂',
          actionText: 'start it',
          successText: 'Awesome! You started the train!',
          failureText: 'Oh no! The train did not start, try again!',
          baseSeconds: 7,
          accentColor: Color(0xFFCF6E55),
        ),
        _HoldRoundData(
          id: 'balloon',
          label: 'balloon',
          emoji: '🎈',
          actionText: 'lift it',
          successText: 'Awesome! You lifted the balloon!',
          failureText: 'Oh no! The balloon did not lift, try again!',
          baseSeconds: 9,
          accentColor: Color(0xFFE85F6A),
        ),
      ],
    ];

    final selected = variations[replaySeed % variations.length];
    return List<_FocusRound>.generate(selected.length, (index) {
      final data = selected[index];
      final instruction = 'Hold the ${data.label} to ${data.actionText}';
      return _FocusRound(
        id: 'hold-$replaySeed-$index-${data.id}',
        instructionText: instruction,
        speakText: instruction,
        successText: data.successText,
        holdData: data,
      );
    });
  }

  String _promptTextFor(_LearningGameVariant variant, ContentItem prompt) {
    switch (variant) {
      case _LearningGameVariant.findIt:
        return 'Find: ${prompt.title}';
      case _LearningGameVariant.matchIt:
        return prompt.subtitle.isEmpty
            ? 'Match: ${prompt.title}'
            : 'Match: ${prompt.subtitle}';
      case _LearningGameVariant.holdIt:
        return 'Press and hold on: ${prompt.title}';
      case _LearningGameVariant.words:
        return 'Select the word: ${prompt.title}';
      case _LearningGameVariant.sentences:
        return 'Choose the correct sentence';
      case _LearningGameVariant.generic:
        return 'Find: ${prompt.title}';
    }
  }

  String _promptHintFor(_LearningGameVariant variant, ContentItem prompt) {
    switch (variant) {
      case _LearningGameVariant.findIt:
        return 'Tap the correct item from the choices.';
      case _LearningGameVariant.matchIt:
        return 'Match the prompt with the best option.';
      case _LearningGameVariant.holdIt:
        return 'Hold on the correct option to answer.';
      case _LearningGameVariant.words:
        return prompt.subtitle.isEmpty
            ? 'Tap the matching word.'
            : prompt.subtitle;
      case _LearningGameVariant.sentences:
        return 'Pick the sentence that best matches.';
      case _LearningGameVariant.generic:
        return prompt.subtitle.isEmpty
            ? 'Pick the best answer.'
            : prompt.subtitle;
    }
  }

  String _playingTitle() {
    switch (_variant) {
      case _LearningGameVariant.findIt:
        return 'Find It';
      case _LearningGameVariant.matchIt:
        return 'Match It';
      case _LearningGameVariant.holdIt:
        return 'Hold It';
      case _LearningGameVariant.words:
        return 'Words';
      case _LearningGameVariant.sentences:
        return 'Sentences';
      case _LearningGameVariant.generic:
        return widget.module.title;
    }
  }

  Future<void> _speakCurrentPrompt() async {
    if (_isFocusGame) {
      if (_focusRounds.isEmpty || _levelIndex >= _focusRounds.length) {
        return;
      }
      await _tts.speak(_currentFocusRound.speakText);
      return;
    }

    if (_levels.isEmpty || _levelIndex >= _levels.length) {
      return;
    }
    await _tts.speak(_currentLevel.promptSpeakText);
  }

  Future<void> _selectOption(int optionIndex, {required bool fromHold}) async {
    if (_stage != _LearningGameStage.playing || _isResolvingSelection) {
      return;
    }

    final requiresHold = _variant == _LearningGameVariant.holdIt;
    if (requiresHold && !fromHold) {
      return;
    }

    setState(() {
      _isResolvingSelection = true;
    });

    final isCorrect = optionIndex == _currentLevel.correctOptionIndex;
    if (!isCorrect) {
      setState(() {
        _stage = _LearningGameStage.wrongOption;
        _isResolvingSelection = false;
      });
      return;
    }

    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _earnedPoints += 100;
        _stage = _LearningGameStage.levelCompleted;
        _isResolvingSelection = false;
      });
      return;
    }

    setState(() {
      _earnedPoints += 100;
      _stage = _LearningGameStage.allLevelsCompleted;
      _isResolvingSelection = false;
    });
    await _saveProgressIfNeeded();
  }

  int get _adaptiveDifficulty {
    if (!_isFocusGame) {
      return 0;
    }
    if (_wrongAttempts == 0 && _earnedStars > 0) {
      return 1;
    }
    if (_wrongAttempts >= 2) {
      return -1;
    }
    return 0;
  }

  String get _focusBadgeName {
    return switch (_variant) {
      _LearningGameVariant.findIt => 'Bronze Badge',
      _LearningGameVariant.matchIt => 'Silver Badge',
      _LearningGameVariant.holdIt => 'Gold Badge',
      _ => 'Focus Badge',
    };
  }

  Color get _focusBadgeColor {
    return switch (_variant) {
      _LearningGameVariant.findIt => const Color(0xFFCD7F32),
      _LearningGameVariant.matchIt => const Color(0xFFC0C0C0),
      _LearningGameVariant.holdIt => const Color(0xFFFFC83D),
      _ => AppColors.primaryBlue,
    };
  }

  String get _focusCompletionFeedback {
    return switch (_variant) {
      _LearningGameVariant.findIt => 'You found $_earnedStars items!',
      _LearningGameVariant.matchIt =>
        _earnedStars == _focusRounds.length
            ? 'You matched all shapes!'
            : 'You matched $_earnedStars rounds!',
      _LearningGameVariant.holdIt => 'You stayed focused till the end!',
      _ => 'You completed $_earnedStars rounds!',
    };
  }

  String get _focusEncouragement {
    if (_wrongAttempts == 0) {
      return 'Calm focus from start to finish.';
    }
    return 'You kept trying and finished strong.';
  }

  String get _focusReplayLabel {
    return switch (_variant) {
      _LearningGameVariant.findIt => 'Replay Find It',
      _LearningGameVariant.matchIt => 'Replay Match It',
      _LearningGameVariant.holdIt => 'Replay Hold It',
      _ => 'Play Again',
    };
  }

  String get _focusCompletionTitle {
    return switch (_variant) {
      _LearningGameVariant.findIt => 'You found them!',
      _LearningGameVariant.matchIt => 'Amazing matches!',
      _LearningGameVariant.holdIt => 'You stayed focused!',
      _ => 'Great Job!',
    };
  }

  Color get _focusDialogAccent {
    return switch (_variant) {
      _LearningGameVariant.findIt => const Color(0xFFE48B3C),
      _LearningGameVariant.matchIt => const Color(0xFF7D8FF2),
      _LearningGameVariant.holdIt => const Color(0xFFE9B43A),
      _ => AppColors.primaryBlue,
    };
  }

  Future<void> _handleFocusWrong() async {
    if (_stage != _LearningGameStage.playing || _isResolvingSelection) {
      return;
    }
    final messages = <String>[
      'No problem, try again!',
      'You are doing great!',
      'Almost there, try one more time!',
    ];
    final message = messages[_wrongAttempts % messages.length];
    setState(() {
      _wrongAttempts += 1;
      _isResolvingSelection = true;
    });
    unawaited(_tts.speak(message));
    await _showFocusDialog(
      title: 'Try Again',
      message: message,
      icon: Icons.favorite_rounded,
      accentColor: const Color(0xFFFFA260),
      actionLabel: 'Try Again',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isResolvingSelection = false;
    });
    await _speakCurrentPrompt();
  }

  void _handleHoldEarlyRelease(String message) {
    if (_stage != _LearningGameStage.playing) {
      return;
    }
    setState(() {
      _wrongAttempts += 1;
    });
    unawaited(_tts.speak(message));
  }

  Future<void> _handleFocusSuccess() async {
    if (_stage != _LearningGameStage.playing || _isResolvingSelection) {
      return;
    }

    final round = _currentFocusRound;
    final isLastRound = _levelIndex >= _focusRounds.length - 1;
    setState(() {
      _earnedStars += 1;
      _earnedPoints += 100;
      _isResolvingSelection = true;
    });

    final message = '${round.successText} You earned 1 star.';
    unawaited(_tts.speak(message));
    await _showFocusDialog(
      title: 'Great Job!',
      message: message,
      icon: Icons.star_rounded,
      accentColor: _focusDialogAccent,
      actionLabel: isLastRound ? 'See Badge' : 'Next Round',
    );
    if (!mounted) {
      return;
    }

    if (isLastRound) {
      setState(() {
        _stage = _LearningGameStage.allLevelsCompleted;
        _isResolvingSelection = false;
      });
      unawaited(_tts.speak(_focusCompletionFeedback));
      await _saveProgressIfNeeded();
      return;
    }

    setState(() {
      _levelIndex += 1;
      _isResolvingSelection = false;
      _stage = _LearningGameStage.playing;
    });
    await _speakCurrentPrompt();
  }

  Future<void> _playFocusAgain() async {
    _replaySeed += 1;
    await _loadGame();
  }

  Future<void> _showFocusDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
    required String actionLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      barrierDismissible: false,
      builder: (dialogContext) {
        return _FocusFeedbackDialog(
          title: title,
          message: message,
          icon: icon,
          accentColor: accentColor,
          actionLabel: actionLabel,
          onAction: () => Navigator.pop(dialogContext),
        );
      },
    );
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

  void _retryLevel() {
    setState(() {
      _stage = _LearningGameStage.playing;
      _isResolvingSelection = false;
    });
  }

  void _replayCurrentLevel() {
    setState(() {
      _stage = _LearningGameStage.playing;
      _isResolvingSelection = false;
    });
  }

  Future<void> _nextLevel() async {
    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _levelIndex += 1;
        _stage = _LearningGameStage.playing;
        _isResolvingSelection = false;
      });
      await _speakCurrentPrompt();
      return;
    }
    setState(() {
      _stage = _LearningGameStage.allLevelsCompleted;
    });
    await _saveProgressIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _LearningGameStage.allLevelsCompleted && _isFocusGame) {
      return SessionGuard(
        role: SessionGuardRole.parent,
        child: MovePlayCelebration(
          title: _focusCompletionTitle,
          subtitle: '$_focusCompletionFeedback $_focusEncouragement',
          starsEarned: _earnedStars,
          starsTotal: _focusRounds.length,
          badgeLabel: _focusBadgeName,
          trophyColor: _focusBadgeColor,
          replayLabel: _focusReplayLabel,
          backLabel: 'Back to Focus Games',
          onReplay: _playFocusAgain,
          onBack: () => Navigator.pop(context),
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
    switch (_stage) {
      case _LearningGameStage.loading:
        return const Center(child: CircularProgressIndicator());
      case _LearningGameStage.error:
        return _GameInfoCard(
          title: 'Unable to start game',
          body: _error ?? 'Unknown error',
          actionLabel: 'Retry',
          onAction: () {
            _loadGame();
          },
        );
      case _LearningGameStage.playing:
        if (_isFocusGame) {
          return _buildFocusBoard();
        }
        return _LearningLevelBoard(
          title: 'Level ${_levelIndex + 1} of ${_levels.length}',
          level: _currentLevel,
          variant: _variant,
          isBusy: _isResolvingSelection,
          onSpeak: () {
            _speakCurrentPrompt();
          },
          onTapOption: (index) {
            _selectOption(index, fromHold: false);
          },
          onHoldOption: (index) {
            _selectOption(index, fromHold: true);
          },
        );
      case _LearningGameStage.wrongOption:
        return _WrongOptionCard(onTryAgain: _retryLevel);
      case _LearningGameStage.levelCompleted:
        return _LevelCompletedCard(
          levelNumber: _levelIndex + 1,
          onReplay: _replayCurrentLevel,
          onNextLevel: () {
            _nextLevel();
          },
        );
      case _LearningGameStage.allLevelsCompleted:
        return _AllLevelsCompletedCard(
          moduleTitle: widget.module.title,
          isSavingProgress: _isSavingProgress,
          onHome: () => Navigator.pop(context),
          onReplay: () {
            _loadGame();
          },
        );
    }
  }

  Widget _buildFocusBoard() {
    final round = _currentFocusRound;
    final commonHeader = _FocusProgressHeader(
      title: 'Round ${_levelIndex + 1} of ${_focusRounds.length}',
      badgeName: _focusBadgeName,
      badgeColor: _focusBadgeColor,
      earnedStars: _earnedStars,
      totalStars: _focusRounds.length,
    );
    final instruction = _FocusInstructionCard(
      instruction: round.instructionText,
      isBusy: _isResolvingSelection,
      onSpeak: _speakCurrentPrompt,
    );

    switch (_variant) {
      case _LearningGameVariant.findIt:
        return _FindItBoard(
          header: commonHeader,
          instruction: instruction,
          round: round.findData!,
          seed: _replaySeed + _levelIndex * 37,
          adaptiveDifficulty: _adaptiveDifficulty,
          isBusy: _isResolvingSelection,
          onCorrect: _handleFocusSuccess,
          onWrong: _handleFocusWrong,
        );
      case _LearningGameVariant.matchIt:
        return _MatchItBoard(
          header: commonHeader,
          instruction: instruction,
          round: round.matchData!,
          adaptiveDifficulty: _adaptiveDifficulty,
          isBusy: _isResolvingSelection,
          onRoundComplete: _handleFocusSuccess,
          onWrong: _handleFocusWrong,
        );
      case _LearningGameVariant.holdIt:
        return _HoldItBoard(
          header: commonHeader,
          instruction: instruction,
          round: round.holdData!,
          adaptiveDifficulty: _adaptiveDifficulty,
          isBusy: _isResolvingSelection,
          onComplete: _handleFocusSuccess,
          onEarlyRelease: _handleHoldEarlyRelease,
        );
      case _LearningGameVariant.generic:
      case _LearningGameVariant.words:
      case _LearningGameVariant.sentences:
        return const SizedBox.shrink();
    }
  }
}

class _FocusRound {
  const _FocusRound({
    required this.id,
    required this.instructionText,
    required this.speakText,
    required this.successText,
    this.findData,
    this.matchData,
    this.holdData,
  });

  final String id;
  final String instructionText;
  final String speakText;
  final String successText;
  final _FindRoundData? findData;
  final _MatchRoundData? matchData;
  final _HoldRoundData? holdData;
}

class _FocusEmojiItem {
  const _FocusEmojiItem({
    required this.id,
    required this.label,
    required this.emoji,
  });

  final String id;
  final String label;
  final String emoji;
}

class _FindRoundData {
  const _FindRoundData({
    required this.target,
    required this.distractors,
    required this.baseItemCount,
    required this.crowded,
  });

  final _FocusEmojiItem target;
  final List<_FocusEmojiItem> distractors;
  final int baseItemCount;
  final bool crowded;
}

class _ScatteredFocusItem {
  const _ScatteredFocusItem({
    required this.item,
    required this.x,
    required this.y,
    required this.size,
    required this.rotation,
    required this.partlyHidden,
  });

  final _FocusEmojiItem item;
  final double x;
  final double y;
  final double size;
  final double rotation;
  final bool partlyHidden;
}

class _MatchRoundData {
  const _MatchRoundData({
    required this.category,
    required this.pairs,
    required this.seed,
  });

  final String category;
  final List<_MatchPair> pairs;
  final int seed;
}

class _MatchPair {
  const _MatchPair({
    required this.id,
    required this.leftEmoji,
    required this.leftLabel,
    required this.rightEmoji,
    required this.rightLabel,
  });

  final String id;
  final String leftEmoji;
  final String leftLabel;
  final String rightEmoji;
  final String rightLabel;
}

class _HoldRoundData {
  const _HoldRoundData({
    required this.id,
    required this.label,
    required this.emoji,
    required this.actionText,
    required this.successText,
    required this.failureText,
    required this.baseSeconds,
    required this.accentColor,
  });

  final String id;
  final String label;
  final String emoji;
  final String actionText;
  final String successText;
  final String failureText;
  final int baseSeconds;
  final Color accentColor;
}

class _FocusProgressHeader extends StatelessWidget {
  const _FocusProgressHeader({
    required this.title,
    required this.badgeName,
    required this.badgeColor,
    required this.earnedStars,
    required this.totalStars,
  });

  final String title;
  final String badgeName;
  final Color badgeColor;
  final int earnedStars;
  final int totalStars;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final iconSize = keyboardOpen ? 34.0 : 42.0;
    return Container(
      padding: keyboardOpen
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(keyboardOpen ? 18 : 22),
        border: Border.all(color: const Color(0xFFE4ECF6)),
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: badgeColor,
              size: keyboardOpen ? 22 : 24,
            ),
          ),
          SizedBox(width: keyboardOpen ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: keyboardOpen ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1A2D4B),
                  ),
                ),
                if (!keyboardOpen) const SizedBox(height: 3),
                Text(
                  badgeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: keyboardOpen ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(totalStars, (index) {
              final filled = index < earnedStars;
              return Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: filled ? const Color(0xFFFFC83D) : Colors.black26,
                size: keyboardOpen ? 20 : 25,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _FocusInstructionCard extends StatelessWidget {
  const _FocusInstructionCard({
    required this.instruction,
    required this.isBusy,
    required this.onSpeak,
  });

  final String instruction;
  final bool isBusy;
  final Future<void> Function() onSpeak;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Container(
      padding: keyboardOpen
          ? const EdgeInsets.fromLTRB(12, 8, 8, 8)
          : const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4C7),
        borderRadius: BorderRadius.circular(keyboardOpen ? 18 : 22),
        border: Border.all(color: const Color(0xFFFFDE79)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.record_voice_over_rounded,
            color: const Color(0xFF9A6A00),
            size: keyboardOpen ? 23 : 28,
          ),
          SizedBox(width: keyboardOpen ? 8 : 12),
          Expanded(
            child: Text(
              instruction,
              maxLines: keyboardOpen ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF1A2D4B),
                fontSize: keyboardOpen ? 16 : 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: isBusy ? null : () => unawaited(onSpeak()),
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: 'Hear prompt',
            constraints: BoxConstraints.tightFor(
              width: keyboardOpen ? 40 : 48,
              height: keyboardOpen ? 40 : 48,
            ),
          ),
        ],
      ),
    );
  }
}

class _FindItBoard extends StatefulWidget {
  const _FindItBoard({
    required this.header,
    required this.instruction,
    required this.round,
    required this.seed,
    required this.adaptiveDifficulty,
    required this.isBusy,
    required this.onCorrect,
    required this.onWrong,
  });

  final Widget header;
  final Widget instruction;
  final _FindRoundData round;
  final int seed;
  final int adaptiveDifficulty;
  final bool isBusy;
  final Future<void> Function() onCorrect;
  final Future<void> Function() onWrong;

  @override
  State<_FindItBoard> createState() => _FindItBoardState();
}

class _FindItBoardState extends State<_FindItBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  Timer? _guidanceTimer;
  bool _showGuidance = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _scheduleGuidance();
  }

  @override
  void didUpdateWidget(covariant _FindItBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.round.target.id != widget.round.target.id ||
        oldWidget.seed != widget.seed ||
        oldWidget.adaptiveDifficulty != widget.adaptiveDifficulty) {
      _scheduleGuidance();
    }
  }

  @override
  void dispose() {
    _guidanceTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _scheduleGuidance() {
    _guidanceTimer?.cancel();
    _showGuidance = false;
    _guidanceTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _showGuidance = true;
        });
      }
    });
  }

  List<_ScatteredFocusItem> _scatteredItems() {
    final random = Random(widget.seed + widget.adaptiveDifficulty * 97);
    final distractors = List<_FocusEmojiItem>.from(widget.round.distractors)
      ..shuffle(random);
    final maxCount = distractors.length + 1;
    final minCount = widget.round.crowded ? 8 : 5;
    final itemCount = (widget.round.baseItemCount + widget.adaptiveDifficulty)
        .clamp(minCount, maxCount)
        .toInt();
    final selected = <_FocusEmojiItem>[
      widget.round.target,
      ...distractors.take(itemCount - 1),
    ]..shuffle(random);

    return List<_ScatteredFocusItem>.generate(selected.length, (index) {
      final isTarget = selected[index].id == widget.round.target.id;
      final crowded = widget.round.crowded || widget.adaptiveDifficulty > 0;
      final partlyHidden = crowded && !isTarget && index % 4 == 0;
      final baseSize = widget.adaptiveDifficulty < 0
          ? 66.0
          : crowded
          ? 54.0
          : 61.0;
      final size = baseSize + random.nextDouble() * 12;
      final x = partlyHidden
          ? (random.nextBool() ? -0.04 : 0.92)
          : 0.04 + random.nextDouble() * 0.82;
      final y = partlyHidden
          ? (random.nextBool() ? -0.03 : 0.88)
          : 0.04 + random.nextDouble() * 0.80;
      return _ScatteredFocusItem(
        item: selected[index],
        x: x,
        y: y,
        size: size,
        rotation: (random.nextDouble() - 0.5) * 0.36,
        partlyHidden: partlyHidden,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _scatteredItems();
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showHint = !keyboardOpen || constraints.maxHeight >= 330;
        final boardHeight =
            (constraints.maxHeight * (keyboardOpen ? 0.62 : 0.55))
                .clamp(
                  keyboardOpen ? 96.0 : 240.0,
                  keyboardOpen ? 220.0 : 340.0,
                )
                .toDouble();
        return Column(
          children: [
            widget.header,
            SizedBox(height: keyboardOpen ? 6 : 8),
            widget.instruction,
            SizedBox(height: keyboardOpen ? 6 : 10),
            Flexible(
              fit: FlexFit.loose,
              child: SizedBox(
                height: boardHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8FF),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: const Color(0xFFBCE8FA),
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, boardConstraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FindItBackgroundPainter(),
                            ),
                          ),
                          for (final scattered in items)
                            _buildScatteredEmoji(scattered, boardConstraints),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            if (showHint) ...[
              const SizedBox(height: 8),
              const Text(
                'Look carefully, then tap the matching emoji.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF466176),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildScatteredEmoji(
    _ScatteredFocusItem scattered,
    BoxConstraints constraints,
  ) {
    final isTarget = scattered.item.id == widget.round.target.id;
    final maxItemSize = max(
      28.0,
      min(constraints.maxWidth * 0.24, constraints.maxHeight * 0.34),
    );
    final itemSize = min(scattered.size, maxItemSize);
    final left = scattered.x < 0
        ? -itemSize * 0.22
        : scattered.x * (constraints.maxWidth - itemSize);
    final top = scattered.y < 0
        ? -itemSize * 0.18
        : scattered.y * (constraints.maxHeight - itemSize);
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isBusy
          ? null
          : () {
              if (isTarget) {
                unawaited(widget.onCorrect());
              } else {
                unawaited(widget.onWrong());
              }
            },
      child: Transform.rotate(
        angle: scattered.rotation,
        child: SizedBox(
          width: itemSize,
          height: itemSize,
          child: Center(
            child: Text(
              scattered.item.emoji,
              style: TextStyle(fontSize: itemSize * 0.72),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: scattered.partlyHidden ? 0.92 : 1,
        child: Semantics(
          button: true,
          label: scattered.item.label,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, _) {
              final pulse = 1 + (_pulseCtrl.value * 0.12);
              final glow = isTarget && _showGuidance;
              return Transform.scale(
                scale: glow ? pulse : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: glow
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFFFC83D,
                              ).withValues(alpha: 0.55),
                              blurRadius: 22,
                              spreadRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FindItBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final colors = <Color>[
      const Color(0xFFFFD6E4),
      const Color(0xFFFFF2A8),
      const Color(0xFFBFEFD7),
      const Color(0xFFD8D2FF),
    ];
    final positions = <Offset>[
      Offset(size.width * 0.18, size.height * 0.18),
      Offset(size.width * 0.78, size.height * 0.20),
      Offset(size.width * 0.26, size.height * 0.78),
      Offset(size.width * 0.82, size.height * 0.72),
    ];
    for (var i = 0; i < positions.length; i++) {
      paint.color = colors[i].withValues(alpha: 0.42);
      canvas.drawCircle(positions[i], 42 + i * 7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MatchItBoard extends StatefulWidget {
  const _MatchItBoard({
    required this.header,
    required this.instruction,
    required this.round,
    required this.adaptiveDifficulty,
    required this.isBusy,
    required this.onRoundComplete,
    required this.onWrong,
  });

  final Widget header;
  final Widget instruction;
  final _MatchRoundData round;
  final int adaptiveDifficulty;
  final bool isBusy;
  final Future<void> Function() onRoundComplete;
  final Future<void> Function() onWrong;

  @override
  State<_MatchItBoard> createState() => _MatchItBoardState();
}

class _MatchItBoardState extends State<_MatchItBoard> {
  static const double _rowHeight = 74;
  late List<_MatchPair> _pairs;
  late List<_MatchPair> _rightPairs;
  final Set<String> _matchedIds = <String>{};
  String? _draggingId;
  Offset? _dragStart;
  Offset? _dragCurrent;
  String _feedback = 'Drag from a left item to its match on the right.';
  bool _completionSent = false;

  @override
  void initState() {
    super.initState();
    _prepareRound();
  }

  @override
  void didUpdateWidget(covariant _MatchItBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.round.category != widget.round.category ||
        oldWidget.round.seed != widget.round.seed) {
      _prepareRound();
    }
  }

  void _prepareRound() {
    final visibleCount =
        widget.adaptiveDifficulty > 0 && widget.round.pairs.length > 3
        ? 4
        : min(3, widget.round.pairs.length);
    final random = Random(widget.round.seed + visibleCount * 19);
    _pairs = widget.round.pairs.take(visibleCount).toList();
    _rightPairs = List<_MatchPair>.from(_pairs)..shuffle(random);
    _matchedIds.clear();
    _draggingId = null;
    _dragStart = null;
    _dragCurrent = null;
    _feedback = 'Drag from a left item to its match on the right.';
    _completionSent = false;
  }

  double _leftWidth(double boardWidth) => min(134.0, boardWidth * 0.38);

  double _rightWidth(double boardWidth) => min(146.0, boardWidth * 0.40);

  int? _leftIndexAt(Offset position, Size size, double rowHeight) {
    if (position.dx < 0 || position.dx > _leftWidth(size.width)) {
      return null;
    }
    final index = (position.dy / rowHeight).floor();
    if (index < 0 || index >= _pairs.length) {
      return null;
    }
    return index;
  }

  int? _rightIndexAt(Offset position, Size size, double rowHeight) {
    final rightStart = size.width - _rightWidth(size.width);
    if (position.dx < rightStart || position.dx > size.width) {
      return null;
    }
    final index = (position.dy / rowHeight).floor();
    if (index < 0 || index >= _rightPairs.length) {
      return null;
    }
    return index;
  }

  Offset _leftAnchorForIndex(int index, Size size, double rowHeight) {
    return Offset(
      _leftWidth(size.width) - 8,
      index * rowHeight + rowHeight / 2,
    );
  }

  Offset _rightAnchorForIndex(int index, Size size, double rowHeight) {
    return Offset(
      size.width - _rightWidth(size.width) + 8,
      index * rowHeight + rowHeight / 2,
    );
  }

  void _startDrag(Offset position, Size size, double rowHeight) {
    if (widget.isBusy) {
      return;
    }
    final index = _leftIndexAt(position, size, rowHeight);
    if (index == null) {
      return;
    }
    final pair = _pairs[index];
    if (_matchedIds.contains(pair.id)) {
      return;
    }
    setState(() {
      _draggingId = pair.id;
      _dragStart = _leftAnchorForIndex(index, size, rowHeight);
      _dragCurrent = position;
      _feedback = 'Keep dragging to the matching item.';
    });
  }

  void _updateDrag(Offset position) {
    if (_draggingId == null) {
      return;
    }
    setState(() {
      _dragCurrent = position;
    });
  }

  void _endDrag(Size size, double rowHeight) {
    final selectedId = _draggingId;
    final releasePoint = _dragCurrent;
    if (selectedId == null || releasePoint == null) {
      return;
    }

    final rightIndex = _rightIndexAt(releasePoint, size, rowHeight);
    if (rightIndex == null) {
      setState(() {
        _draggingId = null;
        _dragStart = null;
        _dragCurrent = null;
        _feedback = 'Start on the left and drag all the way across.';
      });
      return;
    }

    final rightPair = _rightPairs[rightIndex];
    if (selectedId == rightPair.id) {
      setState(() {
        _matchedIds.add(rightPair.id);
        _draggingId = null;
        _dragStart = null;
        _dragCurrent = null;
        _feedback = _matchedIds.length == _pairs.length
            ? 'All matched!'
            : 'Great match!';
      });
      if (_matchedIds.length == _pairs.length && !_completionSent) {
        _completionSent = true;
        Timer(const Duration(milliseconds: 450), () {
          if (mounted) {
            unawaited(widget.onRoundComplete());
          }
        });
      }
      return;
    }
    setState(() {
      _draggingId = null;
      _dragStart = null;
      _dragCurrent = null;
      _feedback = 'No problem, try again!';
    });
    unawaited(widget.onWrong());
  }

  void _cancelDrag() {
    if (_draggingId == null) {
      return;
    }
    setState(() {
      _draggingId = null;
      _dragStart = null;
      _dragCurrent = null;
      _feedback = 'Drag from a left item to its match on the right.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, keyboardOpen ? 0 : 8),
      child: Column(
        children: [
          widget.header,
          SizedBox(height: keyboardOpen ? 6 : 8),
          widget.instruction,
          SizedBox(height: keyboardOpen ? 6 : 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight <= 0 || _pairs.isEmpty) {
                  return const SizedBox.shrink();
                }
                final showFeedback =
                    !keyboardOpen || constraints.maxHeight >= 170;
                final feedbackSpace = showFeedback ? 34.0 : 0.0;
                final availableForBoard = max(
                  0.0,
                  constraints.maxHeight - feedbackSpace,
                );
                final rowHeight = min(
                  _rowHeight,
                  availableForBoard / _pairs.length,
                );
                if (rowHeight <= 0) {
                  return const SizedBox.shrink();
                }
                final boardHeight = rowHeight * _pairs.length;
                final size = Size(constraints.maxWidth, boardHeight);
                final rightIndexById = <String, int>{
                  for (var i = 0; i < _rightPairs.length; i++)
                    _rightPairs[i].id: i,
                };
                final lines = <_MatchLine>[
                  for (final id in _matchedIds)
                    _MatchLine(
                      start: _leftAnchorForIndex(
                        _pairs.indexWhere((pair) => pair.id == id),
                        size,
                        rowHeight,
                      ),
                      end: _rightAnchorForIndex(
                        rightIndexById[id] ?? 0,
                        size,
                        rowHeight,
                      ),
                      active: false,
                    ),
                  if (_dragStart != null && _dragCurrent != null)
                    _MatchLine(
                      start: _dragStart!,
                      end: _dragCurrent!,
                      active: true,
                    ),
                ];
                final hoverRightIndex = _dragCurrent == null
                    ? null
                    : _rightIndexAt(_dragCurrent!, size, rowHeight);
                final hoverRightId = hoverRightIndex == null
                    ? null
                    : _rightPairs[hoverRightIndex].id;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: boardHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) =>
                            _startDrag(details.localPosition, size, rowHeight),
                        onPanUpdate: (details) =>
                            _updateDrag(details.localPosition),
                        onPanEnd: (_) => _endDrag(size, rowHeight),
                        onPanCancel: _cancelDrag,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MatchLinesPainter(lines: lines),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              width: _leftWidth(size.width),
                              child: Column(
                                children: [
                                  for (final pair in _pairs)
                                    _MatchChoiceTile(
                                      emoji: pair.leftEmoji,
                                      label: pair.leftLabel,
                                      selected: _draggingId == pair.id,
                                      matched: _matchedIds.contains(pair.id),
                                      height: rowHeight - 10,
                                    ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              width: _rightWidth(size.width),
                              child: Column(
                                children: [
                                  for (final pair in _rightPairs)
                                    _MatchChoiceTile(
                                      emoji: pair.rightEmoji,
                                      label: pair.rightLabel,
                                      selected: hoverRightId == pair.id,
                                      matched: _matchedIds.contains(pair.id),
                                      height: rowHeight - 10,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showFeedback) ...[
                      const SizedBox(height: 6),
                      Text(
                        _feedback,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF466176),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchChoiceTile extends StatelessWidget {
  const _MatchChoiceTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.matched,
    required this.height,
  });

  final String emoji;
  final String label;
  final bool selected;
  final bool matched;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) {
      return const SizedBox.shrink();
    }
    final compact = height < 42;
    final showLabel = height >= 18;
    final emojiBoxSize = height.clamp(0.0, 42.0).toDouble();
    final background = matched
        ? const Color(0xFFE8F8E7)
        : selected
        ? const Color(0xFFEAF4FF)
        : Colors.transparent;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 10),
      child: Semantics(
        button: !matched,
        label: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: max(0.0, height),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(compact ? 14 : 22),
            boxShadow: selected || matched
                ? [
                    BoxShadow(
                      color:
                          (matched
                                  ? const Color(0xFF67B96B)
                                  : const Color(0xFF7D8FF2))
                              .withValues(alpha: 0.18),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 140),
                child: SizedBox(
                  width: emojiBoxSize,
                  height: emojiBoxSize,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        emoji,
                        style: TextStyle(
                          fontSize: emojiBoxSize * 0.86,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 4 : 7),
              if (showLabel) ...[
                Expanded(
                  child: Text(
                    label,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10 : 13,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1A2D4B),
                    ),
                  ),
                ),
              ],
              if (matched && showLabel)
                Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF67B96B),
                  size: compact ? 14 : 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchLine {
  const _MatchLine({
    required this.start,
    required this.end,
    required this.active,
  });

  final Offset start;
  final Offset end;
  final bool active;
}

class _MatchLinesPainter extends CustomPainter {
  const _MatchLinesPainter({required this.lines});

  final List<_MatchLine> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.active
            ? const Color(0xFF7D8FF2)
            : const Color(0xFF67B96B)
        ..strokeWidth = line.active ? 4 : 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(line.start.dx, line.start.dy)
        ..cubicTo(
          size.width * 0.42,
          line.start.dy,
          size.width * 0.58,
          line.end.dy,
          line.end.dx,
          line.end.dy,
        );
      canvas.drawPath(path, paint);

      if (!line.active) {
        final dotPaint = Paint()
          ..color = const Color(0xFF67B96B)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(line.end, 5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MatchLinesPainter oldDelegate) {
    return oldDelegate.lines != lines;
  }
}

class _HoldItBoard extends StatefulWidget {
  const _HoldItBoard({
    required this.header,
    required this.instruction,
    required this.round,
    required this.adaptiveDifficulty,
    required this.isBusy,
    required this.onComplete,
    required this.onEarlyRelease,
  });

  final Widget header;
  final Widget instruction;
  final _HoldRoundData round;
  final int adaptiveDifficulty;
  final bool isBusy;
  final Future<void> Function() onComplete;
  final void Function(String message) onEarlyRelease;

  @override
  State<_HoldItBoard> createState() => _HoldItBoardState();
}

class _HoldItBoardState extends State<_HoldItBoard>
    with TickerProviderStateMixin {
  late AnimationController _progressCtrl;
  late final AnimationController _breathCtrl;
  Timer? _completionTimer;
  bool _holding = false;
  bool _complete = false;
  String _statusText = '';

  int get _durationSeconds {
    final adjusted = widget.round.baseSeconds + widget.adaptiveDifficulty;
    return adjusted.clamp(5, 10).toInt();
  }

  String get _actionVerb =>
      widget.round.actionText.replaceFirst(RegExp(r'\s+it$'), '');

  String get _idleStatusText => 'Hold to $_actionVerb';

  String get _activeStatusText {
    return switch (_actionVerb) {
      'charge' => 'Charging... ⚡',
      'fuel' => 'Fueling... ⚡',
      'launch' => 'Launching... 🚀',
      'fly' => 'Flying... ✈️',
      'start' => 'Starting...',
      'lift' => 'Lifting...',
      _ => '${_actionVerb[0].toUpperCase()}${_actionVerb.substring(1)}ing...',
    };
  }

  @override
  void initState() {
    super.initState();
    _statusText = _idleStatusText;
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _createProgressController();
  }

  @override
  void didUpdateWidget(covariant _HoldItBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.round.id != widget.round.id ||
        oldWidget.adaptiveDifficulty != widget.adaptiveDifficulty) {
      _completionTimer?.cancel();
      _progressCtrl.dispose();
      _createProgressController();
      _holding = false;
      _complete = false;
      _statusText = _idleStatusText;
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _progressCtrl.dispose();
    _breathCtrl.dispose();
    super.dispose();
  }

  void _createProgressController() {
    _progressCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: _durationSeconds),
    )..addListener(_updateProgressStatus);
  }

  void _updateProgressStatus() {
    if (!mounted || _complete) {
      return;
    }
    final value = _progressCtrl.value;
    final nextText = value >= 0.84
        ? 'Almost there!'
        : value > 0
        ? _activeStatusText
        : _idleStatusText;
    if (_statusText != nextText) {
      setState(() {
        _statusText = nextText;
      });
    } else {
      setState(() {});
    }
    if (value >= 1 && !_complete) {
      _finishHold();
    }
  }

  void _startHold(TapDownDetails details) {
    if (widget.isBusy || _complete) {
      return;
    }
    setState(() {
      _holding = true;
      _statusText = _activeStatusText;
    });
    _progressCtrl.forward(from: 0);
  }

  void _releaseHold() {
    if (widget.isBusy || _complete || !_holding) {
      return;
    }
    if (_progressCtrl.value < 1) {
      _progressCtrl.stop();
      _progressCtrl.reset();
      setState(() {
        _holding = false;
        _statusText = widget.round.failureText;
      });
      widget.onEarlyRelease(widget.round.failureText);
    }
  }

  void _finishHold() {
    _progressCtrl.stop();
    setState(() {
      _complete = true;
      _holding = false;
      _statusText = 'Done!';
    });
    _completionTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        unawaited(widget.onComplete());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(
      children: [
        widget.header,
        SizedBox(height: keyboardOpen ? 6 : 8),
        widget.instruction,
        SizedBox(height: keyboardOpen ? 6 : 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
                return const SizedBox.shrink();
              }
              final cardWidth = min(constraints.maxWidth, 360.0);
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: cardWidth,
                    child: Container(
                      padding: keyboardOpen
                          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
                          : const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6FBF8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFCDEBDD),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _progressCtrl,
                              _breathCtrl,
                            ]),
                            builder: (context, _) {
                              final breathingScale =
                                  1 + _breathCtrl.value * 0.035;
                              final nearDone =
                                  _progressCtrl.value > 0.84 && !_complete;
                              final shake = nearDone
                                  ? sin(_breathCtrl.value * pi * 12) * 4
                                  : 0.0;
                              final displayedProgress = _holding || _complete
                                  ? max(_progressCtrl.value, 0.025)
                                  : _progressCtrl.value;
                              return Transform.translate(
                                offset: Offset(shake, 0),
                                child: Transform.scale(
                                  scale: breathingScale,
                                  child: GestureDetector(
                                    onTapDown: _startHold,
                                    onTapUp: (_) => _releaseHold(),
                                    onTapCancel: _releaseHold,
                                    child: SizedBox(
                                      width: 206,
                                      height: 206,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CustomPaint(
                                            size: const Size.square(206),
                                            painter: _HoldProgressPainter(
                                              progress: displayedProgress,
                                              color: widget.round.accentColor,
                                            ),
                                          ),
                                          Container(
                                            width: 152,
                                            height: 152,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: widget
                                                      .round
                                                      .accentColor
                                                      .withValues(alpha: 0.20),
                                                  blurRadius: 22,
                                                  spreadRadius: 3,
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                widget.round.emoji,
                                                style: const TextStyle(
                                                  fontSize: 66,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_complete)
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: _HoldExplosionPainter(
                                                  t: _breathCtrl.value,
                                                  color:
                                                      widget.round.accentColor,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              color: _complete
                                  ? const Color(0xFF38A169)
                                  : _progressCtrl.value > 0
                                  ? widget.round.accentColor
                                  : const Color(0xFF1A2D4B),
                              fontSize: _progressCtrl.value > 0.84 ? 21 : 18,
                              fontWeight: FontWeight.w900,
                            ),
                            child: Text(
                              _statusText,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hold for $_durationSeconds seconds',
                            style: const TextStyle(
                              color: Color(0xFF466176),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HoldProgressPainter extends CustomPainter {
  const _HoldProgressPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final strokeWidth = (size.shortestSide * 0.078).clamp(8.0, 16.0);
    final radius = size.shortestSide / 2 - strokeWidth * 0.7;
    final base = Paint()
      ..color = const Color(0xFFE3EDF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      pi * 2 * progress,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _HoldExplosionPainter extends CustomPainter {
  const _HoldExplosionPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..strokeWidth = (size.shortestSide * 0.02).clamp(2.0, 4.0)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = (pi * 2 / 12) * i;
      final distance = size.shortestSide * 0.4 + t * size.shortestSide * 0.09;
      final start = Offset(
        center.dx + cos(angle) * (distance - size.shortestSide * 0.06),
        center.dy + sin(angle) * (distance - size.shortestSide * 0.06),
      );
      final end = Offset(
        center.dx + cos(angle) * distance,
        center.dy + sin(angle) * distance,
      );
      paint.color = i.isEven
          ? color.withValues(alpha: 0.78)
          : const Color(0xFFFFC83D).withValues(alpha: 0.78);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HoldExplosionPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.color != color;
  }
}

class _FocusFeedbackDialog extends StatelessWidget {
  const _FocusFeedbackDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final softAccent = Color.alphaBlend(
      accentColor.withValues(alpha: 0.13),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, softAccent, softBlue],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -20,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 92,
                  color: accentColor.withValues(alpha: 0.12),
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
                        border: Border.all(color: accentColor, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.24),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 48, color: accentColor),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF12213D),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF334765),
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
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
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: Text(
                          actionLabel,
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
      ),
    );
  }
}

class _LearningLevelBoard extends StatelessWidget {
  const _LearningLevelBoard({
    required this.title,
    required this.level,
    required this.variant,
    required this.isBusy,
    required this.onSpeak,
    required this.onTapOption,
    required this.onHoldOption,
  });

  final String title;
  final _QuizLevel level;
  final _LearningGameVariant variant;
  final bool isBusy;
  final VoidCallback onSpeak;
  final void Function(int index) onTapOption;
  final void Function(int index) onHoldOption;

  @override
  Widget build(BuildContext context) {
    final isHold = variant == _LearningGameVariant.holdIt;
    final isVisualGrid =
        variant == _LearningGameVariant.findIt ||
        variant == _LearningGameVariant.matchIt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
      children: [
        _GameInfoCard(
          title: title,
          body: switch (variant) {
            _LearningGameVariant.holdIt => 'Hold on the correct option.',
            _LearningGameVariant.matchIt =>
              'Match the prompt with the right option.',
            _LearningGameVariant.findIt => 'Find the exact item shown above.',
            _LearningGameVariant.words =>
              'Pick the exact word that matches the prompt.',
            _LearningGameVariant.sentences =>
              'Select the sentence that best matches.',
            _LearningGameVariant.generic => 'Tap the correct option.',
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.psychology_alt_outlined,
                size: 42,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(height: 12),
              Text(
                level.promptText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2D4B),
                ),
              ),
              const SizedBox(height: 8),
              Text(level.promptHint, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              _PromptImage(
                url: level.promptImageUrl,
                square: isVisualGrid,
                semanticText: level.promptVisualKey,
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: isBusy ? null : onSpeak,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Hear prompt'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isVisualGrid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: level.options.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              return _GameOptionTile(
                option: level.options[index],
                requiresHold: isHold,
                enabled: !isBusy,
                emphasizeImage: true,
                onTap: () => onTapOption(index),
                onLongPress: () => onHoldOption(index),
              );
            },
          )
        else
          for (var i = 0; i < level.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GameOptionTile(
                option: level.options[i],
                requiresHold: isHold,
                enabled: !isBusy,
                emphasizeImage: false,
                onTap: () => onTapOption(i),
                onLongPress: () => onHoldOption(i),
              ),
            ),
        if (isBusy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _GameOptionTile extends StatelessWidget {
  const _GameOptionTile({
    required this.option,
    required this.requiresHold,
    required this.enabled,
    required this.emphasizeImage,
    required this.onTap,
    required this.onLongPress,
  });

  final _QuizOption option;
  final bool requiresHold;
  final bool enabled;
  final bool emphasizeImage;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final tile = Ink(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE6F2)),
      ),
      child: emphasizeImage
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PromptImage(
                    url: option.imageUrl,
                    square: true,
                    semanticText: '${option.label} ${option.subtitle ?? ''}',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2D4B),
                  ),
                ),
                if (option.subtitle?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      option.subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                if (requiresHold)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Hold',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: _PromptImage(
                      url: option.imageUrl,
                      square: true,
                      semanticText: '${option.label} ${option.subtitle ?? ''}',
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2D4B),
                        ),
                      ),
                      if (option.subtitle?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            option.subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (requiresHold)
                  const Text(
                    'Hold',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: !enabled || requiresHold ? null : onTap,
      onLongPress: !enabled || !requiresHold ? null : onLongPress,
      child: tile,
    );
  }
}

class _PromptImage extends StatelessWidget {
  const _PromptImage({
    required this.url,
    required this.square,
    required this.semanticText,
  });

  final String url;
  final bool square;
  final String semanticText;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(square ? 16 : 20);
    final visual = _VisualSpec.fromText(semanticText);
    final fallback = Container(
      decoration: BoxDecoration(
        color: visual.backgroundColor,
        borderRadius: radius,
      ),
      child: Center(
        child: visual.glyph != null
            ? Text(
                visual.glyph!,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: square ? 26 : 34,
                ),
              )
            : Icon(visual.icon, color: Colors.white, size: square ? 34 : 44),
      ),
    );

    if (url.trim().isEmpty) {
      return ClipRRect(borderRadius: radius, child: fallback);
    }

    final child = url.startsWith('http')
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.asset(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );

    return ClipRRect(borderRadius: radius, child: child);
  }
}

class _VisualSpec {
  const _VisualSpec({
    required this.icon,
    required this.backgroundColor,
    this.glyph,
  });

  final IconData icon;
  final Color backgroundColor;
  final String? glyph;

  static const Map<String, _VisualSpec> _wordSpecific = <String, _VisualSpec>{
    'mother': _VisualSpec(
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFF82C596),
      glyph: 'M',
    ),
    'father': _VisualSpec(
      icon: Icons.person_outline_rounded,
      backgroundColor: Color(0xFF6AAE8B),
      glyph: 'F',
    ),
    'sister': _VisualSpec(
      icon: Icons.people_alt_rounded,
      backgroundColor: Color(0xFF8FC37F),
      glyph: 'S',
    ),
    'shirt': _VisualSpec(
      icon: Icons.checkroom_rounded,
      backgroundColor: Color(0xFF9E95D6),
    ),
    'pants': _VisualSpec(
      icon: Icons.dry_cleaning_rounded,
      backgroundColor: Color(0xFF7F84D6),
    ),
    'shoes': _VisualSpec(
      icon: Icons.directions_walk_rounded,
      backgroundColor: Color(0xFF6E7EC7),
    ),
    'milk': _VisualSpec(
      icon: Icons.local_drink_rounded,
      backgroundColor: Color(0xFFF2A65A),
    ),
    'bread': _VisualSpec(
      icon: Icons.breakfast_dining_rounded,
      backgroundColor: Color(0xFFE79C4B),
    ),
    'apple': _VisualSpec(
      icon: Icons.eco_rounded,
      backgroundColor: Color(0xFFE56E6E),
    ),
    'angry': _VisualSpec(
      icon: Icons.sentiment_very_dissatisfied_rounded,
      backgroundColor: Color(0xFFF07D7D),
    ),
    'sad': _VisualSpec(
      icon: Icons.sentiment_dissatisfied_rounded,
      backgroundColor: Color(0xFF8CA1D8),
    ),
    'happy': _VisualSpec(
      icon: Icons.sentiment_very_satisfied_rounded,
      backgroundColor: Color(0xFF7EC9F5),
    ),
    'cat': _VisualSpec(
      icon: Icons.pets_rounded,
      backgroundColor: Color(0xFF8FA4C4),
    ),
    'red': _VisualSpec(
      icon: Icons.circle_rounded,
      backgroundColor: Color(0xFFD95C5C),
    ),
    'blue': _VisualSpec(
      icon: Icons.water_drop_rounded,
      backgroundColor: Color(0xFF5E8CE0),
    ),
    'circle': _VisualSpec(
      icon: Icons.circle_outlined,
      backgroundColor: Color(0xFF5CB9C7),
    ),
    'square': _VisualSpec(
      icon: Icons.crop_square_rounded,
      backgroundColor: Color(0xFF57A9B8),
    ),
    'triangle': _VisualSpec(
      icon: Icons.change_history_rounded,
      backgroundColor: Color(0xFF4E99A6),
    ),
    '1': _VisualSpec(
      icon: Icons.filter_1_rounded,
      backgroundColor: Color(0xFFB98DCE),
    ),
    '2': _VisualSpec(
      icon: Icons.filter_2_rounded,
      backgroundColor: Color(0xFFA77EC0),
    ),
    '3': _VisualSpec(
      icon: Icons.filter_3_rounded,
      backgroundColor: Color(0xFF966EB2),
    ),
    'a': _VisualSpec(
      icon: Icons.sort_by_alpha_rounded,
      backgroundColor: Color(0xFF5F93C6),
      glyph: 'A',
    ),
    'b': _VisualSpec(
      icon: Icons.sort_by_alpha_rounded,
      backgroundColor: Color(0xFF4E84B8),
      glyph: 'B',
    ),
    'c': _VisualSpec(
      icon: Icons.sort_by_alpha_rounded,
      backgroundColor: Color(0xFF3D75A9),
      glyph: 'C',
    ),
  };

  static const List<Color> _fallbackColors = <Color>[
    Color(0xFF8BA7C9),
    Color(0xFF8FC37F),
    Color(0xFF9E95D6),
    Color(0xFFF2A65A),
    Color(0xFF7EC9F5),
    Color(0xFFDD7FA4),
  ];

  static const List<IconData> _fallbackIcons = <IconData>[
    Icons.auto_awesome_rounded,
    Icons.extension_rounded,
    Icons.lightbulb_rounded,
    Icons.toys_rounded,
    Icons.explore_rounded,
    Icons.public_rounded,
  ];

  static _VisualSpec fromText(String text) {
    final lower = text.toLowerCase();
    final tokens = lower
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final keys = _wordSpecific.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (tokens.contains(key)) {
        return _wordSpecific[key]!;
      }
    }

    final seed = tokens.isEmpty ? lower.trim() : tokens.first;
    final hash = seed.hashCode.abs();
    final icon = _fallbackIcons[hash % _fallbackIcons.length];
    final color = _fallbackColors[hash % _fallbackColors.length];
    final glyph = seed.isEmpty ? null : seed[0].toUpperCase();
    return _VisualSpec(icon: icon, backgroundColor: color, glyph: glyph);
  }
}

class _WrongOptionCard extends StatelessWidget {
  const _WrongOptionCard({required this.onTryAgain});

  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFDCDCDC),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wrong Option',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black54, width: 2),
              ),
              child: const Center(
                child: Icon(
                  Icons.close_rounded,
                  color: AppColors.errorRed,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onTryAgain,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA260),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCompletedCard extends StatelessWidget {
  const _LevelCompletedCard({
    required this.levelNumber,
    required this.onReplay,
    required this.onNextLevel,
  });

  final int levelNumber;
  final VoidCallback onReplay;
  final VoidCallback onNextLevel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 330,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 70,
              color: Color(0xFFF5B700),
            ),
            const SizedBox(height: 14),
            Text(
              'Level $levelNumber Completed',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'You have earned 100 points',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            _ActionWideButton(
              label: 'Replay',
              backgroundColor: const Color(0xFFF4A9AD),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.replay,
              onTap: onReplay,
            ),
            const SizedBox(height: 14),
            _ActionWideButton(
              label: 'Next Level',
              backgroundColor: const Color(0xFF76ED67),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.arrow_forward,
              onTap: onNextLevel,
            ),
          ],
        ),
      ),
    );
  }
}

class _AllLevelsCompletedCard extends StatelessWidget {
  const _AllLevelsCompletedCard({
    required this.moduleTitle,
    required this.isSavingProgress,
    required this.onHome,
    required this.onReplay,
  });

  final String moduleTitle;
  final bool isSavingProgress;
  final VoidCallback onHome;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 330,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 72,
              color: Color(0xFFF5B700),
            ),
            const SizedBox(height: 12),
            Text(
              'You have completed\n$moduleTitle',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (isSavingProgress)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(),
              ),
            _ActionWideButton(
              label: 'Play Again',
              backgroundColor: const Color(0xFF76ED67),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.replay,
              onTap: onReplay,
            ),
            const SizedBox(height: 12),
            _ActionWideButton(
              label: 'Home',
              backgroundColor: const Color(0xFFF4A9AD),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.home_outlined,
              onTap: onHome,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionWideButton extends StatelessWidget {
  const _ActionWideButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.trailingIcon,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Icon(trailingIcon),
          ],
        ),
      ),
    );
  }
}

class _GameInfoCard extends StatelessWidget {
  const _GameInfoCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizLevel {
  const _QuizLevel({
    required this.promptText,
    required this.promptHint,
    required this.promptImageUrl,
    required this.promptVisualKey,
    required this.promptSpeakText,
    required this.options,
    required this.correctOptionIndex,
  });

  final String promptText;
  final String promptHint;
  final String promptImageUrl;
  final String promptVisualKey;
  final String promptSpeakText;
  final List<_QuizOption> options;
  final int correctOptionIndex;
}

class _QuizOption {
  const _QuizOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.imageUrl = '',
  });

  final String id;
  final String label;
  final String? subtitle;
  final String imageUrl;
}
