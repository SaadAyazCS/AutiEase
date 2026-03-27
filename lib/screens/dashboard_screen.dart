import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FutureBuilder<ChildProfile?>(
        future: AppRepositories.users.getActiveChildForCurrentParent(),
        builder: (context, childSnapshot) {
          if (childSnapshot.connectionState == ConnectionState.waiting &&
              !childSnapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final child = childSnapshot.data;
          return FigmaModuleScaffold(
            title: 'Dashboard',
            onBack: () => Navigator.pop(context),
            child: child == null
                ? const _DashboardEmptyState(
                    title: 'No child profile found',
                    message:
                        'Create a child profile first so the dashboard can show progress, mood, and activity summaries.',
                  )
                : StreamBuilder<DashboardSnapshot?>(
                    stream: AppRepositories.planner.watchDashboard(child.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final dashboard = snapshot.data;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                        children: [
                          _SectionCard(
                            title: 'Progress overview for ${child.name}',
                            body:
                                'This dashboard reflects your child\'s latest progress from Firestore.',
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _MetricCard(
                                title: 'Completed Tasks',
                                value: '${dashboard?.completedTasks ?? 0}',
                                color: const Color(0xFFFBA6A6),
                              ),
                              _MetricCard(
                                title: 'Weekly Minutes',
                                value: '${dashboard?.weeklyMinutes ?? 0}',
                                color: const Color(0xFF6EFAAD),
                              ),
                              _MetricCard(
                                title: 'Streak Days',
                                value: '${dashboard?.streakDays ?? 0}',
                                color: const Color(0xFFB2FE83),
                              ),
                              _MetricCard(
                                title: 'Mood Logs',
                                value: '${dashboard?.moodEntries ?? 0}',
                                color: const Color(0xFF4DDEE3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _SectionCard(
                            title: 'How this dashboard works',
                            body:
                                'All summaries are read from Firestore. Progress entries, mood logs, and activity completions update this space so the parent does not rely on device-local state.',
                          ),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Last refresh',
                            body: dashboard?.lastUpdated == null
                                ? 'No snapshot has been generated yet.'
                                : dashboard!.lastUpdated.toString(),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width / 2 - 32,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
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
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dashboard_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
