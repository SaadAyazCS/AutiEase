import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class TapGameScreen extends StatefulWidget {
  const TapGameScreen({super.key, required this.childId, required this.module});

  final String childId;
  final LearningModuleModel module;

  @override
  State<TapGameScreen> createState() => _TapGameScreenState();
}

enum _TapGameStage { playing, wrongOption, levelCompleted, allLevelsCompleted }

class _TapGameScreenState extends State<TapGameScreen> {
  static const _levels = <_TapLevel>[
    _TapLevel(
      prompt: 'Circle',
      options: <_TapOption>[
        _TapOption(
          key: 'triangle',
          label: 'Triangle',
          kind: _TapOptionKind.icon,
          icon: Icons.change_history_rounded,
          color: Color(0xFF5DAA2A),
          left: 26,
          top: 20,
        ),
        _TapOption(
          key: 'rectangle',
          label: 'Rectangle',
          kind: _TapOptionKind.icon,
          icon: Icons.rectangle_rounded,
          color: Color(0xFFFF0E8A),
          left: 190,
          top: 36,
        ),
        _TapOption(
          key: 'star',
          label: 'Star',
          kind: _TapOptionKind.icon,
          icon: Icons.star_rounded,
          color: Color(0xFFF7C926),
          left: 104,
          top: 104,
        ),
        _TapOption(
          key: 'heart',
          label: 'Heart',
          kind: _TapOptionKind.icon,
          icon: Icons.favorite_rounded,
          color: Color(0xFFE36BA7),
          left: 26,
          top: 196,
        ),
        _TapOption(
          key: 'circle',
          label: 'Circle',
          kind: _TapOptionKind.icon,
          icon: Icons.circle_rounded,
          color: Color(0xFFF14D4D),
          left: 178,
          top: 204,
        ),
      ],
    ),
    _TapLevel(
      prompt: 'Apple',
      options: <_TapOption>[
        _TapOption(
          key: 'banana',
          label: 'Banana',
          kind: _TapOptionKind.emoji,
          emoji: '🍌',
          left: 70,
          top: 36,
        ),
        _TapOption(
          key: 'watermelon',
          label: 'Watermelon',
          kind: _TapOptionKind.emoji,
          emoji: '🍉',
          left: 194,
          top: 68,
        ),
        _TapOption(
          key: 'grapes',
          label: 'Grapes',
          kind: _TapOptionKind.emoji,
          emoji: '🍇',
          left: 104,
          top: 142,
        ),
        _TapOption(
          key: 'apple',
          label: 'Apple',
          kind: _TapOptionKind.emoji,
          emoji: '🍎',
          left: 48,
          top: 240,
        ),
        _TapOption(
          key: 'lemon',
          label: 'Lemon',
          kind: _TapOptionKind.emoji,
          emoji: '🍋',
          left: 194,
          top: 240,
        ),
      ],
    ),
    _TapLevel(
      prompt: '2',
      options: <_TapOption>[
        _TapOption(
          key: '1',
          label: '1',
          kind: _TapOptionKind.number,
          numberText: '1',
          color: Color(0xFF59B086),
          left: 162,
          top: 42,
        ),
        _TapOption(
          key: '5',
          label: '5',
          kind: _TapOptionKind.number,
          numberText: '5',
          color: Color(0xFFE9B126),
          left: 96,
          top: 86,
        ),
        _TapOption(
          key: '9',
          label: '9',
          kind: _TapOptionKind.number,
          numberText: '9',
          color: Color(0xFFEF5755),
          left: 128,
          top: 190,
        ),
        _TapOption(
          key: '2',
          label: '2',
          kind: _TapOptionKind.number,
          numberText: '2',
          color: Color(0xFFF58436),
          left: 228,
          top: 182,
        ),
        _TapOption(
          key: '3',
          label: '3',
          kind: _TapOptionKind.number,
          numberText: '3',
          color: Color(0xFFF7746A),
          left: 28,
          top: 262,
        ),
      ],
    ),
  ];

  int _levelIndex = 0;
  _TapGameStage _stage = _TapGameStage.playing;
  int _earnedPoints = 0;
  bool _isSavingProgress = false;
  bool _savedCompletion = false;

  _TapLevel get _currentLevel => _levels[_levelIndex];

  String get _title {
    if (_stage == _TapGameStage.playing) {
      return 'Tap on "${_currentLevel.prompt}"';
    }
    if (_stage == _TapGameStage.wrongOption) {
      return 'Tap Game';
    }
    return 'Great Job!';
  }

