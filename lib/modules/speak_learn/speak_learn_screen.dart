// Speak & Learn: opened from Learn → Speak & Learn (hub, practice, completion in one route).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_models.dart';
import '../../widgets/figma_module_scaffold.dart';
import '../../widgets/module_bottom_wave_overlay.dart';
import '../../widgets/session_guard.dart';
import 'models/speak_learn_item.dart';
import 'models/speak_learn_level_kind.dart';
import 'services/speak_learn_analytics.dart';
import 'services/speak_learn_content.dart';
import 'services/speak_learn_evaluator.dart';
import 'services/speak_learn_speech_service.dart';
import 'widgets/speak_learn_level_intro_dialog.dart';

enum _Phase { hub, practice, completion }

const _encourageWrong = <String>[
  'No problem, try again — you can do it!',
  'Good try, let\'s do it once more!',
  'Almost there, keep going!',
  'You are doing great, keep trying!',
  'Nice effort! Give it another go.',
];

const _completionTitles = <String>[
  'You superstar!',
  'Amazing work!',
  'Wow — you did it!',
  'Champion speaker!',
  'Fantastic job!',
];

const _completionSubtitles = <String>[
  'You finished every step in this level. That takes real focus!',
  'Your voice powered through the whole level — we are so proud!',
  'Level complete! Keep shining and try another level when you are ready.',
  'What a great speaking session — celebrate this win!',
  'You stuck with it and spoke beautifully. High five!',
];

/// Hub shows only levels assigned in Learning Planner (same modules as child assignment).
class SpeakLearnScreen extends StatefulWidget {
  const SpeakLearnScreen({
    super.key,
    required this.childId,
    required this.modules,
  });

  final String childId;
  final List<LearningModuleModel> modules;

  @override
  State<SpeakLearnScreen> createState() => _SpeakLearnScreenState();
}

