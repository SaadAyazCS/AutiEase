import 'package:flutter/material.dart';

import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/bouncing_button.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'content_items_screen.dart';
import 'learning_planner_screen.dart';

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
            final boards = _orderedBoards(
              allowedBoardIds: allowedBoardIds,
              categories: access.categories,
            );
            if (boards.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4EA9E3).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 64,
                          color: Color(0xFF4EA9E3),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No topics assigned yet',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Select communication topics from the Learning Planner to start building sentences.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF64748B),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      BouncingButton(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningPlannerScreen(),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4EA9E3), Color(0xFF2D7CF6)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4EA9E3).withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_calendar_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Open Learning Planner',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
    if (assignment == null) {
      return <String>{
        for (final id in CommunicationFigmaCatalog.homeBoardOrder)
          if (!CommunicationFigmaCatalog.isHiddenBoardId(id)) id,
      };
    }

    final selectedIds = assignment.assignedCategoryIds;

    final boardById = <String, CommunicationBoardDefinition>{
      for (final board in CommunicationFigmaCatalog.boards)
        if (!CommunicationFigmaCatalog.isHiddenBoardId(board.id))
          board.id: board,
    };
    final categoryToBoardId = _categoryToBoardIdMap(
      categories: categories,
      boardById: boardById,
    );

    final allowed = <String>{};
    if (selectedIds.isEmpty) {
      return allowed;
    }
    for (final id in selectedIds) {
      if (CommunicationFigmaCatalog.isHiddenBoardId(id)) {
        continue;
      }
      if (boardById.containsKey(id)) {
        allowed.add(id);
      }
      final mapped = categoryToBoardId[id];
      if (mapped != null &&
          mapped.isNotEmpty &&
          !CommunicationFigmaCatalog.isHiddenBoardId(mapped)) {
        allowed.add(mapped);
      }
    }
    return allowed;
  }

  List<CommunicationBoardDefinition> _orderedBoards({
    required Set<String> allowedBoardIds,
    required List<ContentCategory> categories,
  }) {
    if (allowedBoardIds.isEmpty) {
      return const <CommunicationBoardDefinition>[];
    }

    final boardById = <String, CommunicationBoardDefinition>{
      for (final board in CommunicationFigmaCatalog.boards)
        if (!CommunicationFigmaCatalog.isHiddenBoardId(board.id))
          board.id: board,
    };
    final categoryToBoardId = _categoryToBoardIdMap(
      categories: categories,
      boardById: boardById,
    );
    final orderedIds = <String>[];

    void addIfAllowed(String id) {
      if (!allowedBoardIds.contains(id) || orderedIds.contains(id)) {
        return;
      }
      if (CommunicationFigmaCatalog.isHiddenBoardId(id)) {
        return;
      }
      if (!boardById.containsKey(id)) {
        return;
      }
      orderedIds.add(id);
    }

    for (final id in CommunicationFigmaCatalog.homeBoardOrder) {
      addIfAllowed(id);
    }

    for (final category in categories) {
      final mapped = categoryToBoardId[category.id];
      if (mapped != null) {
        addIfAllowed(mapped);
      }
    }

    for (final board in CommunicationFigmaCatalog.boards) {
      addIfAllowed(board.id);
    }

    return orderedIds
        .map((id) => boardById[id])
        .whereType<CommunicationBoardDefinition>()
        .toList();
  }

  Map<String, String> _categoryToBoardIdMap({
    required List<ContentCategory> categories,
    required Map<String, CommunicationBoardDefinition> boardById,
  }) {
    final boardByTitle = <String, String>{
      for (final board in CommunicationFigmaCatalog.boards)
        if (!CommunicationFigmaCatalog.isHiddenBoardId(board.id))
          board.title.trim().toLowerCase(): board.id,
    };
    final categoryToBoardId = <String, String>{};
    for (final category in categories) {
      if (CommunicationFigmaCatalog.isHiddenBoardId(category.id) ||
          CommunicationFigmaCatalog.isHiddenBoardTitle(category.title)) {
        continue;
      }
      if (boardById.containsKey(category.id)) {
        categoryToBoardId[category.id] = category.id;
        continue;
      }
      final mappedByTitle = boardByTitle[category.title.trim().toLowerCase()];
      if (mappedByTitle != null) {
        categoryToBoardId[category.id] = mappedByTitle;
      }
    }
    return categoryToBoardId;
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
