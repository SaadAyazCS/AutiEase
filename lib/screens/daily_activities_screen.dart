import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/duration_utils.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'learning_planner_screen.dart';

class DailyActivitiesScreen extends StatefulWidget {
  const DailyActivitiesScreen({super.key, required this.childId});

  final String childId;

  @override
  State<DailyActivitiesScreen> createState() => _DailyActivitiesScreenState();
}

class _DailyActivitiesScreenState extends State<DailyActivitiesScreen> {
  List<_AssignedActivity> _activities = const <_AssignedActivity>[];
  Set<String> _completedIds = const <String>{};
  final Set<String> _savingIds = <String>{};
  bool _loading = true;
  bool _allDoneDialogShown = false;

  @override
  void initState() {
    super.initState();
    _loadAssignedActivities();
  }

  Future<void> _loadAssignedActivities() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AppRepositories.content.getAssignedActivities(widget.childId),
      AppRepositories.planner.getAssignmentForChild(widget.childId),
    ]);
    final templates = results[0] as List<DailyActivityTemplate>;
    final assignment = results[1] as ChildAssignment?;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final progressSnapshot = await AppRepositories.firestore
        .collection(FirestoreCollections.activityProgress)
        .where('childId', isEqualTo: widget.childId)
        .get();
    final latestByItem = <String, Map<String, dynamic>>{};
    for (final doc in progressSnapshot.docs) {
      final data = doc.data();
      final itemId = (data['itemId'] ?? '').toString().trim();
      if (itemId.isEmpty) {
        continue;
      }
      final completedAt = dateTimeFromFirestore(data['completedAt']);
      if (completedAt == null || completedAt.isBefore(todayStart)) {
        continue;
      }
      final existing = latestByItem[itemId];
      final existingAt = existing == null
          ? null
          : dateTimeFromFirestore(existing['completedAt']);
      if (existingAt == null || completedAt.isAfter(existingAt)) {
        latestByItem[itemId] = data;
      }
    }

    final completedToday = latestByItem.entries
        .where(
          (entry) =>
              (entry.value['status'] ?? 'completed').toString().toLowerCase() ==
              'completed',
        )
        .map((entry) => entry.key)
        .toSet();

    if (!mounted) {
      return;
    }

    final templateActivities = templates
        .map(
          (template) => _AssignedActivity(
            id: template.id,
            title: template.title,
            estimatedMinutes: template.estimatedMinutes > 0
                ? template.estimatedMinutes
                : 10,
          ),
        )
        .toList();
    final customActivities =
        (assignment?.customDailyActivities ?? const <CustomDailyActivity>[])
            .map(
              (activity) => _AssignedActivity(
                id: activity.id,
                title: activity.title,
                estimatedMinutes: normalizeDurationMinutes(
                  activity.durationMinutes,
                ),
              ),
            )
            .toList();

    final assignedActivities = <_AssignedActivity>[
      ...customActivities,
      ...templateActivities,
    ];

    setState(() {
      _activities = assignedActivities;
      _completedIds = completedToday;
      _loading = false;
      _allDoneDialogShown =
          assignedActivities.isNotEmpty &&
          assignedActivities.every(
            (activity) => completedToday.contains(activity.id),
          );
    });
  }

  Future<void> _toggle(_AssignedActivity activity) async {
    final nowCompleted = !_completedIds.contains(activity.id);
    if (!nowCompleted || _savingIds.contains(activity.id)) {
      return;
    }
    final wasAllComplete = _allActivitiesComplete();

    setState(() {
      _completedIds = {..._completedIds, activity.id};
      _savingIds.add(activity.id);
    });
    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: widget.childId,
        itemId: activity.id,
        moduleId: activity.id,
        score: 1,
      );
      if (!wasAllComplete &&
          _allActivitiesComplete() &&
          _savingIds.length == 1 &&
          !_allDoneDialogShown &&
          mounted) {
        _allDoneDialogShown = true;
        await _showAllDoneDialog();
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingIds.remove(activity.id);
        });
      }
    }
  }

  bool _allActivitiesComplete() {
    return _activities.isNotEmpty &&
        _activities.every((activity) => _completedIds.contains(activity.id));
  }

  Future<void> _showAllDoneDialog() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final scale = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: scale,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 40, bottom: 30),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF6D365), Color(0xFFFDA085)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'YOU DID IT!',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                    child: Column(
                      children: [
                        const Text(
                          'All daily activities are complete!\nYou worked hard and stayed focused.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.4,
                            color: Color(0xFF4A5568),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Be very proud of yourself today!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF718096),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0DBBDB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                              elevation: 2,
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'AWESOME!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.celebration_rounded, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Daily Activity',
        onBack: () => Navigator.pop(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _activities.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No daily activities are selected in Learning Planner yet.',
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
              )
            : _buildActivitiesList(),
      ),
    );
  }

  Widget _buildActivitiesList() {
    final completedCount = _activities
        .where((activity) => _completedIds.contains(activity.id))
        .length;
    final progress = _activities.isEmpty
        ? 0.0
        : completedCount / _activities.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 170),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Today\'s Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF27384E),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$completedCount/${_activities.length}',
                    style: const TextStyle(
                      color: Color(0xFF13A9DD),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: progress,
                  color: const Color(0xFF0DBBDB),
                  backgroundColor: const Color(0xFFE2E4E9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final activity in _activities) ...[
          _ActivityTile(
            activity: activity,
            completed: _completedIds.contains(activity.id),
            isSaving: _savingIds.contains(activity.id),
            onToggle: () => _toggle(activity),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.activity,
    required this.completed,
    required this.isSaving,
    required this.onToggle,
  });

  final _AssignedActivity activity;
  final bool completed;
  final bool isSaving;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: completed
                            ? const Color(0xFF7C8A9B)
                            : const Color(0xFF23334A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDurationLabel(activity.estimatedMinutes),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6A7B8F),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSaving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  completed
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: completed
                      ? const Color(0xFF18A74E)
                      : const Color(0xFF98A6B8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignedActivity {
  const _AssignedActivity({
    required this.id,
    required this.title,
    required this.estimatedMinutes,
  });

  final String id;
  final String title;
  final int estimatedMinutes;
}
