import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'alphabets_screen.dart';
import 'animals_screen.dart';
import 'clothes_screen.dart';
import 'colors_screen.dart';
import 'emotions_screen.dart';
import 'family_screen.dart';
import 'food_screen.dart';
import 'learning_game_screen.dart';
import 'numbers_screen.dart';
import 'shapes_screen.dart';

class LearningModulesScreen extends StatelessWidget {
  const LearningModulesScreen({super.key, required this.childId});

  final String childId;

  Widget? _legacyGameScreen(LearningModuleModel module) {
    final key = '${module.id} ${module.title}'.toLowerCase();
    if (key.contains('alphabet')) {
      return const AlphabetsScreen();
    }
    if (key.contains('number')) {
      return const NumbersScreen();
    }
    if (key.contains('color')) {
      return const ColorsScreen();
    }
    if (key.contains('shape')) {
      return const ShapesScreen();
    }
    if (key.contains('animal')) {
      return const AnimalsScreen();
    }
    if (key.contains('family')) {
      return const FamilyScreen();
    }
    if (key.contains('cloth')) {
      return const ClothesScreen();
    }
    if (key.contains('food')) {
      return const FoodScreen();
    }
    if (key.contains('emotion') || key.contains('feeling')) {
      return const EmotionsScreen();
    }
    return null;
  }

  Future<void> _playModule(
    BuildContext context,
    LearningModuleModel module,
  ) async {
    final legacyScreen = _legacyGameScreen(module);
    if (legacyScreen != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => legacyScreen),
      );
      await AppRepositories.planner.recordActivityCompletion(
        childId: childId,
        itemId: module.id,
        moduleId: module.id,
        score: 1,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${module.title} gameplay session saved'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LearningGameScreen(childId: childId, module: module),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Learning Modules',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<LearningModuleModel>>(
          future: AppRepositories.content.getAssignedLearningModules(childId),
          builder: (context, snapshot) {
            final modules = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                modules.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (modules.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No learning modules have been assigned in Firestore yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
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
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2D4B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(module.description),
                      const SizedBox(height: 10),
                      Text('Level range: ${module.levelRange}'),
                      const SizedBox(height: 4),
                      Text('Type: ${module.type}'),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _playModule(context, module),
                            icon: const Icon(Icons.sports_esports_outlined),
                            label: const Text('Play game'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await AppRepositories.planner
                                  .recordActivityCompletion(
                                    childId: childId,
                                    itemId: module.id,
                                    moduleId: module.id,
                                    score: 1,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${module.title} marked complete',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Mark complete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
