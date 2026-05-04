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
                  Center(
                    child: _ChildModuleCard(
                      title: 'Communication',
                      iconAssetPath: 'assets/images/Communication.png',
                      color: const Color(0xFFD9BCC0),
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
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: _ChildModuleCard(
                      title: 'Learn',
                      iconAssetPath: 'assets/images/Learn.png',
                      color: const Color(0xFF86D44A),
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
                                DailyActivitiesScreen(childId: _child!.id),
                          ),
                        );
                      },
                    ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.clamp(240.0, 330.0).toDouble();
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: cardWidth,
            child: Material(
              color: Colors.transparent,
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
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  height: 124,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Stack(
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
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
                      if (locked)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.94,
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withValues(alpha: 0.12),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.lock_rounded,
                                        size: 28,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Locked',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
