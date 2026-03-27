import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class DailyActivitiesScreen extends StatelessWidget {
  const DailyActivitiesScreen({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Daily Activities',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<DailyActivityTemplate>>(
          future: AppRepositories.content.getAssignedActivities(childId),
          builder: (context, snapshot) {
            final activities = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                activities.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (activities.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No daily activities have been assigned in Firestore yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              itemCount: activities.length,
              itemBuilder: (context, index) {
                final activity = activities[index];
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
                        activity.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2D4B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(activity.description),
                      const SizedBox(height: 10),
                      Text(
                        '${activity.estimatedMinutes} minutes - ${activity.difficulty}',
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await AppRepositories.planner
                              .recordActivityCompletion(
                                childId: childId,
                                itemId: activity.id,
                                score: 1,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${activity.title} marked complete',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Complete activity'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                        ),
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
