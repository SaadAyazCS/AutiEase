import 'package:flutter/material.dart';

import '../config/communication_figma_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'communication_info_screen.dart';
import 'learning_play_info_screen.dart';

class LearningPlannerScreen extends StatefulWidget {
  const LearningPlannerScreen({super.key});

  @override
  State<LearningPlannerScreen> createState() => _LearningPlannerScreenState();
}

enum _PlannerView { home, communication, learn, dailyActivities }

class _LearningPlannerScreenState extends State<LearningPlannerScreen> {
  static const _dailyTimeSlots = <String>[
    '8:00 AM',
    '10:00 AM',
    '12:30 PM',
    '2:00 PM',
    '3:30 PM',
    '5:00 PM',
  ];

  final Set<String> _selectedCategoryIds = <String>{};
  final Set<String> _selectedModuleIds = <String>{};
  final Set<String> _selectedActivityIds = <String>{};
  final Set<String> _selectedFallbackLearnOptionIds = <String>{};

  final TextEditingController _activityNameController = TextEditingController();
  final TextEditingController _activityTimeController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showAddActivityForm = false;

  _PlannerView _view = _PlannerView.home;
  ChildProfile? _child;
  List<ContentCategory> _categories = const <ContentCategory>[];
  List<LearningModuleModel> _modules = const <LearningModuleModel>[];
  List<_PlannerDailyActivity> _dailyActivities =
      const <_PlannerDailyActivity>[];
  final Set<String> _savingDailyCompletionIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPlannerState();
  }

  @override
  void dispose() {
    _activityNameController.dispose();
    _activityTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadPlannerState() async {
    setState(() => _isLoading = true);
    final child = await AppRepositories.users.getActiveChildForCurrentParent();
    if (child == null) {
      if (mounted) {
        setState(() {
          _child = null;
          _isLoading = false;
        });
      }
      return;
    }

    final results = await Future.wait([
      AppRepositories.content.getAllCategories(type: 'communication'),
      AppRepositories.content.getAllLearningModules(),
      AppRepositories.content.getAllActivityTemplates(),
      AppRepositories.planner.getAssignmentForChild(child.id),
      _loadCompletedActivityIdsForToday(child.id),
    ]);

    final categories = results[0] as List<ContentCategory>;
    final modules = results[1] as List<LearningModuleModel>;
    final activities = results[2] as List<DailyActivityTemplate>;
    final assignment = results[3] as ChildAssignment?;
    final completedTodayIds = results[4] as Set<String>;

    _selectedCategoryIds
      ..clear()
      ..addAll(assignment?.assignedCategoryIds ?? const <String>[]);
    _selectedModuleIds
      ..clear()
      ..addAll(assignment?.assignedModuleIds ?? const <String>[]);
    _selectedActivityIds
      ..clear()
      ..addAll(assignment?.assignedActivityTemplateIds ?? const <String>[]);

    final dailyActivities = _buildDailyActivities(
      activities,
      assignment: assignment,
      completedTodayIds: completedTodayIds,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _child = child;
      _categories = categories;
      _modules = modules;
      _dailyActivities = dailyActivities;
      _isLoading = false;
    });
  }

  Map<String, List<LearningModuleModel>> _groupLearningModules(
    List<LearningModuleModel> modules,
  ) {
    final grouped = <String, List<LearningModuleModel>>{};
    for (final module in modules) {
      final key = module.learningCategoryKey.trim().toLowerCase();
      final normalized = key.isEmpty ? 'general' : key;
      grouped
          .putIfAbsent(normalized, () => <LearningModuleModel>[])
          .add(module);
    }
    for (final modulesByCategory in grouped.values) {
      modulesByCategory.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return grouped;
  }

  List<_PlannerDailyActivity> _buildDailyActivities(
    List<DailyActivityTemplate> templates,
    {
    required ChildAssignment? assignment,
    required Set<String> completedTodayIds,
  }
  ) {
    final templateById = <String, DailyActivityTemplate>{
      for (final template in templates) template.id: template,
    };
    final assignedTemplateIds = assignment?.assignedActivityTemplateIds ??
        templateById.keys.toList();

    final templateActivities = <_PlannerDailyActivity>[];
    var slotIndex = 0;
    for (final templateId in assignedTemplateIds) {
      final template = templateById[templateId];
      if (template == null) {
        continue;
      }
      templateActivities.add(
        _PlannerDailyActivity(
          id: template.id,
          title: template.title,
          timeLabel: _dailyTimeSlots[slotIndex % _dailyTimeSlots.length],
          isTemplate: true,
          isCompleted: completedTodayIds.contains(template.id),
        ),
      );
      slotIndex += 1;
    }

    final customActivities = (assignment?.customDailyActivities ??
            const <CustomDailyActivity>[])
        .map(
          (activity) => _PlannerDailyActivity(
            id: activity.id,
            title: activity.title,
            timeLabel: activity.timeLabel,
            isTemplate: false,
            isCompleted: completedTodayIds.contains(activity.id),
          ),
        )
        .toList();

    return <_PlannerDailyActivity>[
      ...customActivities,
      ...templateActivities,
    ];
  }

  Future<Set<String>> _loadCompletedActivityIdsForToday(String childId) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final snapshot = await AppRepositories.firestore
        .collection(FirestoreCollections.activityProgress)
        .where('childId', isEqualTo: childId)
        .get();
    return snapshot.docs
        .where((doc) {
          final completedAt = dateTimeFromFirestore(doc.data()['completedAt']);
          return completedAt != null && !completedAt.isBefore(todayStart);
        })
        .map((doc) => (doc.data()['itemId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> _savePlan({bool showFeedback = true}) async {
    if (_child == null || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final selectedTemplateIds = _dailyActivities
          .where((activity) => activity.isTemplate)
          .map((activity) => activity.id)
          .toList();
      final customActivities = _dailyActivities
          .where((activity) => !activity.isTemplate)
          .map(
            (activity) => CustomDailyActivity(
              id: activity.id,
              title: activity.title,
              timeLabel: activity.timeLabel,
              createdAt: DateTime.now(),
            ),
          )
          .toList();
      _selectedActivityIds
        ..clear()
        ..addAll(selectedTemplateIds);

      await AppRepositories.planner.saveAssignment(
        ChildAssignment(
          id: _child!.id,
          childId: _child!.id,
          parentId: _child!.parentId,
          assignedCategoryIds: _selectedCategoryIds.toList(),
          assignedModuleIds: _selectedModuleIds.toList(),
          assignedActivityTemplateIds: _selectedActivityIds.toList(),
          customDailyActivities: customActivities,
          status: 'active',
          effectiveFrom: DateTime.now(),
        ),
      );
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Learning planner saved')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _doneAndReturnHome() async {
    await _savePlan(showFeedback: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _showAddActivityForm = false;
      _view = _PlannerView.home;
    });
  }

  void _toggleCommunicationSelection(String categoryId, bool selected) {
    setState(() {
      if (selected) {
        _selectedCategoryIds.add(categoryId);
      } else {
        _selectedCategoryIds.remove(categoryId);
      }
    });
  }

  bool _isLearnOptionSelected(_LearnOption option) {
    return option.isModuleBacked
        ? _selectedModuleIds.contains(option.id)
        : _selectedFallbackLearnOptionIds.contains(option.id);
  }

  bool _isLearnCategoryChecked(List<_LearnOption> options) {
    return options.isNotEmpty && options.any(_isLearnOptionSelected);
  }

  void _toggleLearnCategory(List<_LearnOption> options, bool selected) {
    setState(() {
      for (final option in options) {
        if (option.isModuleBacked) {
          if (selected) {
            _selectedModuleIds.add(option.id);
          } else {
            _selectedModuleIds.remove(option.id);
          }
        } else {
          if (selected) {
            _selectedFallbackLearnOptionIds.add(option.id);
          } else {
            _selectedFallbackLearnOptionIds.remove(option.id);
          }
        }
      }
    });
  }

  void _toggleLearnOption(_LearnOption option, bool selected) {
    setState(() {
      if (option.isModuleBacked) {
        if (selected) {
          _selectedModuleIds.add(option.id);
        } else {
          _selectedModuleIds.remove(option.id);
        }
      } else {
        if (selected) {
          _selectedFallbackLearnOptionIds.add(option.id);
        } else {
          _selectedFallbackLearnOptionIds.remove(option.id);
        }
      }
    });
  }

  void _toggleDailyActivityCompletion(String activityId, bool selected) {
    if (_child == null) {
      return;
    }
    final index = _dailyActivities.indexWhere((item) => item.id == activityId);
    if (index == -1) {
      return;
    }
    final current = _dailyActivities[index];
    if (current.isCompleted || !selected || _savingDailyCompletionIds.contains(activityId)) {
      return;
    }
    setState(() {
      _dailyActivities[index] = _dailyActivities[index].copyWith(
        isCompleted: true,
      );
      _savingDailyCompletionIds.add(activityId);
    });
    AppRepositories.planner
        .recordActivityCompletion(
          childId: _child!.id,
          itemId: current.id,
          moduleId: current.id,
          score: 1,
        )
        .whenComplete(() {
          if (!mounted) {
            return;
          }
          setState(() {
            _savingDailyCompletionIds.remove(activityId);
          });
          _showCompletionDialogIfNeeded();
        });
  }

  void _removeDailyActivity(String activityId) {
    setState(() {
      _dailyActivities = _dailyActivities
          .where((activity) => activity.id != activityId)
          .toList();
      _selectedActivityIds.remove(activityId);
    });
    _savePlan(showFeedback: false);
  }

  void _addDailyActivity() {
    final name = _activityNameController.text.trim();
    final time = _activityTimeController.text.trim();
    if (name.isEmpty || time.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter activity name and time')),
      );
      return;
    }

    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _dailyActivities = <_PlannerDailyActivity>[
        _PlannerDailyActivity(
          id: id,
          title: name,
          timeLabel: time,
          isTemplate: false,
          isCompleted: false,
        ),
        ..._dailyActivities,
      ];
      _showAddActivityForm = false;
      _activityNameController.clear();
      _activityTimeController.clear();
    });
    _savePlan(showFeedback: false);
  }

  Future<void> _showCompletionDialogIfNeeded() async {
    final total = _dailyActivities.length;
    final done = _dailyActivities.where((item) => item.isCompleted).length;
    if (total == 0 || done != total || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF0DBB50),
                  size: 76,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Congratulations!',
                  style: TextStyle(
                    fontSize: 30 / 1.4,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2C45),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your child completed all daily activities!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF556174)),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '100%',
                        style: TextStyle(
                          fontSize: 36 / 1.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0DBB50),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Completion Rate',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF546174),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _showAddActivityForm = true;
                      });
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Add More Activities'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0DBB50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2F3E56),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String get _title {
    return switch (_view) {
      _PlannerView.home => 'Learning Planner',
      _PlannerView.communication => 'Communication',
      _PlannerView.learn => 'LEARN',
      _PlannerView.dailyActivities => 'Daily Activity',
    };
  }

  VoidCallback get _onBack {
    return () {
      if (_view == _PlannerView.home) {
        Navigator.pop(context);
      } else {
        setState(() {
          _showAddActivityForm = false;
          _view = _PlannerView.home;
        });
      }
    };
  }

  Widget? get _trailing {
    switch (_view) {
      case _PlannerView.communication:
        return IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CommunicationInfoScreen(),
              ),
            );
          },
          icon: const Icon(Icons.info_outline, color: Color(0xFF0F1E38)),
        );
      case _PlannerView.learn:
        return IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LearningPlayInfoScreen()),
            );
          },
          icon: const Icon(Icons.info_outline, color: Color(0xFF0F1E38)),
        );
      case _PlannerView.dailyActivities:
        return IconButton(
          onPressed: () {
            setState(() {
              _showAddActivityForm = !_showAddActivityForm;
            });
          },
          icon: const Icon(
            Icons.add_circle,
            color: Color(0xFF059DCC),
            size: 28,
          ),
        );
      case _PlannerView.home:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: _title,
        onBack: _onBack,
        trailing: _trailing,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _child == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No child profile available for Learning Planner.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : switch (_view) {
                _PlannerView.home => _buildPlannerHome(),
                _PlannerView.communication => _buildCommunicationView(),
                _PlannerView.learn => _buildLearnView(),
                _PlannerView.dailyActivities => _buildDailyActivitiesView(),
              },
      ),
    );
  }

  Widget _buildPlannerHome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 170),
      children: [
        const SizedBox(height: 14),
        Center(
          child: _PlannerHomeCard(
            title: 'Communication',
            imagePath: 'assets/images/Communication.png',
            color: const Color(0xFFD7B6B8),
            onTap: () => setState(() => _view = _PlannerView.communication),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _PlannerHomeCard(
            title: 'Learn',
            imagePath: 'assets/images/Learn.png',
            color: const Color(0xFF86D34A),
            onTap: () => setState(() => _view = _PlannerView.learn),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _PlannerHomeCard(
            title: 'Daily Activities',
            imagePath: 'assets/images/Daily_Activities.png',
            color: const Color(0xFFBFB5DD),
            onTap: () => setState(() => _view = _PlannerView.dailyActivities),
          ),
        ),
      ],
    );
  }

  List<_PlannerCommunicationItem> _communicationPlannerItems() {
    if (_categories.isEmpty) {
      return CommunicationFigmaCatalog.homeBoardOrder
          .map(CommunicationFigmaCatalog.boardForId)
          .whereType<CommunicationBoardDefinition>()
          .map(
            (board) => _PlannerCommunicationItem(
              id: board.id,
              title: board.title,
              visual: board.homeEmoji,
            ),
          )
          .toList();
    }

    final boardByNormalizedTitle = <String, CommunicationBoardDefinition>{
      for (final board in CommunicationFigmaCatalog.boards)
        board.title.toLowerCase(): board,
    };
    final categoriesById = <String, ContentCategory>{
      for (final category in _categories) category.id: category,
    };
    final consumedIds = <String>{};
    final ordered = <_PlannerCommunicationItem>[];

    for (final boardId in CommunicationFigmaCatalog.homeBoardOrder) {
      final board = CommunicationFigmaCatalog.boardForId(boardId);
      if (board == null) {
        continue;
      }
      ContentCategory? category = categoriesById[board.id];
      category ??= _categories.firstWhere(
        (item) => item.title.toLowerCase() == board.title.toLowerCase(),
        orElse: () => const ContentCategory(
          id: '',
          type: '',
          title: '',
          icon: '',
          imageUrl: '',
          sortOrder: 0,
          isActive: false,
        ),
      );

      if (category.id.isNotEmpty) {
        consumedIds.add(category.id);
        ordered.add(
          _PlannerCommunicationItem(
            id: category.id,
            title: category.title,
            visual: board.homeEmoji,
          ),
        );
      } else {
        ordered.add(
          _PlannerCommunicationItem(
            id: board.id,
            title: board.title,
            visual: board.homeEmoji,
          ),
        );
      }
    }

    for (final category in _categories) {
      if (consumedIds.contains(category.id)) {
        continue;
      }
      final board = boardByNormalizedTitle[category.title.toLowerCase()];
      ordered.add(
        _PlannerCommunicationItem(
          id: category.id,
          title: category.title,
          visual: board?.homeEmoji ?? '\u{1F5E3}',
        ),
      );
    }

    final seenIds = ordered.map((item) => item.id).toSet();
    for (final board in CommunicationFigmaCatalog.boards) {
      if (seenIds.contains(board.id)) {
        continue;
      }
      ordered.add(
        _PlannerCommunicationItem(
          id: board.id,
          title: board.title,
          visual: board.homeEmoji,
        ),
      );
      seenIds.add(board.id);
    }
    return ordered;
  }

  Widget _buildCommunicationView() {
    final items = _communicationPlannerItems();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 170),
      itemCount: items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _PlannerDoneButton(
                isBusy: _isSaving,
                onTap: _doneAndReturnHome,
              ),
            ),
          );
        }
        final item = items[index];
        final selected = _selectedCategoryIds.contains(item.id);
        return Row(
          children: [
            Expanded(
              child: Container(
                height: 108,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFC9DDF3),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(1, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item.visual, style: const TextStyle(fontSize: 34)),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2438),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            _SquareCheckBox(
              value: selected,
              onChanged: (value) =>
                  _toggleCommunicationSelection(item.id, value),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLearnView() {
    final groupedModules = _groupLearningModules(_modules);
    final movePlayOptions = _learnOptionsFor(
      categoryKey: 'move_play',
      modules: groupedModules['move_play'] ?? const <LearningModuleModel>[],
      fallbackLabels: const ['Tap Game', 'Drag Game', 'Trace Game'],
    );
    final speakLearnOptions = _learnOptionsFor(
      categoryKey: 'speak_learn',
      modules: groupedModules['speak_learn'] ?? const <LearningModuleModel>[],
      fallbackLabels: const ['Alphabets', 'Sentences', 'Words'],
    );
    final focusGameOptions = _learnOptionsFor(
      categoryKey: 'focus_games',
      modules: groupedModules['focus_games'] ?? const <LearningModuleModel>[],
      fallbackLabels: const ['Find it', 'Hold it', 'Match it'],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 170),
      children: [
        _LearnPlannerCard(
          title: 'Move &\nPlay',
          symbol: Icons.touch_app_outlined,
          color: const Color(0xFFF8B8BF),
          checked: _isLearnCategoryChecked(movePlayOptions),
          selectionLabel: 'Select games:',
          options: movePlayOptions,
          isOptionSelected: _isLearnOptionSelected,
          onCheckChanged: (value) =>
              _toggleLearnCategory(movePlayOptions, value),
          onOptionChanged: _toggleLearnOption,
        ),
        const SizedBox(height: 14),
        _LearnPlannerCard(
          title: 'Speak &\nLearn',
          symbol: Icons.record_voice_over_outlined,
          color: const Color(0xFFB7F393),
          checked: _isLearnCategoryChecked(speakLearnOptions),
          selectionLabel: 'Select levels:',
          options: speakLearnOptions,
          isOptionSelected: _isLearnOptionSelected,
          onCheckChanged: (value) =>
              _toggleLearnCategory(speakLearnOptions, value),
          onOptionChanged: _toggleLearnOption,
        ),
        const SizedBox(height: 14),
        _LearnPlannerCard(
          title: 'Focus\nGames',
          symbol: Icons.filter_center_focus,
          color: const Color(0xFFC6EADB),
          checked: _isLearnCategoryChecked(focusGameOptions),
          selectionLabel: 'Select games:',
          options: focusGameOptions,
          isOptionSelected: _isLearnOptionSelected,
          onCheckChanged: (value) =>
              _toggleLearnCategory(focusGameOptions, value),
          onOptionChanged: _toggleLearnOption,
        ),
        const SizedBox(height: 16),
        Center(
          child: _PlannerDoneButton(
            isBusy: _isSaving,
            onTap: _doneAndReturnHome,
          ),
        ),
      ],
    );
  }

  List<_LearnOption> _learnOptionsFor({
    required String categoryKey,
    required List<LearningModuleModel> modules,
    required List<String> fallbackLabels,
  }) {
    if (modules.isEmpty) {
      return fallbackLabels
          .map(
            (label) => _LearnOption(
              id: '$categoryKey-${label.toLowerCase().replaceAll(' ', '-')}',
              label: label,
              isModuleBacked: false,
            ),
          )
          .toList();
    }

    final options = <_LearnOption>[];
    final seenLabels = <String>{};
    for (final module in modules) {
      final cleaned = module.title.trim();
      final byType = module.gameTypeKey
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .trim();
      final titleCase = _toTitleCase(byType);
      final label = cleaned.isNotEmpty ? cleaned : titleCase;
      final normalizedLabel = label.toLowerCase();
      if (label.isNotEmpty && seenLabels.add(normalizedLabel)) {
        options.add(
          _LearnOption(id: module.id, label: label, isModuleBacked: true),
        );
      }
    }

    if (options.isEmpty) {
      return fallbackLabels
          .map(
            (label) => _LearnOption(
              id: '$categoryKey-${label.toLowerCase().replaceAll(' ', '-')}',
              label: label,
              isModuleBacked: false,
            ),
          )
          .toList();
    }

    if (categoryKey == 'speak_learn') {
      options.sort((a, b) {
        final indexA = _speakLearnSortOrder(a.label);
        final indexB = _speakLearnSortOrder(b.label);
        return indexA.compareTo(indexB);
      });
    } else if (categoryKey == 'focus_games') {
      options.sort((a, b) {
        final indexA = _focusSortOrder(a.label);
        final indexB = _focusSortOrder(b.label);
        return indexA.compareTo(indexB);
      });
    } else if (categoryKey == 'move_play') {
      options.sort((a, b) {
        final indexA = _movePlaySortOrder(a.label);
        final indexB = _movePlaySortOrder(b.label);
        return indexA.compareTo(indexB);
      });
    }
    return options;
  }

  int _movePlaySortOrder(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('tap')) {
      return 0;
    }
    if (lower.contains('drag')) {
      return 1;
    }
    if (lower.contains('trace') || lower.contains('tracing')) {
      return 2;
    }
    return 3;
  }

  int _speakLearnSortOrder(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('alphabet')) {
      return 0;
    }
    if (lower.contains('sentence')) {
      return 1;
    }
    if (lower.contains('word')) {
      return 2;
    }
    return 3;
  }

  int _focusSortOrder(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('find')) {
      return 0;
    }
    if (lower.contains('hold')) {
      return 1;
    }
    if (lower.contains('match')) {
      return 2;
    }
    return 3;
  }

  String _toTitleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1).toLowerCase() : ''}',
        )
        .join(' ');
  }

  Widget _buildDailyActivitiesView() {
    final completed = _dailyActivities.where((item) => item.isCompleted).length;
    final total = _dailyActivities.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
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
                      fontSize: 30 / 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF27384E),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$completed/$total',
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
        if (_showAddActivityForm) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Activity',
                  style: TextStyle(
                    fontSize: 31 / 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B3A50),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _activityNameController,
                  decoration: InputDecoration(
                    hintText: 'Activity name',
                    filled: true,
                    fillColor: const Color(0xFFF1F2F6),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _activityTimeController,
                  decoration: InputDecoration(
                    hintText: 'Time (e.g., 3:00 PM)',
                    filled: true,
                    fillColor: const Color(0xFFF1F2F6),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _addDailyActivity,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0DBBDB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Add Activity'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showAddActivityForm = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF505D70),
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        for (final activity in _dailyActivities) ...[
          _DailyActivityTile(
            activity: activity,
            isSaving: _savingDailyCompletionIds.contains(activity.id),
            onToggle: (value) =>
                _toggleDailyActivityCompletion(activity.id, value),
            onDelete: () => _removeDailyActivity(activity.id),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Center(
          child: _PlannerDoneButton(
            isBusy: _isSaving,
            onTap: _doneAndReturnHome,
          ),
        ),
      ],
    );
  }
}