class _SpeakLearnScreenState extends State<SpeakLearnScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.hub;
  SpeakLearnLevelKind? _kind;
  LearningModuleModel? _module;

  final SpeakLearnSpeechService _speech = SpeakLearnSpeechService();

  List<SpeakLearnItem> _items = [];
  bool _loadingPractice = false;
  int _index = 0;
  int _failedAttemptsThisItem = 0;
  int _sessionFailedAttempts = 0;
  bool _listening = false;
  bool _successTint = false;
  String? _banner;
  String? _hintLine;
  String? _liveListenLabel;

  /// Each index must be answered correctly at least once before level completion.
  final Set<int> _masteredItemIndices = {};

  bool _completionAnalyticsSent = false;
  String _completionTitle = 'Amazing!';
  String _completionSubtitle = '';

  late final AnimationController _trophyCtrl;
  late final AnimationController _confettiCtrl;

  @override
  void initState() {
    super.initState();
    _trophyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _speech.dispose();
    _trophyCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  SpeakLearnItem? get _current =>
      _items.isEmpty || _index >= _items.length ? null : _items[_index];

  /// Hub cards follow Learning Planner: only assigned speak_learn modules appear.
  bool _levelAssigned(SpeakLearnLevelKind kind) =>
      SpeakLearnContent.moduleForKind(widget.modules, kind) != null;

  Future<void> _showLevelIntroThenStart(SpeakLearnLevelKind kind) async {
    final go = await showSpeakLearnLevelIntroDialog(context, kind: kind);
    if (!mounted || !go) {
      return;
    }
    await _beginPractice(kind);
  }

  Future<void> _beginPractice(SpeakLearnLevelKind kind) async {
    setState(() {
      _kind = kind;
      _module = SpeakLearnContent.moduleForKind(widget.modules, kind);
      _loadingPractice = true;
      _items = [];
      _index = 0;
      _failedAttemptsThisItem = 0;
      _sessionFailedAttempts = 0;
      _banner = null;
      _hintLine = null;
      _successTint = false;
      _completionAnalyticsSent = false;
      _liveListenLabel = null;
      _masteredItemIndices.clear();
      _phase = _Phase.practice;
    });

    await _speech.initTts();
    await _speech.ensureSpeechPermission();

    List<SpeakLearnItem> loaded;
    switch (kind) {
      case SpeakLearnLevelKind.alphabets:
        loaded = SpeakLearnContent.alphabetItems();
        break;
      case SpeakLearnLevelKind.words:
        loaded = await SpeakLearnContent.loadWordItems(_module);
        break;
      case SpeakLearnLevelKind.sentences:
        loaded = await SpeakLearnContent.loadSentenceItems(_module);
        break;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _items = loaded;
      _loadingPractice = false;
    });
    _scheduleAutoSpeak();
  }

  void _advanceToNextUnmastered() {
    if (_items.isEmpty) {
      return;
    }
    for (var j = _index + 1; j < _items.length; j++) {
      if (!_masteredItemIndices.contains(j)) {
        setState(() => _index = j);
        return;
      }
    }
    for (var j = 0; j < _index; j++) {
      if (!_masteredItemIndices.contains(j)) {
        setState(() => _index = j);
        return;
      }
    }
  }

  bool get _allItemsMastered =>
      _items.isNotEmpty && _masteredItemIndices.length == _items.length;

  String _pickEncouragement() =>
      _encourageWrong[math.Random().nextInt(_encourageWrong.length)];

  String _successBannerText(String heard, SpeakLearnItem item) {
    final trimmed = heard.trim();
    final display =
        trimmed.length > 48 ? '${trimmed.substring(0, 45)}…' : trimmed;
    return "Great job! You said '$display'";
  }

  void _scheduleAutoSpeak() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final item = _current;
      if (item == null || !mounted) {
        return;
      }
      await _speech.speak(item.speakText);
    });
  }

  String? _listeningPrompt() {
    if (!_listening) {
      return null;
    }
    final item = _current;
    final k = _kind;
    if (item == null || k == null) {
      return null;
    }
    return switch (k) {
      SpeakLearnLevelKind.alphabets => "Say '${item.displayText}'…",
      SpeakLearnLevelKind.words => 'Say the word…',
      SpeakLearnLevelKind.sentences => 'Say the sentence…',
    };
  }

  Future<void> _replayAudio() async {
    final item = _current;
    if (item == null) {
      return;
    }
    await _speech.speak(item.speakText);
  }

  Future<void> _onMic() async {
    final item = _current;
    final k = _kind;
    if (item == null || k == null || _listening) {
      return;
    }
    final listenCue =
        math.Random().nextBool() ? 'Listening…' : 'Hearing you…';
    setState(() {
      _listening = true;
      _liveListenLabel = listenCue;
      _banner = null;
      _hintLine = null;
    });

    await _speech.stopListening();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final heard = await _speech.listenOnce();

    if (!mounted) {
      return;
    }
    setState(() {
      _listening = false;
      _liveListenLabel = null;
    });

    final trimmed = heard?.trim() ?? '';
    final hadSpeechInput = trimmed.isNotEmpty;
    final ok = hadSpeechInput &&
        SpeakLearnEvaluator.isCorrect(
          kind: k,
          expected: item.speakText,
          heard: trimmed,
        );

    if (ok) {
      _masteredItemIndices.add(_index);
      setState(() {
        _successTint = true;
        _banner = _successBannerText(trimmed, item);
        _failedAttemptsThisItem = 0;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) {
        return;
      }
      setState(() {
        _successTint = false;
        _banner = null;
      });
      if (_allItemsMastered) {
        await _goCompletion();
      } else {
        _failedAttemptsThisItem = 0;
        _advanceToNextUnmastered();
        _scheduleAutoSpeak();
      }
    } else {
      _sessionFailedAttempts++;
      _failedAttemptsThisItem++;
      setState(() {
        if (!hadSpeechInput) {
          _banner = "Sorry, I can't hear you properly";
        } else {
          _banner = _pickEncouragement();
        }
        if (_failedAttemptsThisItem >= 2) {
          _hintLine = SpeakLearnEvaluator.guidanceHint(
            kind: k,
            expected: item.displayText,
          );
        }
      });
    }
  }

  Future<void> _goCompletion() async {
    final k = _kind;
    if (k == null) {
      return;
    }
    final moduleId = _module?.id ?? 'speak-learn-unknown';
    if (!_completionAnalyticsSent) {
      _completionAnalyticsSent = true;
      await SpeakLearnAnalytics.recordLevelCompletion(
        childId: widget.childId,
        kind: k,
        moduleId: moduleId,
        starRating: 3,
        totalItems: _items.length,
        correctItems: _masteredItemIndices.length,
        failedAttemptsTotal: _sessionFailedAttempts,
      );
    }
    if (!mounted) {
      return;
    }
    final pick =
        (_masteredItemIndices.length * 11 + k.index * 3) % _completionTitles.length;
    final subPick =
        (_items.length * 5 + k.index) % _completionSubtitles.length;
    _completionTitle = _completionTitles[pick];
    _completionSubtitle = _completionSubtitles[subPick];
    _trophyCtrl.forward(from: 0);
    setState(() => _phase = _Phase.completion);
  }

  void _onHubBack() => Navigator.pop(context);

  void _onPracticeBack() {
    setState(() {
      _phase = _Phase.hub;
      _kind = null;
      _module = null;
      _items = [];
      _banner = null;
      _hintLine = null;
      _masteredItemIndices.clear();
      _liveListenLabel = null;
    });
  }

  Future<void> _onCompletionReplay() async {
    final k = _kind;
    if (k == null) {
      return;
    }
    setState(() {
      _phase = _Phase.hub;
      _kind = null;
      _module = null;
      _items = [];
      _masteredItemIndices.clear();
    });
    await _showLevelIntroThenStart(k);
  }

  void _onCompletionBackToSpeakLearnHub() {
    setState(() {
      _phase = _Phase.hub;
      _kind = null;
      _module = null;
      _items = [];
      _banner = null;
      _hintLine = null;
      _masteredItemIndices.clear();
      _liveListenLabel = null;
      _completionAnalyticsSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: switch (_phase) {
        _Phase.hub => _buildHub(context),
        _Phase.practice => _buildPractice(context),
        _Phase.completion => _buildCompletion(context),
      },
    );
  }

  // —— Hub (level cards) —— //

  Widget _buildHub(BuildContext context) {
    final enabledKinds = SpeakLearnLevelKind.values
        .where(_levelAssigned)
        .toList(growable: false);

    return FigmaModuleScaffold(
      title: 'Speak & Learn',
      onBack: _onHubBack,
      child: enabledKinds.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 200),
              child: Center(
                child: Text(
                  'No Speak & Learn levels are selected in Learning Planner yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 200),
              children: [
                const SizedBox(height: 8),
                for (var i = 0; i < enabledKinds.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _hubCardForKind(enabledKinds[i]),
                ],
              ],
            ),
    );
  }

  Widget _hubCardForKind(SpeakLearnLevelKind kind) {
    return switch (kind) {
      SpeakLearnLevelKind.alphabets => _HubLevelCard(
          kind: kind,
          background: const Color(0xFFFFE4E8),
          onTap: () => _showLevelIntroThenStart(kind),
          trailing: _alphabetArt(),
        ),
      SpeakLearnLevelKind.words => _HubLevelCard(
          kind: kind,
          background: const Color(0xFFE4FCCD),
          onTap: () => _showLevelIntroThenStart(kind),
          trailing: _wordsArt(),
        ),
      SpeakLearnLevelKind.sentences => _HubLevelCard(
          kind: kind,
          background: const Color(0xFFD5F5F5),
          onTap: () => _showLevelIntroThenStart(kind),
          trailing: _sentencesArt(),
        ),
    };
  }

  Widget _alphabetArt() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _abcBlock(const Color(0xFFFFD447), 'A'),
        Transform.translate(
          offset: const Offset(-6, 10),
          child: _abcBlock(const Color(0xFF4ECDC4), 'B'),
        ),
        Transform.translate(
          offset: const Offset(-12, 4),
          child: _abcBlock(const Color(0xFFFF6B6B), 'C'),
        ),
      ],
    );
  }

  Widget _abcBlock(Color c, String letter) {
    return Container(
      width: 42,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _wordsArt() {
    const letters = <String>['W', 'O', 'R', 'D'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++)
          Container(
            margin: const EdgeInsets.only(left: 3),
            width: 30,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i.isEven ? const Color(0xFF7BC9FF) : const Color(0xFFFFD447),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              letters[i],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A2D4B),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sentencesArt() {
    return SizedBox(
      width: 92,
      height: 70,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 56,
              height: 40,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFB8E0FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  3,
                  (_) => Container(
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 60,
              height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4EA9E3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  3,
                  (_) => Container(
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EEF5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // —— Practice —— //

  Widget _buildPractice(BuildContext context) {
    final k = _kind!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                _PracticeHeader(
                  title: k.uiTitle,
                  subtitle: k.levelSubtitle,
                  onBack: _onPracticeBack,
                ),
                if (_loadingPractice)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _ProgressBar(
                    masteredCount: _masteredItemIndices.length,
                    total: _items.isEmpty ? 1 : _items.length,
                    currentItemIndex: _index,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            children: [
                              _SparkleRow(seed: _index),
                              const SizedBox(height: 10),
                              _ItemStarProgressRow(
                                itemCount: _items.length,
                                masteredIndices: _masteredItemIndices,
                                currentIndex: _index,
                              ),
                              const SizedBox(height: 16),
                              if (_current != null)
                                k == SpeakLearnLevelKind.sentences
                                    ? _sentenceCard()
                                    : _compactCard(k),
                              if (_listening && _liveListenLabel != null) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                    _liveListenLabel!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF4EA9E3),
                                    ),
                                  ),
                                ),
                              ],
                              if (_listeningPrompt() != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _listeningPrompt()!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE53935),
                                    ),
                                  ),
                                ),
                              if (_banner != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    _banner!,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _successTint
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFF5C6678),
                                    ),
                                  ),
                                ),
                              if (_hintLine != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _hintLine!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF4EA9E3),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 22),
                              _bottomNav(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: const ModuleBottomWaveLayer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactCard(SpeakLearnLevelKind k) {
    final item = _current!;
    final textColor =
        _successTint ? const Color(0xFF2E7D32) : const Color(0xFF1A1A1A);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 36, 72, 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (k == SpeakLearnLevelKind.words &&
                  (item.iconEmoji != null || item.imageUrl != null)) ...[
                if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                  Image.network(
                    item.imageUrl!,
                    height: 48,
                    errorBuilder: (_, __, ___) => Text(
                      item.iconEmoji ?? '',
                      style: const TextStyle(fontSize: 40),
                    ),
                  )
                else
                  Text(item.iconEmoji ?? '', style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
              ],
              Text(
                item.displayText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: k == SpeakLearnLevelKind.alphabets ? 72 : 36,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: 24,
          child: Column(
            children: [
              _RoundIconButton(
                icon: Icons.volume_up_rounded,
                filled: false,
                onTap: _listening ? null : _replayAudio,
              ),
              const SizedBox(height: 10),
              _RoundIconButton(
                icon: Icons.mic_rounded,
                filled: false,
                micStyle: true,
                active: _listening,
                onTap: _listening ? null : _onMic,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentenceCard() {
    final item = _current!;
    final textColor =
        _successTint ? const Color(0xFF2E7D32) : const Color(0xFF1A1A1A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          if (item.tag != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFB8E0FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                item.tag!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2D4B),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            item.displayText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  _RoundIconButton(
                    icon: Icons.volume_up_rounded,
                    filled: false,
                    large: true,
                    onTap: _listening ? null : _replayAudio,
                  ),
                ],
              ),
              const SizedBox(width: 28),
              Column(
                children: [
                  _RoundIconButton(
                    icon: Icons.mic_rounded,
                    filled: true,
                    large: true,
                    active: _listening,
                    onTap: _listening ? null : _onMic,
                  ),
                  const SizedBox(height: 6),
                  if (!_listening)
                    const Text(
                      'Tap to speak',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4EA9E3),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    final canBack = _index > 0;
    final canNext = _index < _items.length - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _NavCircle(
          icon: Icons.arrow_back_ios_new_rounded,
          enabled: canBack,
          onTap: canBack
              ? () {
                  setState(() {
                    _index--;
                    _failedAttemptsThisItem = 0;
                    _banner = null;
                    _hintLine = null;
                  });
                  _scheduleAutoSpeak();
                }
              : null,
        ),
        _NavCircle(
          icon: Icons.refresh_rounded,
          large: true,
          enabled: !_listening,
          onTap: _listening
              ? null
              : () {
                  setState(() {
                    _masteredItemIndices.clear();
                    _index = 0;
                    _failedAttemptsThisItem = 0;
                    _sessionFailedAttempts = 0;
                    _banner = null;
                    _hintLine = null;
                    _successTint = false;
                    _completionAnalyticsSent = false;
                  });
                },
        ),
        _NavCircle(
          icon: Icons.arrow_forward_ios_rounded,
          enabled: canNext,
          onTap: canNext
              ? () {
                  setState(() {
                    _index++;
                    _failedAttemptsThisItem = 0;
                    _banner = null;
                    _hintLine = null;
                  });
                  _scheduleAutoSpeak();
                }
              : null,
        ),
      ],
    );
  }

  // —— Completion (same screen) —— //

  Widget _buildCompletion(BuildContext context) {
    final k = _kind!;
    final badgeColor = switch (k) {
      SpeakLearnLevelKind.alphabets => const Color(0xFFCD7F32),
      SpeakLearnLevelKind.words => const Color(0xFFC0C0C0),
      SpeakLearnLevelKind.sentences => const Color(0xFFFFD700),
    };
    final badgeLabel = switch (k) {
      SpeakLearnLevelKind.alphabets => 'Bronze Badge',
      SpeakLearnLevelKind.words => 'Silver Badge',
      SpeakLearnLevelKind.sentences => 'Gold Badge',
    };

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF67C9F4), Color(0xFFEAF6FF)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ConfettiPainter(
                    t: _confettiCtrl.value,
                    seed: k.index * 17,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              child: Column(
                children: [
                  Text(
                    _completionTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.98),
                      shadows: const [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.black26,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You finished ${k.levelsCardLabel}!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF12213D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _completionSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C405B),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _trophyCtrl,
                      curve: Curves.elasticOut,
                    ),
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: badgeColor.withValues(alpha: 0.45),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        size: 86,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeLabel,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.star_rounded,
                          size: 44,
                          color: i < 3
                              ? const Color(0xFFFFD447)
                              : const Color(0xFFE0E6ED),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Three big stars for finishing the whole level!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onCompletionReplay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4EA9E3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        k == SpeakLearnLevelKind.alphabets
                            ? 'Replay Alphabets'
                            : k == SpeakLearnLevelKind.words
                                ? 'Replay Words'
                                : 'Replay Sentences',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _onCompletionBackToSpeakLearnHub,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF12213D),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF12213D)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Back to Speak & Learn levels',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// —— Private widgets (same library, not separate routes) —— //

class _HubLevelCard extends StatelessWidget {
  const _HubLevelCard({
    required this.kind,
    required this.background,
    required this.onTap,
    required this.trailing,
  });

  final SpeakLearnLevelKind kind;
  final Color background;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.levelsCardLabel,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kind.levelSubtitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeHeader extends StatelessWidget {
  const _PracticeHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF67C9F4),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 18),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF0F1E38),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.masteredCount,
    required this.total,
    required this.currentItemIndex,
  });

  final int masteredCount;
  final int total;
  final int currentItemIndex;

  @override
  Widget build(BuildContext context) {
    final t = total <= 0 ? 1 : total;
    final progress = (masteredCount / t).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A94A6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$masteredCount of $t mastered · item ${currentItemIndex + 1} of $t',
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5C6678),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8EEF5),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF4EA9E3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemStarProgressRow extends StatelessWidget {
  const _ItemStarProgressRow({
    required this.itemCount,
    required this.masteredIndices,
    required this.currentIndex,
  });

  final int itemCount;
  final Set<int> masteredIndices;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final spacing = itemCount > 20 ? 1.5 : 3.0;
        final raw = (maxW - (itemCount - 1) * spacing) / itemCount;
        final size = raw.clamp(9.0, 22.0);
        return Wrap(
          spacing: spacing,
          runSpacing: 5,
          alignment: WrapAlignment.center,
          children: List.generate(itemCount, (i) {
            final mastered = masteredIndices.contains(i);
            final here = i == currentIndex;
            return Icon(
              Icons.star_rounded,
              size: size,
              color: mastered
                  ? const Color(0xFFFFD447)
                  : here
                      ? const Color(0xFFFFE082)
                      : const Color(0xFFE0E6ED),
            );
          }),
        );
      },
    );
  }
}

