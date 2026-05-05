import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../navigation/app_route_observer.dart';
import '../repositories/app_repositories.dart';
import '../utils/parent_support_areas.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'communication_screen.dart';
import 'daily_activities_screen.dart';
import 'learning_modules_screen.dart';

class ChildProfileHomeScreen extends StatefulWidget {
  const ChildProfileHomeScreen({super.key});

  @override
  State<ChildProfileHomeScreen> createState() => _ChildProfileHomeScreenState();
}

class _ChildProfileHomeScreenState extends State<ChildProfileHomeScreen>
    with RouteAware {
  PageRoute<dynamic>? _observedRoute;
  ChildProfile? _child;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadChild();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      if (_observedRoute != route) {
        if (_observedRoute != null) {
          appRouteObserver.unsubscribe(this);
        }
        _observedRoute = route;
        appRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _reloadChild();
  }

  Future<void> _reloadChild() async {
    setState(() => _loading = true);
    final child = await AppRepositories.users.getActiveChildForCurrentParent();
    if (!mounted) {
      return;
    }
    setState(() {
      _child = child;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Child Profile',
        onBack: () => Navigator.pop(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _child == null
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
                  _ChildModuleCard(
                    title: 'Communication',
                    iconAssetPath: 'assets/images/Communication.png',
                    color: const Color(0xFFD7B6B8), // Matching Planner Red
                    locked: !childHasCommunicationSupport(_child),
                    lockedAreaLabel: 'Communication',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CommunicationScreen(childId: _child!.id),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _ChildModuleCard(
                    title: 'Learn',
                    iconAssetPath: 'assets/images/Learn.png',
                    color: const Color(0xFF86D34A), // Matching Planner Green
                    locked: !childHasLearningPlaySupport(_child),
                    lockedAreaLabel: 'Learning & Play',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LearningModulesScreen(childId: _child!.id),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _ChildModuleCard(
                    title: 'Daily Activities',
                    iconAssetPath: 'assets/images/Daily_Activities.png',
                    color: const Color(0xFFBFB5DD), // Matching Planner Purple
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DailyActivitiesScreen(childId: _child!.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
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
    this.locked = false,
    this.lockedAreaLabel = '',
  });

  final String title;
  final String iconAssetPath;
  final Color color;
  final VoidCallback onTap;
  final bool locked;
  final String lockedAreaLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 220,
        height: 140,
        margin: const EdgeInsets.only(bottom: 24),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: () {
              if (locked) {
                showLockedParentSupportAreaDialog(
                  context,
                  areaLabel: lockedAreaLabel,
                );
              } else {
                onTap();
              }
            },
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Image.asset(
                          iconAssetPath,
                          width: 54,
                          height: 54,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 28,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
