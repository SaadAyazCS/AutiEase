import 'package:flutter/material.dart';

import '../config/learning_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../modules/speak_learn/speak_learn_screen.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'move_play_screen.dart';
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
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              itemCount: orderedKeys.length,
              itemBuilder: (context, index) {
                final key = orderedKeys[index];
                final categoryModules = groupedModules[key]!
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final category = LearningCatalog.forKey(
                  key,
                  fallbackTitle: categoryModules.first.learningCategoryTitle,
                );

                return _LearnCategoryCard(
                  category: category,
                  selectionCount: categoryModules.length,
                  onTap: () {
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
  });

  final LearningCategoryDefinition category;
  final int selectionCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: category.color,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2D4B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        category.key == 'speak_learn'
                            ? '$selectionCount level${selectionCount == 1 ? '' : 's'} selected'
                            : '$selectionCount game${selectionCount == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                          color: Color(0xFF2C405B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(category.icon, size: 36, color: const Color(0xFF2A4A7A)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
