import 'package:flutter/material.dart';

import '../config/learning_catalog.dart';
import '../models/app_models.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'drag_game_screen.dart';
import 'learning_game_screen.dart';
import 'tap_game_screen.dart';
import 'trace_game_screen.dart';

class LearningCategoryGamesScreen extends StatelessWidget {
  const LearningCategoryGamesScreen({
    super.key,
    required this.childId,
    required this.category,
    required this.modules,
  });

  final String childId;
  final LearningCategoryDefinition category;
  final List<LearningModuleModel> modules;

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: category.title,
        onBack: () => Navigator.pop(context),
        child: modules.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No games are assigned in this category yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                itemCount: modules.length,
                itemBuilder: (context, index) {
                  final module = modules[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2D4B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(module.description),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                final isTapGame =
                                    module.gameTypeKey.toLowerCase() ==
                                        'tap_game' ||
                                    module.id.toLowerCase() == 'move-play-tap';
                                final isDragGame =
                                    module.gameTypeKey.toLowerCase() ==
                                        'drag_game' ||
                                    module.id.toLowerCase() == 'move-play-drag';
                                final isTraceGame =
                                    module.gameTypeKey.toLowerCase() ==
                                        'trace_game' ||
                                    module.id.toLowerCase() ==
                                        'move-play-trace';
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) {
                                      if (isTapGame) {
                                        return TapGameScreen(
                                          childId: childId,
                                          module: module,
                                        );
                                      }
                                      if (isDragGame) {
                                        return DragGameScreen(
                                          childId: childId,
                                          module: module,
                                        );
                                      }
                                      if (isTraceGame) {
                                        return TraceGameScreen(
                                          childId: childId,
                                          module: module,
                                        );
                                      }
                                      return LearningGameScreen(
                                        childId: childId,
                                        module: module,
                                      );
                                    },
                                  ),
                                );
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            Chip(
                              avatar: const Icon(
                                Icons.flag_outlined,
                                size: 16,
                                color: AppColors.primaryBlue,
                              ),
                              label: Text(module.levelRange),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