class _SparkleRow extends StatelessWidget {
  const _SparkleRow({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(seed);
    final w = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(7, (i) {
          final x = (rnd.nextDouble() - 0.5) * 160;
          final y = rnd.nextDouble() * 12;
          final s = 6 + rnd.nextDouble() * 6;
          return Positioned(
            left: w / 2 + x - s,
            top: y,
            child: Icon(
              Icons.auto_awesome,
              size: s,
              color: Color.lerp(
                const Color(0xFFFFC93C),
                const Color(0xFF7BC9FF),
                rnd.nextDouble(),
              )!.withValues(alpha: 0.75),
            ),
          );
        }),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.filled,
    this.active = false,
    this.large = false,
    this.micStyle = false,
    this.onTap,
  });

  final IconData icon;
  final bool filled;
  final bool active;
  final bool large;
  final bool micStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = large ? 56.0 : 44.0;
    Color bg;
    Color fg;
    BoxBorder? boxBorder;
    if (active) {
      bg = const Color(0xFFE53935);
      fg = Colors.white;
    } else if (micStyle) {
      bg = Colors.white;
      fg = const Color(0xFF9A9A9A);
      boxBorder = Border.all(color: const Color(0xFF9A9A9A));
    } else if (filled) {
      bg = const Color(0xFF4EA9E3);
      fg = Colors.white;
    } else {
      bg = Colors.white;
      fg = const Color(0xFF4EA9E3);
      boxBorder = Border.all(color: const Color(0xFF4EA9E3));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: boxBorder,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: fg, size: large ? 28 : 22),
        ),
      ),
    );
  }
}

class _NavCircle extends StatelessWidget {
  const _NavCircle({
    required this.icon,
    this.large = false,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final bool large;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dim = large ? 56.0 : 40.0;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: large ? Colors.white : const Color(0xFFF0F3F8),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: dim,
            height: dim,
            child: Icon(
              icon,
              size: large ? 28 : 18,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.seed});

  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    for (var i = 0; i < 48; i++) {
      final x = rnd.nextDouble() * size.width;
      final baseY = (t + rnd.nextDouble()) % 1.0;
      final y = baseY * size.height * 1.15 - size.height * 0.1;
      final r = Rect.fromCenter(
        center: Offset(x, y),
        width: 6 + rnd.nextDouble() * 8,
        height: 4 + rnd.nextDouble() * 6,
      );
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFF6B9D),
          const Color(0xFF4ECDC4),
          rnd.nextDouble(),
        )!.withValues(alpha: 0.75);
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.rotate((t * 6 + i) * 0.4);
      canvas.translate(-r.center.dx, -r.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}
