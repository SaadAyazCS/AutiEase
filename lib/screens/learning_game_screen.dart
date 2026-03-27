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

class _LearningGameScreenState extends State<LearningGameScreen> {
  final TtsService _tts = TtsService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCompleted = false;
  String? _error;

  List<_QuizQuestion> _questions = const [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  int? _selectedOptionIndex;
  bool _answerLocked = false;

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  Future<void> _loadGame() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isCompleted = false;
      _score = 0;
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _answerLocked = false;
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

      final questions = _buildQuestions(scopedItems);
      if (questions.isEmpty) {
        throw StateError(
          'Unable to build quiz questions from current content.',
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
      await _speakCurrentPrompt();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
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

    if (filtered.isEmpty) {
      filtered = List<ContentItem>.from(allItems);
    }

    final deduped = <String, ContentItem>{
      for (final item in filtered) item.id: item,
    };
    return deduped.values.toList();
  }

  List<_QuizQuestion> _buildQuestions(List<ContentItem> items) {
    final random = Random();
    final shuffledItems = List<ContentItem>.from(items)..shuffle(random);
    final questionCount = min(10, shuffledItems.length);
    final selectedPrompts = shuffledItems.take(questionCount).toList();

    return selectedPrompts.map((prompt) {
      final distractors = items.where((item) => item.id != prompt.id).toList()
        ..shuffle(random);
      final optionCount = min(4, items.length);
      final options = <ContentItem>[
        prompt,
        ...distractors.take(optionCount - 1),
      ]..shuffle(random);
      return _QuizQuestion(
        prompt: prompt,
        options: options,
        correctOptionIndex: options.indexWhere((item) => item.id == prompt.id),
      );
    }).toList();
  }

  Future<void> _speakCurrentPrompt() async {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) {
      return;
    }
    final prompt = _questions[_currentQuestionIndex].prompt;
    final text = prompt.audioText.isEmpty ? prompt.title : prompt.audioText;
    await _tts.speak(text);
  }

  Future<void> _handleOptionTap(int optionIndex) async {
    if (_answerLocked || _isCompleted || _questions.isEmpty) {
      return;
    }

    final question = _questions[_currentQuestionIndex];
    final isCorrect = optionIndex == question.correctOptionIndex;

    setState(() {
      _answerLocked = true;
      _selectedOptionIndex = optionIndex;
      if (isCorrect) {
        _score += 1;
      }
    });

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) {
      return;
    }

    final isLastQuestion = _currentQuestionIndex == _questions.length - 1;
    if (isLastQuestion) {
      await _completeGame();
      return;
    }

    setState(() {
      _currentQuestionIndex += 1;
      _selectedOptionIndex = null;
      _answerLocked = false;
    });
    await _speakCurrentPrompt();
  }

  Future<void> _completeGame() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: widget.module.id,
        moduleId: widget.module.id,
        score: _score,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isCompleted = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Game complete: $_score/${_questions.length} saved to progress.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save game progress: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _answerLocked = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: widget.module.title,
        onBack: () => Navigator.pop(context),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _GameInfoCard(
                title: 'Unable to start game',
                body: _error!,
                actionLabel: 'Retry',
                onAction: _loadGame,
              )
            : _isCompleted
            ? _GameInfoCard(
                title: 'Great job!',
                body:
                    'You scored $_score out of ${_questions.length}. Keep practicing for better accuracy.',
                actionLabel: 'Play again',
                onAction: _loadGame,
                secondaryActionLabel: 'Done',
                onSecondaryAction: () => Navigator.pop(context),
              )
            : _buildQuizView(context),
      ),
    );
  }

  Widget _buildQuizView(BuildContext context) {
    final question = _questions[_currentQuestionIndex];
    final total = _questions.length;
    final current = _currentQuestionIndex + 1;
    final progress = total == 0 ? 0.0 : current / total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
      children: [
        _GameInfoCard(
          title: 'Question $current of $total',
          body: 'Tap the correct option. Progress is saved when the game ends.',
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.psychology_alt_outlined,
                color: AppColors.primaryBlue,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                'Find: ${question.prompt.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2D4B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                question.prompt.subtitle.isEmpty
                    ? 'Use hints and tap the best answer.'
                    : question.prompt.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _answerLocked ? null : _speakCurrentPrompt,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Hear prompt'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < question.options.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildOptionTile(
              option: question.options[index],
              isSelected: _selectedOptionIndex == index,
              isCorrectOption: question.correctOptionIndex == index,
              locked: _answerLocked || _isSaving,
              onTap: () => _handleOptionTap(index),
            ),
          ),
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildOptionTile({
    required ContentItem option,
    required bool isSelected,
    required bool isCorrectOption,
    required bool locked,
    required VoidCallback onTap,
  }) {
    Color backgroundColor = Colors.white;
    if (locked && isCorrectOption) {
      backgroundColor = Colors.green.shade100;
    } else if (locked && isSelected && !isCorrectOption) {
      backgroundColor = Colors.red.shade100;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: locked ? null : onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDDE6F2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_outline, color: AppColors.primaryBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2D4B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.prompt,
    required this.options,
    required this.correctOptionIndex,
  });

  final ContentItem prompt;
  final List<ContentItem> options;
  final int correctOptionIndex;
}

class _GameInfoCard extends StatelessWidget {
  const _GameInfoCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

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
            Wrap(
              spacing: 10,
              children: [
                ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(actionLabel!),
                ),
                if (secondaryActionLabel != null && onSecondaryAction != null)
                  OutlinedButton(
                    onPressed: onSecondaryAction,
                    child: Text(secondaryActionLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
