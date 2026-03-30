import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'communication_screen.dart';
import 'daily_activities_screen.dart';
import 'learning_modules_screen.dart';

class ChildProfileHomeScreen extends StatelessWidget {
  const ChildProfileHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FutureBuilder<List<Object?>>(
        future: Future.wait([
          AppRepositories.users.getActiveChildForCurrentParent(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final child = snapshot.data?[0] as ChildProfile?;
          return FigmaModuleScaffold(
            title: 'Child Profile',
            onBack: () => Navigator.pop(context),
            child: child == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No child profile is connected to this parent account yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                    children: [
                      const SizedBox(height: 18),
                      Center(
                        child: _ChildModuleCard(
                          title: 'Communication',
                          iconAssetPath: 'assets/images/Communication.png',
                          color: const Color(0xFFD9BCC0),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CommunicationScreen(childId: child.id),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: _ChildModuleCard(
                          title: 'Learn',
                          iconAssetPath: 'assets/images/Learn.png',
                          color: const Color(0xFF86D44A),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LearningModulesScreen(childId: child.id),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: _ChildModuleCard(
                          title: 'Daily Activities',
                          iconAssetPath: 'assets/images/Daily_Activities.png',
                          color: const Color(0xFFB7AFD9),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DailyActivitiesScreen(childId: child.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ChildModuleCard extends StatelessWidget {
  const _ChildModuleCard({
    required this.title,
    required this.iconAssetPath,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String iconAssetPath;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - 72).clamp(270.0, 330.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: cardWidth,
          height: 124,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21 / 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B2843),
                ),
              ),
              const SizedBox(height: 8),
              Image.asset(
                iconAssetPath,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
