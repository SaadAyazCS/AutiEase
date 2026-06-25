import 'package:flutter/material.dart';

import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/communication_aac_service.dart';
import '../services/tts_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class ContentItemsScreen extends StatefulWidget {
  const ContentItemsScreen({super.key, required this.category, this.childId});

  final ContentCategory category;
  final String? childId;

  @override
  State<ContentItemsScreen> createState() => _ContentItemsScreenState();
}

class _ContentItemsScreenState extends State<ContentItemsScreen> {
  String? _resolvedChildId;
  bool _sentenceSheetOpen = false;

  CommunicationBoardDefinition? get _board {
    final byId = CommunicationFigmaCatalog.boardForId(widget.category.id);
    if (byId != null) {
      return byId;
    }
    final key = widget.category.title.toLowerCase();
    for (final board in CommunicationFigmaCatalog.boards) {
      if (board.title.toLowerCase() == key) {
        return board;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final resolvedChildId = widget.childId != null && widget.childId!.isNotEmpty
        ? widget.childId
        : (await AppRepositories.users.getActiveChildForCurrentParent())?.id;
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedChildId = resolvedChildId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: widget.category.title,
        onBack: () => Navigator.pop(context),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_board == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No communication board configuration was found for this category.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final board = _board!;
    return switch (board.layout) {
      CommunicationBoardLayout.alphabets => _buildAlphabetBoard(board),
      CommunicationBoardLayout.colors => _buildGridBoard(
        board,
        isColorBoard: true,
      ),
      CommunicationBoardLayout.grid => _buildGridBoard(
        board,
        isColorBoard: false,
      ),
    };
  }

  void _openSentenceBoard({
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
  }) async {
    if (_sentenceSheetOpen) {
      return;
    }
    final childId = _resolvedChildId;
    if (childId == null || childId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active child profile was found.')),
      );
      return;
    }

    _sentenceSheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: FractionallySizedBox(
              heightFactor: 0.9,
              child: CommunicationSentenceSheet(
                key: ValueKey('${childId}_${board.id}_${item.id}'),
                childId: childId,
                board: board,
                item: item,
              ),
            ),
          );
        },
      );
    } finally {
      _sentenceSheetOpen = false;
    }
  }

  Widget _buildAlphabetBoard(CommunicationBoardDefinition board) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 170),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemCount: board.items.length,
      itemBuilder: (context, index) {
        final item = board.items[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openSentenceBoard(board: board, item: item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFC9C1E3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.transparent, width: 1.5),
              ),
              child: Row(
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20 / 1.2,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridBoard(
    CommunicationBoardDefinition board, {
    required bool isColorBoard,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 170),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        childAspectRatio: 0.95,
      ),
      itemCount: board.items.length,
      itemBuilder: (context, index) {
        final item = board.items[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openSentenceBoard(board: board, item: item),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFC9DDF3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.transparent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(1, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: isColorBoard
                          ? _ColorSwatch(color: item.swatchColor ?? Colors.grey)
                          : _CommunicationVisual(item: item),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 22 / 1.2,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 24,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class CommunicationSentenceSheet extends StatefulWidget {
  const CommunicationSentenceSheet({
    super.key,
    required this.childId,
    required this.board,
    required this.item,
  });

  final String childId;
  final CommunicationBoardDefinition board;
  final CommunicationBoardItem item;

  @override
  State<CommunicationSentenceSheet> createState() =>
      _CommunicationSentenceSheetState();
}

class _CommunicationSentenceSheetState
    extends State<CommunicationSentenceSheet> {
  final CommunicationAacService _aac = const CommunicationAacService();
  final TtsService _tts = TtsService();
  final GlobalKey<ScaffoldMessengerState> _sheetMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final TextEditingController _sentenceEditorController =
      TextEditingController();

  CommunicationAacItemState? _state;
  List<CommunicationAacSentence> _draft = const <CommunicationAacSentence>[];
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _speakingSentenceId;
  String? _sentenceEditorTitle;
  int? _sentenceEditorIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sentenceEditorController.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _tts.init();
      final state = await _aac.loadItemState(
        childId: widget.childId,
        board: widget.board,
        item: widget.item,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
        _draft = List<CommunicationAacSentence>.from(state.sentences);
        _loading = false;
      });
    } catch (error) {
      debugPrint('Unable to load communication sentences: $error');
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showMessage('Unable to load sentences. Please try again.');
    }
  }

  Future<void> _speakSentence(CommunicationAacSentence sentence) async {
    if (_speakingSentenceId != null || _editing) {
      return;
    }
    setState(() {
      _speakingSentenceId = sentence.id;
      _state = _state?.incrementUsage(sentence.id);
    });
    try {
      await _tts.speak(sentence.text);
      try {
        await _aac.recordSentenceUse(
          childId: widget.childId,
          board: widget.board,
          item: widget.item,
          sentence: sentence,
        );
        await AppRepositories.planner.recordActivityCompletion(
          childId: widget.childId,
          itemId: widget.item.id,
          moduleId: widget.board.id,
          score: 1,
          metadata: {
            'communicationItemId': widget.item.id,
            'communicationItem': widget.item.label,
            'spokenSentence': sentence.text,
            'source': 'aac_sentence',
          },
        );
      } catch (error) {
        debugPrint('Unable to persist communication sentence use: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _speakingSentenceId = null);
      }
    }
  }

  void _enterEditMode() {
    final state = _state;
    if (state == null) {
      return;
    }
    setState(() {
      _editing = true;
      _draft = List<CommunicationAacSentence>.from(state.sentences);
    });
  }

  void _exitEditMode() {
    setState(() {
      _editing = false;
      _sentenceEditorTitle = null;
      _sentenceEditorIndex = null;
      _draft = List<CommunicationAacSentence>.from(
        _state?.sentences ?? const <CommunicationAacSentence>[],
      );
    });
    _sentenceEditorController.clear();
  }

  Future<void> _saveChanges() async {
    final cleaned = _draft
        .map((sentence) => sentence.copyWith(text: sentence.text.trim()))
        .where((sentence) => sentence.text.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      _showMessage('At least 1 sentence must stay on each card.');
      return;
    }
    if (cleaned.length > CommunicationAacService.maxSentencesPerItem) {
      _showMessage(
        'Only 10 sentences are allowed. Edit an existing sentence instead.',
      );
      return;
    }
    if (cleaned.any(_sentenceIsTooLong)) {
      _showMessage(
        'Sentences can be ${CommunicationAacService.maxSentenceTextLength} characters or fewer.',
      );
      return;
    }
    if (_hasDuplicateSentences(cleaned)) {
      _showMessage('This sentence already exists.');
      return;
    }
    final customCount = cleaned.where((sentence) => !sentence.isDefault).length;
    if (customCount > CommunicationAacService.maxCustomSentencesPerItem) {
      _showMessage('Only 5 custom sentences can be added.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _aac.saveItemState(
        childId: widget.childId,
        board: widget.board,
        item: widget.item,
        sentences: cleaned,
      );
      final updated = await _aac.loadItemState(
        childId: widget.childId,
        board: widget.board,
        item: widget.item,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _state = updated;
        _draft = List<CommunicationAacSentence>.from(updated.sentences);
        _editing = false;
      });
      _showMessage('Sentences saved.');
    } catch (error) {
      debugPrint('Unable to save communication sentences: $error');
      if (mounted) {
        _showMessage('Unable to save sentences. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addSentence() async {
    if (_draft.length >= CommunicationAacService.maxSentencesPerItem) {
      _showMessage(
        'Only 10 sentences are allowed. Edit an existing sentence instead.',
      );
      return;
    }
    if (_draft.where((sentence) => !sentence.isDefault).length >=
        CommunicationAacService.maxCustomSentencesPerItem) {
      _showMessage('Only 5 custom sentences can be added.');
      return;
    }
    _openSentenceEditor(title: 'Add Sentence');
  }

  void _editSentence(int index) {
    _openSentenceEditor(
      title: 'Edit Sentence',
      index: index,
      initialText: _draft[index].text,
    );
  }

  void _openSentenceEditor({
    required String title,
    int? index,
    String initialText = '',
  }) {
    _sentenceEditorController.text = initialText;
    _sentenceEditorController.selection = TextSelection.collapsed(
      offset: initialText.length,
    );
    setState(() {
      _sentenceEditorTitle = title;
      _sentenceEditorIndex = index;
    });
  }

  void _cancelSentenceEditor() {
    setState(() {
      _sentenceEditorTitle = null;
      _sentenceEditorIndex = null;
    });
    _sentenceEditorController.clear();
  }

  void _commitSentenceEditor() {
    final text = _sentenceEditorController.text.trim();
    if (text.isEmpty || _normalizeSentenceText(text).isEmpty) {
      _showMessage('Type a sentence first.');
      return;
    }
    if (text.length > CommunicationAacService.maxSentenceTextLength) {
      _showMessage(
        'Sentences can be ${CommunicationAacService.maxSentenceTextLength} characters or fewer.',
      );
      return;
    }
    final editingIndex = _sentenceEditorIndex;
    if (editingIndex == null &&
        _draft.length >= CommunicationAacService.maxSentencesPerItem) {
      _showMessage(
        'Only 10 sentences are allowed. Edit an existing sentence instead.',
      );
      return;
    }
    if (_sentenceAlreadyExists(text, exceptIndex: editingIndex)) {
      _showMessage('This sentence already exists.');
      return;
    }
    setState(() {
      final next = List<CommunicationAacSentence>.from(_draft);
      if (editingIndex == null) {
        next.add(
          CommunicationAacSentence(
            id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
            text: text,
            icon: _sentenceIconFallback,
            isDefault: false,
            isPinned: false,
            usageCount: 0,
            sortOrder: next.length,
          ),
        );
      } else if (editingIndex >= 0 && editingIndex < next.length) {
        next[editingIndex] = next[editingIndex].copyWith(text: text);
      }
      _draft = next;
      _sentenceEditorTitle = null;
      _sentenceEditorIndex = null;
    });
    _sentenceEditorController.clear();
  }

  void _restoreDefaults() {
    final defaults = _aac.defaultItemState(
      childId: widget.childId,
      board: widget.board,
      item: widget.item,
    );
    setState(() {
      _draft = List<CommunicationAacSentence>.from(defaults.sentences);
      _sentenceEditorTitle = null;
      _sentenceEditorIndex = null;
    });
    _sentenceEditorController.clear();
    _showMessage('Default sentences restored. Tap Save Changes to keep them.');
  }

  bool _sentenceAlreadyExists(String text, {int? exceptIndex}) {
    final normalized = _normalizeSentenceText(text);
    for (var i = 0; i < _draft.length; i++) {
      if (i == exceptIndex) {
        continue;
      }
      if (_normalizeSentenceText(_draft[i].text) == normalized) {
        return true;
      }
    }
    return false;
  }

  bool _hasDuplicateSentences(List<CommunicationAacSentence> sentences) {
    final seen = <String>{};
    for (final sentence in sentences) {
      final normalized = _normalizeSentenceText(sentence.text);
      if (normalized.isEmpty) {
        continue;
      }
      if (!seen.add(normalized)) {
        return true;
      }
    }
    return false;
  }

  bool _sentenceIsTooLong(CommunicationAacSentence sentence) {
    return sentence.text.length > CommunicationAacService.maxSentenceTextLength;
  }

  String _normalizeSentenceText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  void _deleteSentence(int index) {
    if (_draft.length <= 1) {
      _showMessage('At least 1 sentence must stay on each card.');
      return;
    }
    final deleted = _draft[index];
    setState(() {
      final next = List<CommunicationAacSentence>.from(_draft)..removeAt(index);
      _draft = next;
      if (_sentenceEditorIndex == index) {
        _sentenceEditorTitle = null;
        _sentenceEditorIndex = null;
        _sentenceEditorController.clear();
      } else if (_sentenceEditorIndex != null &&
          _sentenceEditorIndex! > index) {
        _sentenceEditorIndex = _sentenceEditorIndex! - 1;
      }
    });
    _showMessage(
      'Sentence deleted.',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) {
          return;
        }
        if (_draft.length >= CommunicationAacService.maxSentencesPerItem) {
          _showMessage(
            'Only 10 sentences are allowed. Edit an existing sentence instead.',
          );
          return;
        }
        if (_sentenceAlreadyExists(deleted.text)) {
          _showMessage('This sentence already exists.');
          return;
        }
        setState(() {
          final next = List<CommunicationAacSentence>.from(_draft);
          final insertIndex = index > next.length ? next.length : index;
          next.insert(insertIndex, deleted);
          _draft = [
            for (var i = 0; i < next.length; i++)
              next[i].copyWith(sortOrder: i),
          ];
        });
      },
    );
  }

  void _togglePinned(int index) {
    setState(() {
      final next = List<CommunicationAacSentence>.from(_draft);
      final current = next[index];
      next[index] = current.copyWith(isPinned: !current.isPinned);
      _draft = next;
    });
  }

  void _reorderDraft(int oldIndex, int newIndex) {
    setState(() {
      final next = List<CommunicationAacSentence>.from(_draft);
      final moved = next.removeAt(oldIndex);
      next.insert(newIndex, moved);
      _draft = [
        for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
      ];
    });
  }

  String get _sentenceIconFallback {
    if (widget.item.emoji != null && widget.item.emoji!.trim().isNotEmpty) {
      return widget.item.emoji!;
    }
    if (widget.board.id == 'colors') {
      return '\u{1F3A8}';
    }
    return '\u{1F4AC}';
  }

  void _showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger =
        _sheetMessengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: actionLabel != null && onAction != null
              ? SnackBarAction(label: actionLabel, onPressed: onAction)
              : null,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: actionLabel == null
              ? const Duration(seconds: 2)
              : const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _sheetMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Material(
          color: Colors.transparent,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4DCE5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _editing
                                ? 'Edit ${widget.item.label}'
                                : widget.item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF12213D),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _editing
                              ? 'Close edit mode'
                              : 'Edit sentences',
                          onPressed: _loading
                              ? null
                              : (_editing ? _exitEditMode : _enterEditMode),
                          icon: Icon(
                            _editing ? Icons.close_rounded : Icons.edit_rounded,
                            color: const Color(0xFF12213D),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Color(0xFF12213D),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _editing
                          ? _buildEditMode()
                          : _buildSentenceList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSentenceList() {
    final state = _state;
    if (state == null) {
      return const Center(child: Text('No sentences found.'));
    }
    final display = state.displaySentences;
    final frequent = state.frequentSentences;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      children: [
        _ItemHeaderCard(board: widget.board, item: widget.item),
        if (frequent.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SentenceSectionTitle(
            icon: Icons.star_rounded,
            title: 'Frequently Used',
          ),
          const SizedBox(height: 8),
          for (final sentence in frequent)
            _SentenceChoiceCard(
              sentence: sentence,
              speaking: sentence.id == _speakingSentenceId,
              onTap: () => _speakSentence(sentence),
            ),
        ],
        const SizedBox(height: 16),
        const _SentenceSectionTitle(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Sentences',
        ),
        const SizedBox(height: 8),
        for (final sentence in display)
          _SentenceChoiceCard(
            sentence: sentence,
            speaking: sentence.id == _speakingSentenceId,
            onTap: () => _speakSentence(sentence),
          ),
      ],
    );
  }

  Widget _buildEditMode() {
    final editorTitle = _sentenceEditorTitle;
    final sentenceCountLabel =
        '${_draft.length}/${CommunicationAacService.maxSentencesPerItem} sentences';
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFB8E0FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Parent edit mode: edit, pin, delete, or drag sentences.',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334A6E),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFB8E0FF),
                              ),
                            ),
                            child: Text(
                              sentenceCountLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF334A6E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _restoreDefaults,
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Restore defaults'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (editorTitle != null) ...[
                  _SentenceEditorPanel(
                    title: editorTitle,
                    controller: _sentenceEditorController,
                    maxLength: CommunicationAacService.maxSentenceTextLength,
                    onCancel: _cancelSentenceEditor,
                    onDone: _commitSentenceEditor,
                  ),
                  const SizedBox(height: 10),
                ],
                ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _draft.length,
                  onReorderItem: _reorderDraft,
                  itemBuilder: (context, index) {
                    final sentence = _draft[index];
                    return _EditableSentenceTile(
                      key: ValueKey(sentence.id),
                      sentence: sentence,
                      index: index,
                      onEdit: () => _editSentence(index),
                      onDelete: () => _deleteSentence(index),
                      onTogglePinned: () => _togglePinned(index),
                    );
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || editorTitle != null
                            ? null
                            : _addSentence,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Sentence'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving || editorTitle != null
                            ? null
                            : _saveChanges,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ItemHeaderCard extends StatelessWidget {
  const _ItemHeaderCard({required this.board, required this.item});

  final CommunicationBoardDefinition board;
  final CommunicationBoardItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFC9DDF3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: board.layout == CommunicationBoardLayout.colors
                ? _ColorSwatch(color: item.swatchColor ?? Colors.grey)
                : _CommunicationVisual(item: item),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101B2D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${board.title} sentences',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F5E75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SentenceSectionTitle extends StatelessWidget {
  const _SentenceSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4EA9E3), size: 20),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF23324A),
          ),
        ),
      ],
    );
  }
}

