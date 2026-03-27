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
            title: child == null ? 'Child Profile' : '${child.name}\'s Profile',
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
                : FutureBuilder<ChildAssignment?>(
                    future: AppRepositories.planner.getAssignmentForChild(
                      child.id,
                    ),
                    builder: (context, assignmentSnapshot) {
                      final assignment = assignmentSnapshot.data;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                        children: [
                          _ChildInfoCard(
                            title: child.name,
                            subtitle:
                                'Assigned support areas: ${child.supportAreas.join(', ')}',
                          ),
                          const SizedBox(height: 20),
                          _ChildModuleCard(
                            title: 'Communication',
                            subtitle:
                                '${assignment?.assignedCategoryIds.length ?? 0} topics assigned',
                            color: const Color(0xFFD7B3B3),
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
                          const SizedBox(height: 16),
                          _ChildModuleCard(
                            title: 'Learning',
                            subtitle:
                                '${assignment?.assignedModuleIds.length ?? 0} modules assigned',
                            color: const Color(0xFF75CC40),
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
                          const SizedBox(height: 16),
                          _ChildModuleCard(
                            title: 'Daily Activities',
                            subtitle:
                                '${assignment?.assignedActivityTemplateIds.length ?? 0} activities assigned',
                            color: const Color(0xFFBBB3D7),
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
                        ],
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _ChildInfoCard extends StatelessWidget {
  const _ChildInfoCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _ChildModuleCard extends StatelessWidget {
  const _ChildModuleCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
        ),
      ),
    );
  }
}