  Future<void> _handleTap(_TapOption option) async {
    if (_stage != _TapGameStage.playing) {
      return;
    }

    if (option.key != _currentLevel.prompt.toLowerCase()) {
      setState(() {
        _stage = _TapGameStage.wrongOption;
      });
      return;
    }

    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _earnedPoints += 100;
        _stage = _TapGameStage.levelCompleted;
      });
      return;
    }

    setState(() {
      _earnedPoints += 100;
      _stage = _TapGameStage.allLevelsCompleted;
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
      _stage = _TapGameStage.playing;
    });
  }

  void _replayCurrentLevel() {
    setState(() {
      _stage = _TapGameStage.playing;
    });
  }

  void _nextLevel() {
    if (_levelIndex < _levels.length - 1) {
      setState(() {
        _levelIndex += 1;
        _stage = _TapGameStage.playing;
      });
      return;
    }
    setState(() {
      _stage = _TapGameStage.allLevelsCompleted;
    });
  }

  void _goHome() {
    Navigator.pop(context);
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
      case _TapGameStage.playing:
        return _TapLevelBoard(level: _currentLevel, onTapOption: _handleTap);
      case _TapGameStage.wrongOption:
        return _WrongOptionCard(onTryAgain: _retryLevel);
      case _TapGameStage.levelCompleted:
        return _LevelCompletedCard(
          levelNumber: _levelIndex + 1,
          onReplay: _replayCurrentLevel,
          onNextLevel: _nextLevel,
        );
      case _TapGameStage.allLevelsCompleted:
        return _AllLevelsCompletedCard(
          isSavingProgress: _isSavingProgress,
          onHome: _goHome,
        );
    }
  }
}

class _TapLevelBoard extends StatelessWidget {
  const _TapLevelBoard({required this.level, required this.onTapOption});

  final _TapLevel level;
  final void Function(_TapOption option) onTapOption;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 420,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final option in level.options)
              Positioned(
                left: option.left,
                top: option.top,
                child: GestureDetector(
                  onTap: () => onTapOption(option),
                  child: _TapOptionView(option: option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TapOptionView extends StatelessWidget {
  const _TapOptionView({required this.option});

  final _TapOption option;

  @override
  Widget build(BuildContext context) {
    switch (option.kind) {
      case _TapOptionKind.icon:
        return Icon(option.icon!, size: 86, color: option.color);
      case _TapOptionKind.emoji:
        return Text(option.emoji!, style: const TextStyle(fontSize: 58));
      case _TapOptionKind.number:
        return Text(
          option.numberText!,
          style: TextStyle(
            fontSize: 82,
            fontWeight: FontWeight.w700,
            color: option.color,
          ),
        );
    }
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
              style: TextStyle(fontSize: 38 / 2, fontWeight: FontWeight.w700),
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
              style: const TextStyle(
                fontSize: 30 / 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: Color(0xFFFF7043), size: 36),
                SizedBox(width: 3),
                Icon(Icons.star, color: Color(0xFFFFB74D), size: 36),
                SizedBox(width: 3),
                Icon(Icons.star, color: Color(0xFFFBC02D), size: 36),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'You have earned 100 points',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 30 / 2,
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
              label: levelNumber == 3 ? 'Next' : 'Next Level',
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
    required this.isSavingProgress,
    required this.onHome,
  });

  final bool isSavingProgress;
  final VoidCallback onHome;

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
            const Text(
              'You have completed\nTap Games',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 34 / 2,
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
              label: 'Home',
              backgroundColor: const Color(0xFFF4A9AD),
              foregroundColor: Colors.black87,
              trailingIcon: Icons.replay,
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
              style: const TextStyle(
                fontSize: 30 / 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Icon(trailingIcon),
          ],
        ),
      ),
    );
  }
}

enum _TapOptionKind { icon, emoji, number }

class _TapLevel {
  const _TapLevel({required this.prompt, required this.options});

  final String prompt;
  final List<_TapOption> options;
}

class _TapOption {
  const _TapOption({
    required this.key,
    required this.label,
    required this.kind,
    required this.left,
    required this.top,
    this.icon,
    this.emoji,
    this.numberText,
    this.color = Colors.black,
  });

  final String key;
  final String label;
  final _TapOptionKind kind;
  final double left;
  final double top;
  final IconData? icon;
  final String? emoji;
  final String? numberText;
  final Color color;
}
