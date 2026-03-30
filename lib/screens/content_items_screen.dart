import 'package:flutter/material.dart';

import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
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
  final TtsService _tts = TtsService();
  String? _resolvedChildId;
  String? _speakingItemId;

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
    await _tts.init();
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
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  Future<void> _onSpeak(CommunicationBoardItem item) async {
    setState(() {
      _speakingItemId = item.id;
    });
    try {
      await _tts.speak(item.speakText);
      if (_resolvedChildId != null && _board != null) {
        await AppRepositories.planner.recordActivityCompletion(
          childId: _resolvedChildId!,
          itemId: item.id,
          moduleId: _board!.id,
          score: 1,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _speakingItemId = null;
        });
      }
    }
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
        final speaking = item.id == _speakingItemId;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _onSpeak(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFC9C1E3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: speaking
                      ? const Color(0xFF2C74B8)
                      : Colors.transparent,
                  width: 1.5,
                ),
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
                  Icon(
                    Icons.mic_none_rounded,
                    size: 18,
                    color: speaking ? const Color(0xFF2C74B8) : Colors.black87,
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
        final speaking = item.id == _speakingItemId;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _onSpeak(item),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFC9DDF3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: speaking
                      ? const Color(0xFF2C74B8)
                      : Colors.transparent,
                  width: 1.5,
                ),
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
                      Icon(
                        Icons.mic_none_rounded,
                        size: 24,
                        color: speaking
                            ? const Color(0xFF2C74B8)
                            : Colors.black87,
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
