import 'package:flutter/material.dart';

import '../config/learning_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class LearningPlannerScreen extends StatefulWidget {
  const LearningPlannerScreen({super.key});

  @override
  State<LearningPlannerScreen> createState() => _LearningPlannerScreenState();
}

class _LearningPlannerScreenState extends State<LearningPlannerScreen> {
  final Set<String> _selectedCategoryIds = <String>{};
  final Set<String> _selectedModuleIds = <String>{};
  final Set<String> _selectedActivityIds = <String>{};

  bool _isLoading = true;
  bool _isSaving = false;
  ChildProfile? _child;
  List<ContentCategory> _categories = const [];
  List<LearningModuleModel> _modules = const [];
  List<DailyActivityTemplate> _activities = const [];

  @override
  void initState() {
    super.initState();
    _loadPlannerState();
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
    ]);

    final assignment = results[3] as ChildAssignment?;
    _selectedCategoryIds
      ..clear()
      ..addAll(assignment?.assignedCategoryIds ?? const []);
    _selectedModuleIds
      ..clear()
      ..addAll(assignment?.assignedModuleIds ?? const []);
    _selectedActivityIds
      ..clear()
      ..addAll(assignment?.assignedActivityTemplateIds ?? const []);

    if (mounted) {
      setState(() {
        _child = child;
        _categories = results[0] as List<ContentCategory>;
        _modules = results[1] as List<LearningModuleModel>;
        _activities = results[2] as List<DailyActivityTemplate>;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePlan() async {
    if (_child == null) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await AppRepositories.planner.saveAssignment(
        ChildAssignment(
          id: _child!.id,
          childId: _child!.id,
          parentId: _child!.parentId,
          assignedCategoryIds: _selectedCategoryIds.toList(),
          assignedModuleIds: _selectedModuleIds.toList(),
          assignedActivityTemplateIds: _selectedActivityIds.toList(),
          status: 'active',
          effectiveFrom: DateTime.now(),
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Learning planner saved to Firestore'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Map<String, List<LearningModuleModel>> _groupLearningModules() {
    final grouped = <String, List<LearningModuleModel>>{};
    for (final module in _modules) {
      final key = module.learningCategoryKey.trim().isEmpty
          ? 'general'
          : module.learningCategoryKey.trim().toLowerCase();
      grouped.putIfAbsent(key, () => []).add(module);
    }
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedLearningModules = _groupLearningModules();
    final orderedLearningCategoryKeys = <String>[
      ...LearningCatalog.orderedCategoryKeys.where(
        groupedLearningModules.containsKey,
      ),
      ...groupedLearningModules.keys.where(
        (key) => !LearningCatalog.orderedCategoryKeys.contains(key),
      ),
    ];

    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Learning Planner',
        onBack: () => Navigator.pop(context),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _child == null
            ? const _PlannerInfoCard(
                title: 'No child profile available',
                body:
                    'The planner is DB-driven. Create a child profile first, then return to assign communication categories, learning modules, and daily activities.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                children: [
                  _PlannerInfoCard(
                    title: 'Planning for ${_child!.name}',
                    body:
                        'These selections are stored in Firestore and immediately control what appears in Child Profile.',
                  ),
                  const SizedBox(height: 20),
                  _SelectableGroup<ContentCategory>(
                    title: 'Communication Topics',
                    items: _categories,
                    isSelected: (item) =>
                        _selectedCategoryIds.contains(item.id),
                    label: (item) => item.title,
                    subtitle: (item) => item.type,
                    onChanged: (item, selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategoryIds.add(item.id);
                        } else {
                          _selectedCategoryIds.remove(item.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  if (groupedLearningModules.isEmpty)
                    const _PlannerInfoCard(
                      title: 'No learning games in DB',
                      body:
                          'Seed learning_modules in Firestore to manage Learn categories and game types.',
                    ),
                  for (final key in orderedLearningCategoryKeys) ...[
                    _LearningGameTypeGroup(
                      category: LearningCatalog.forKey(
                        key,
                        fallbackTitle: groupedLearningModules[key]!
                            .first
                            .learningCategoryTitle,
                      ),
                      modules: groupedLearningModules[key]!,
                      selectedModuleIds: _selectedModuleIds,
                      onToggleModule: (moduleId, selected) {
                        setState(() {
                          if (selected) {
                            _selectedModuleIds.add(moduleId);
                          } else {
                            _selectedModuleIds.remove(moduleId);
                          }
                        });
                      },
                      onSelectAll: (moduleIds, shouldSelectAll) {
                        setState(() {
                          if (shouldSelectAll) {
                            _selectedModuleIds.addAll(moduleIds);
                          } else {
                            _selectedModuleIds.removeAll(moduleIds);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 20),
                  _SelectableGroup<DailyActivityTemplate>(
                    title: 'Daily Activities',
                    items: _activities,
                    isSelected: (item) =>
                        _selectedActivityIds.contains(item.id),
                    label: (item) => item.title,
                    subtitle: (item) =>
                        '${item.estimatedMinutes} mins - ${item.difficulty}',
                    onChanged: (item, selected) {
                      setState(() {
                        if (selected) {
                          _selectedActivityIds.add(item.id);
                        } else {
                          _selectedActivityIds.remove(item.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save plan'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PlannerInfoCard extends StatelessWidget {
  const _PlannerInfoCard({required this.title, required this.body});

  final String title;
  final String body;

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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _LearningGameTypeGroup extends StatelessWidget {
  const _LearningGameTypeGroup({
    required this.category,
    required this.modules,
    required this.selectedModuleIds,
    required this.onToggleModule,
    required this.onSelectAll,
  });

  final LearningCategoryDefinition category;
  final List<LearningModuleModel> modules;
  final Set<String> selectedModuleIds;
  final void Function(String moduleId, bool selected) onToggleModule;
  final void Function(List<String> moduleIds, bool shouldSelectAll) onSelectAll;

  @override
  Widget build(BuildContext context) {
    final moduleIds = modules.map((module) => module.id).toList();
    final selectedCount = modules
        .where((module) => selectedModuleIds.contains(module.id))
        .length;
    final shouldSelectAll = selectedCount != modules.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2D4B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$selectedCount/${modules.length} game types selected',
                      style: const TextStyle(color: Color(0xFF2D4058)),
                    ),
                  ],
                ),
              ),
              Icon(category.icon, color: const Color(0xFF2A4A7A)),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => onSelectAll(moduleIds, shouldSelectAll),
            child: Text(shouldSelectAll ? 'Select all' : 'Clear all'),
          ),
          for (final module in modules)
            CheckboxListTile(
              value: selectedModuleIds.contains(module.id),
              onChanged: (selected) =>
                  onToggleModule(module.id, selected ?? false),
              title: Text(module.title),
              subtitle: Text(module.description),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
  }
}

class _SelectableGroup<T> extends StatelessWidget {
  const _SelectableGroup({
    required this.title,
    required this.items,
    required this.isSelected,
    required this.label,
    required this.subtitle,
    required this.onChanged,
  });

  final String title;
  final List<T> items;
  final bool Function(T item) isSelected;
  final String Function(T item) label;
  final String Function(T item) subtitle;
  final void Function(T item, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'No DB content available yet for this section.',
              style: TextStyle(color: Colors.black54),
            ),
          for (final item in items)
            CheckboxListTile(
              value: isSelected(item),
              onChanged: (selected) => onChanged(item, selected ?? false),
              title: Text(label(item)),
              subtitle: Text(subtitle(item)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
  }
}
