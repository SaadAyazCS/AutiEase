import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'learning_game_screen.dart';

class FocusGamesScreen extends StatelessWidget {
  const FocusGamesScreen({
    super.key,
    required this.childId,
  });

  final String childId;

  String _normalizeKey(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _displayLevelLabel(String gameKey) {
    final fingerprint = _normalizeKey(gameKey);
    if (fingerprint.contains('find')) {
      return 'Level 1';
    }
    if (fingerprint.contains('match')) {
      return 'Level 2';
    }
    if (fingerprint.contains('hold')) {
      return 'Level 3';
    }
    return 'Level 1';
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Focus Games',
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
                  child: Text(
                    'No focus games are assigned yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // Filter only focus games
            final focusModules = modules.where((module) {
              final gameKey = _normalizeKey(module.gameTypeKey);
              final moduleKey = _normalizeKey(module.id);
              final titleKey = _normalizeKey(module.title);
              return gameKey.contains('focus') ||
                  moduleKey.contains('focus') ||
                  titleKey.contains('focus') ||
                  gameKey.contains('find') ||
                  gameKey.contains('match') ||
                  gameKey.contains('hold');
            }).toList();

            if (focusModules.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No focus games are assigned yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 170),
              itemCount: focusModules.length,
              itemBuilder: (context, index) {
                final module = focusModules[index];
                final gameKey = _normalizeKey(module.gameTypeKey);
                final moduleKey = _normalizeKey(module.id);
                final titleKey = _normalizeKey(module.title);

                Color cardColor = Colors.white;
                String? assetPath;
                String levelText = _displayLevelLabel(module.gameTypeKey);

                if (gameKey.contains('find') || moduleKey.contains('find') || titleKey.contains('find')) {
                  cardColor = const Color(0xFFFFB6B6); // Soft Red
                  assetPath = 'assets/images/Find it.png';
                } else if (gameKey.contains('match') || moduleKey.contains('match') || titleKey.contains('match')) {
                  cardColor = const Color(0xFFC1FF9B); // Soft Green
                  assetPath = 'assets/images/Match it.png';
                } else if (gameKey.contains('hold') || moduleKey.contains('hold') || titleKey.contains('hold')) {
                  cardColor = const Color(0xFFC7F0E3); // Soft Teal/Green
                  assetPath = 'assets/images/Hold it.png';
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
                            builder: (_) => LearningGameScreen(
                              childId: childId,
                              module: module,
                            ),
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
                                Icons.psychology_rounded,
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
            );
          },
        ),
      ),
    );
  }
}