class _PlannerHomeCard extends StatelessWidget {
  const _PlannerHomeCard({
    required this.title,
    required this.imagePath,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String imagePath;
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF121D32),
                ),
              ),
              const SizedBox(height: 8),
              Image.asset(
                imagePath,
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

class _PlannerDoneButton extends StatelessWidget {
  const _PlannerDoneButton({required this.isBusy, required this.onTap});

  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 122,
      child: ElevatedButton(
        onPressed: isBusy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF48B8F2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Done'),
      ),
    );
  }
}

class _SquareCheckBox extends StatelessWidget {
  const _SquareCheckBox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: value ? Colors.black : const Color(0xFF8F8F8F),
            width: 1.4,
          ),
          color: value ? Colors.black : Colors.white,
        ),
        child: value
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

class _LearnPlannerCard extends StatelessWidget {
  const _LearnPlannerCard({
    required this.title,
    required this.symbol,
    required this.color,
    required this.checked,
    required this.selectionLabel,
    required this.options,
    required this.isOptionSelected,
    required this.onCheckChanged,
    required this.onOptionChanged,
  });

  final String title;
  final IconData symbol;
  final Color color;
  final bool checked;
  final String selectionLabel;
  final List<_LearnOption> options;
  final bool Function(_LearnOption option) isOptionSelected;
  final ValueChanged<bool> onCheckChanged;
  final void Function(_LearnOption option, bool selected) onOptionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101722),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(symbol, size: 28, color: const Color(0xFF25508C)),
                  ],
                ),
              ),
              _SquareCheckBox(value: checked, onChanged: onCheckChanged),
            ],
          ),
          if (checked) ...[
            const SizedBox(height: 8),
            Text(
              selectionLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF263349),
              ),
            ),
            const SizedBox(height: 6),
            for (final option in options)
              InkWell(
                onTap: () => onOptionChanged(option, !isOptionSelected(option)),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4, top: 1),
                  child: Row(
                    children: [
                      Icon(
                        isOptionSelected(option)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 13,
                        color: Colors.black,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option.label,
                        style: const TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E2A3D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LearnOption {
  const _LearnOption({
    required this.id,
    required this.label,
    required this.isModuleBacked,
  });

  final String id;
  final String label;
  final bool isModuleBacked;
}

class _DailyActivityTile extends StatelessWidget {
  const _DailyActivityTile({
    required this.activity,
    required this.isSaving,
    required this.onToggle,
    required this.onDelete,
  });

  final _PlannerDailyActivity activity;
  final bool isSaving;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: activity.isCompleted ? null : () => onToggle(true),
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    activity.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: activity.isCompleted
                        ? const Color(0xFF0DBBDB)
                        : const Color(0xFFBCC2CD),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: TextStyle(
                    fontSize: 29 / 1.5,
                    color: const Color(0xFF233247),
                    decoration: activity.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.timeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A8495),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              color: Color(0xFFFF5A5A),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannerCommunicationItem {
  const _PlannerCommunicationItem({
    required this.id,
    required this.title,
    required this.visual,
  });

  final String id;
  final String title;
  final String visual;
}

class _PlannerDailyActivity {
  const _PlannerDailyActivity({
    required this.id,
    required this.title,
    required this.timeLabel,
    required this.isTemplate,
    this.isCompleted = false,
  });

  final String id;
  final String title;
  final String timeLabel;
  final bool isTemplate;
  final bool isCompleted;

  _PlannerDailyActivity copyWith({
    String? id,
    String? title,
    String? timeLabel,
    bool? isTemplate,
    bool? isCompleted,
  }) {
    return _PlannerDailyActivity(
      id: id ?? this.id,
      title: title ?? this.title,
      timeLabel: timeLabel ?? this.timeLabel,
      isTemplate: isTemplate ?? this.isTemplate,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
