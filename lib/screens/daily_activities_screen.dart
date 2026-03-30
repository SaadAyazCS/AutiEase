import 'package:flutter/material.dart';

import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class DailyActivitiesScreen extends StatefulWidget {
  const DailyActivitiesScreen({super.key, required this.childId});

  final String childId;

  @override
  State<DailyActivitiesScreen> createState() => _DailyActivitiesScreenState();
}

class _DailyActivitiesScreenState extends State<DailyActivitiesScreen> {
  static const List<_RoutineItem> _routine = <_RoutineItem>[
    _RoutineItem(id: 'routine-brush', label: 'Brush', emoji: '🪥'),
    _RoutineItem(id: 'routine-breakfast', label: 'Breakfast', emoji: '🥣'),
    _RoutineItem(id: 'routine-sleep', label: 'Sleep', emoji: '🛏️'),
    _RoutineItem(id: 'routine-school', label: 'School', emoji: '🏫'),
    _RoutineItem(id: 'routine-playtime', label: 'Play Time', emoji: '🎮'),
    _RoutineItem(id: 'routine-reading', label: 'Reading', emoji: '📚'),
  ];

  final Set<String> _completedIds = <String>{'routine-brush'};

  Future<void> _toggle(_RoutineItem item) async {
    final nowCompleted = !_completedIds.contains(item.id);
    setState(() {
      if (nowCompleted) {
        _completedIds.add(item.id);
      } else {
        _completedIds.remove(item.id);
      }
    });

    if (nowCompleted) {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: item.id,
        moduleId: 'daily-routine',
        score: 1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Daily Routine',
        onBack: () => Navigator.pop(context),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 170),
            itemCount: _routine.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = _routine[index];
              final completed = _completedIds.contains(item.id);
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _toggle(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 2,
                  ),
                  child: Text(
                    '${item.emoji} ${item.label}${completed ? ' ✓' : ''}',
                    style: TextStyle(
                      fontSize: 34 / 1.4,
                      fontWeight: FontWeight.w700,
                      color: completed
                          ? const Color(0xFFBFC3C8)
                          : const Color(0xFF27436D),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RoutineItem {
  const _RoutineItem({
    required this.id,
    required this.label,
    required this.emoji,
  });

  final String id;
  final String label;
  final String emoji;
}
