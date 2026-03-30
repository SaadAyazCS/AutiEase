import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/tts_service.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
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
  int _levelIndex = 0;
  int _earnedPoints = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;
  bool _isResolvingSelection = false;
  String? _error;

  _QuizLevel get _currentLevel => _levels[_levelIndex];

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
        return _playingTitle(_currentLevel);
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
      _levelIndex = 0;
      _earnedPoints = 0;
      _savedCompletion = false;
      _isSavingProgress = false;
      _isResolvingSelection = false;
    });

    try {
      await _tts.init();
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

  String _playingTitle(_QuizLevel level) {
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
