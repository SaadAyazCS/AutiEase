import 'package:flutter/material.dart';

import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'content_items_screen.dart';

class CommunicationScreen extends StatelessWidget {
  const CommunicationScreen({super.key, this.childId});

  final String? childId;

  Future<_CommunicationAccessContext?> _resolveAccessContext() async {
    final resolvedChildId = await _resolveChildId();
    if (resolvedChildId == null) {
      return null;
    }
    final results = await Future.wait([
      AppRepositories.planner.getAssignmentForChild(resolvedChildId),
      AppRepositories.content.getAllCategories(type: 'communication'),
    ]);
    return _CommunicationAccessContext(
      childId: resolvedChildId,
      assignment: results[0] as ChildAssignment?,
      categories: results[1] as List<ContentCategory>,
    );
  }

  Future<String?> _resolveChildId() async {
    if (childId != null && childId!.isNotEmpty) {
      return childId;
    }
    return (await AppRepositories.users.getActiveChildForCurrentParent())?.id;
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Communication',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<_CommunicationAccessContext?>(
          future: _resolveAccessContext(),
          builder: (context, snapshot) {
            final access = snapshot.data;
            if (access == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No active child profile was found for this communication space.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final allowedBoardIds = _allowedBoardIds(
              assignment: access.assignment,
              categories: access.categories,
            );
            final boards = CommunicationFigmaCatalog.homeBoardOrder
                .where((id) => allowedBoardIds.contains(id))
                .map(CommunicationFigmaCatalog.boardForId)
                .whereType<CommunicationBoardDefinition>()
                .toList();
            if (boards.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No communication topics are selected in Learning Planner yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: 0.8,
              ),
              itemCount: boards.length,
              itemBuilder: (context, index) {
                final board = boards[index];
                return _CommunicationBoardCard(
                  board: board,
                  childId: access.childId,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Set<String> _allowedBoardIds({
    required ChildAssignment? assignment,
    required List<ContentCategory> categories,
  }) {
    final defaultBoardIds = <String>{
      ...CommunicationFigmaCatalog.homeBoardOrder,
    };
    final selectedIds = assignment?.assignedCategoryIds ?? const <String>[];

    final boardById = <String, CommunicationBoardDefinition>{
      for (final board in CommunicationFigmaCatalog.boards) board.id: board,
    };
    final categoryToBoardId = <String, String>{};
    for (final category in categories) {
      if (boardById.containsKey(category.id)) {
        categoryToBoardId[category.id] = category.id;
        continue;
      }
      final matchedByTitle = CommunicationFigmaCatalog.boards
          .where(
            (board) =>
                board.title.toLowerCase() == category.title.toLowerCase(),
          )
          .map((board) => board.id)
          .firstWhere((_) => true, orElse: () => '');
      if (matchedByTitle.isNotEmpty) {
        categoryToBoardId[category.id] = matchedByTitle;
      }
    }

    final allowed = <String>{...defaultBoardIds};
    if (selectedIds.isEmpty) {
      return allowed;
    }
    for (final id in selectedIds) {
      if (boardById.containsKey(id)) {
        allowed.add(id);
      }
      final mapped = categoryToBoardId[id];
      if (mapped != null && mapped.isNotEmpty) {
        allowed.add(mapped);
      }
    }
    return allowed;
  }
}

class _CommunicationBoardCard extends StatelessWidget {
  const _CommunicationBoardCard({required this.board, required this.childId});

  final CommunicationBoardDefinition board;
  final String childId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContentItemsScreen(
                category: ContentCategory(
                  id: board.id,
                  type: 'communication',
                  title: board.title,
                  icon: '',
                  imageUrl: '',
                  sortOrder: 0,
                  isActive: true,
                ),
                childId: childId,
              ),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFC9DDF3),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                offset: const Offset(1, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(board.homeEmoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                board.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24 / 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101B2D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunicationAccessContext {
  const _CommunicationAccessContext({
    required this.childId,
    required this.assignment,
    required this.categories,
  });

  final String childId;
  final ChildAssignment? assignment;
  final List<ContentCategory> categories;
}
