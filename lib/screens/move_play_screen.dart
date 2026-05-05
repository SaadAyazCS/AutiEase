import 'package:flutter/material.dart';

import '../config/learning_catalog.dart';
import '../models/app_models.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'drag_game_screen.dart';
import 'learning_game_screen.dart';
import 'tap_game_screen.dart';
import 'trace_game_screen.dart';

class MovePlayScreen extends StatelessWidget {
  const MovePlayScreen({
    super.key,
    required this.childId,
    required this.category,
    required this.modules,
  });

  final String childId;
  final LearningCategoryDefinition category;
  final List<LearningModuleModel> modules;

  String _normalizeKey(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _displayLevelLabel(LearningModuleModel module) {
    if (category.key != 'move_play') {
      return module.levelRange;
    }
    final fingerprint = _normalizeKey(
      '${module.gameTypeKey} ${module.id} ${module.title}',
    );
    if (fingerprint.contains('tap')) {
      return 'Level 1';
    }
    if (fingerprint.contains('drag')) {
      return 'Level 2';
    }
    if (fingerprint.contains('trace')) {
      return 'Level 3';
    }
    return module.levelRange;
  }

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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 170),
                itemCount: modules.length,
                itemBuilder: (context, index) {
                  final module = modules[index];
                  final gameKey = _normalizeKey(module.gameTypeKey);
                  final moduleKey = _normalizeKey(module.id);
                  final titleKey = _normalizeKey(module.title);

                  final isTapGame = gameKey == 'tap_game' ||
                      moduleKey.contains('tap') ||
                      titleKey.contains('tap');
                  final isDragGame = gameKey == 'drag_game' ||
                      moduleKey.contains('drag') ||
                      titleKey.contains('drag');
                  final isTraceGame = gameKey == 'trace_game' ||
                      moduleKey.contains('trace') ||
                      titleKey.contains('trace');

                  Color cardColor = Colors.white;
                  String? assetPath;
                  String levelText = _displayLevelLabel(module);

                  if (isTapGame) {
                    cardColor = const Color(0xFFFFB6B6); // Soft Red
                    assetPath = 'assets/images/Tap game.png';
                  } else if (isDragGame) {
                    cardColor = const Color(0xFFC1FF9B); // Soft Green
                    assetPath = 'assets/images/Drag Game.png';
                  } else if (isTraceGame) {
                    cardColor = const Color(0xFFC7F0E3); // Soft Teal/Green
                    assetPath = 'assets/images/Trace game.png';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        onTap: () {
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
                        borderRadius: BorderRadius.circular(28),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 24,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      module.title,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      levelText,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (assetPath != null)
                                Image.asset(
                                  assetPath,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.contain,
                                )
                              else
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 48,
                                  color: Colors.black.withValues(alpha: 0.7),
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
    );
  }
}