class _SentenceChoiceCard extends StatelessWidget {
  const _SentenceChoiceCard({
    required this.sentence,
    required this.speaking,
    required this.onTap,
  });

  final CommunicationAacSentence sentence;
  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pinned = sentence.isPinned;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: speaking
                  ? const Color(0xFFEAF6FF)
                  : pinned
                  ? const Color(0xFFFFF6D7)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: speaking
                    ? const Color(0xFF4EA9E3)
                    : pinned
                    ? const Color(0xFFE9B126)
                    : const Color(0xFFE1E8F0),
                width: speaking ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(sentence.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sentence.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  speaking ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                  color: speaking
                      ? const Color(0xFF2C74B8)
                      : const Color(0xFF4F5E75),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SentenceEditorPanel extends StatelessWidget {
  const _SentenceEditorPanel({
    required this.title,
    required this.controller,
    required this.maxLength,
    required this.onCancel,
    required this.onDone,
  });

  final String title;
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB8E0FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF23324A),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Type a sentence',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onDone,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditableSentenceTile extends StatelessWidget {
  const _EditableSentenceTile({
    super.key,
    required this.sentence,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePinned,
  });

  final CommunicationAacSentence sentence;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePinned;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(
        color: sentence.isPinned ? const Color(0xFFFFF6D7) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sentence.isPinned
              ? const Color(0xFFE9B126)
              : const Color(0xFFE1E8F0),
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle_rounded, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Text(sentence.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sentence.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF23324A),
              ),
            ),
          ),
          IconButton(
            tooltip: sentence.isPinned ? 'Unpin' : 'Pin',
            onPressed: onTogglePinned,
            icon: Icon(
              sentence.isPinned
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: sentence.isPinned
                  ? const Color(0xFFE9B126)
                  : const Color(0xFF6B7280),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF4EA9E3)),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFE85252)),
          ),
        ],
      ),
    );
  }
}

class _CommunicationVisual extends StatelessWidget {
  const _CommunicationVisual({required this.item});

  final CommunicationBoardItem item;

  @override
  Widget build(BuildContext context) {
    if (item.symbol != null) {
      return Text(
        item.symbol!,
        style: TextStyle(
          color: item.symbolColor ?? Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: 54,
        ),
      );
    }
    return Text(
      item.emoji ?? '\u{1F539}',
      style: const TextStyle(fontSize: 52),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
