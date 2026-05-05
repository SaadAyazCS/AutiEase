import 'package:flutter/material.dart';

import '../config/learning_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../modules/speak_learn/speak_learn_screen.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'move_play_screen.dart';
import 'focus_games_screen.dart';
import 'learning_planner_screen.dart';

class LearningModulesScreen extends StatelessWidget {
  const LearningModulesScreen({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Learn',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<LearningModuleModel>>(
          future: AppRepositories.content.getAssignedLearningModules(childId),
          builder: (context, snapshot) {
            final modules = snapshot.data ?? const <LearningModuleModel>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                modules.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (modules.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No learning games are assigned for this child yet.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningPlannerScreen(),
                            ),
                          );
                        },
                        child: const Text('Open Learning Planner'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final groupedModules = <String, List<LearningModuleModel>>{};
            for (final module in modules) {
              final categoryKey = module.learningCategoryKey.trim().isEmpty
                  ? 'general'
                  : module.learningCategoryKey.trim().toLowerCase();
              groupedModules.putIfAbsent(categoryKey, () => []).add(module);
            }

            final orderedKeys = <String>[
              ...LearningCatalog.orderedCategoryKeys.where(
                groupedModules.containsKey,
              ),
              ...groupedModules.keys.where(
                (key) => !LearningCatalog.orderedCategoryKeys.contains(key),
              ),
            ];

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 170),
              itemCount: orderedKeys.length,
              itemBuilder: (context, index) {
                final key = orderedKeys[index];
                final categoryModules = groupedModules[key]!
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final category = LearningCatalog.forKey(
                  key,
                  fallbackTitle: categoryModules.first.learningCategoryTitle,
                );

                String assetPath = '';
                Color cardColor = category.color;
                
                if (key == 'move_play') {
                  assetPath = 'assets/images/Move&Play.png';
                  cardColor = const Color(0xFFFFB6B6); // Soft Red
                } else if (key == 'speak_learn') {
                  assetPath = 'assets/images/Speak&learn.png';
                  cardColor = const Color(0xFFC1FF9B); // Soft Green
                } else if (key == 'focus_games') {
                  assetPath = 'assets/images/focusgames.png';
                  cardColor = const Color(0xFFC7F0E3); // Soft Teal
                }

                return _LearnCategoryCard(
                  category: category,
                  selectionCount: categoryModules.length,
                  assetPath: assetPath,
                  cardColor: cardColor,
                  onTap: () {
                    if (category.key == 'focus_games') {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => FocusGamesScreen(childId: childId),
                        ),
                      );
                      return;
                    }
                    final modules = List<LearningModuleModel>.from(
                      categoryModules,
                    );
                    if (category.key == 'speak_learn') {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SpeakLearnScreen(
                            childId: childId,
                            modules: modules,
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MovePlayScreen(
                          childId: childId,
                          category: category,
                          modules: modules,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LearnCategoryCard extends StatelessWidget {
  const _LearnCategoryCard({
    required this.category,
    required this.selectionCount,
    required this.onTap,
    required this.assetPath,
    required this.cardColor,
  });

  final LearningCategoryDefinition category;
  final int selectionCount;
  final VoidCallback onTap;
  final String assetPath;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final selectionText = category.key == 'speak_learn'
        ? '$selectionCount level${selectionCount == 1 ? '' : 's'} selected'
        : '$selectionCount game${selectionCount == 1 ? '' : 's'} selected';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectionText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (assetPath.isNotEmpty)
                  Image.asset(
                    assetPath,
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                  )
                else
                  Icon(
                    category.icon,
                    size: 48,
                    color: Colors.black.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
