import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/session_guard.dart';
import 'child_profile_home_screen.dart';
import 'dashboard_screen.dart';
import 'learning_planner_screen.dart';
import 'parent_home_info_flow_screen.dart';
import 'professional_support_screen.dart';
import 'settings_screen.dart';

class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  void _openInfoFlow(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ParentHomeInfoFlowScreen()),
    );
  }

  Widget _buildScreenForModule(AppModule module) {
    switch (module.routeKey) {
      case 'dashboard':
        return const DashboardScreen();
      case 'child_profile':
        return const ChildProfileHomeScreen();
      case 'professional_support':
        return const ProfessionalSupportScreen();
      case 'learning_planner':
        return const LearningPlannerScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return _UnavailableModuleScreen(module: module);
    }
  }

  String _assetForModule(AppModule module) {
    switch (module.routeKey) {
      case 'dashboard':
        return 'assets/images/Dashboard.png';
      case 'child_profile':
        return 'assets/images/Child_Profile.png';
      case 'professional_support':
        return 'assets/images/Professional_Support.png';
      case 'learning_planner':
        return 'assets/images/Learning_Planner.png';
      case 'settings':
        return 'assets/images/Settings.png';
      default:
        return 'assets/images/Dashboard.png';
    }
  }

  Color _cardColorForModule(AppModule module) {
    switch (module.routeKey) {
      case 'dashboard':
        return const Color(0xFFF2B9BD);
      case 'child_profile':
        return const Color(0xFF7DE3B5);
      case 'learning_planner':
        return const Color(0xFFC2E9D7);
      case 'professional_support':
        return const Color(0xFFAEEB7A);
      case 'settings':
        return const Color(0xFF5FD4E7);
      default:
        return const Color(0xFFCFC5E5);
    }
  }

  String _labelForModule(AppModule module) {
    switch (module.routeKey) {
      case 'learning_planner':
        return 'Learning\nPlanner';
      case 'professional_support':
        return 'Professional\nSupport';
      default:
        return module.title;
    }
  }

  List<AppModule> _orderedModules(List<AppModule> modules) {
    const desiredOrder = <String>[
      'dashboard',
      'child_profile',
      'learning_planner',
      'professional_support',
      'settings',
    ];
    final byRoute = <String, AppModule>{
      for (final module in modules) module.routeKey: module,
    };
    final ordered = <AppModule>[
      ...desiredOrder.map(byRoute.remove).whereType<AppModule>(),
      ...byRoute.values,
    ];
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF9ED7F4))),
            Positioned(
              top: 96,
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                child: const ColoredBox(color: Color(0xFFF6F6F6)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 92,
                  decoration: const BoxDecoration(
                    color: Color(0xFF77C6F0),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 160,
              child: ClipPath(
                clipper: _ParentHomeBottomClipper(),
                child: const ColoredBox(color: Color(0xFF60BEEF)),
              ),
            ),
            const Positioned(
              left: 44,
              bottom: 73,
              child: _DecorSquare(color: Color(0xFFF6E72F), size: 16),
            ),
            const Positioned(
              left: 92,
              bottom: 84,
              child: Icon(Icons.star, size: 20, color: Color(0xFFFF4081)),
            ),
            const Positioned(
              left: 165,
              bottom: 55,
              child: _DecorTriangle(color: Color(0xFFFF5B47)),
            ),
            const Positioned(
              right: 52,
              bottom: 54,
              child: _DecorCircle(color: Color(0xFF24C235), size: 15),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 0,
              right: 0,
              child: const Center(child: _ParentHomeBadge()),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 140),
                  Expanded(
                    child: StreamBuilder<List<AppModule>>(
                      stream: AppRepositories.content.watchModules('parent'),
                      builder: (context, snapshot) {
                        final modules = _orderedModules(
                          snapshot.data ?? const <AppModule>[],
                        );
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            modules.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (modules.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No parent modules are configured in Firestore.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 172),
                          itemCount: modules.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final module = modules[index];
                            return Center(
                              child: _ParentModuleCard(
                                label: _labelForModule(module),
                                assetPath: _assetForModule(module),
                                color: _cardColorForModule(module),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          _buildScreenForModule(module),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 48,
              bottom: 90,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openInfoFlow(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF101010),
                      width: 1.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: Color(0xFF101010),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentHomeBadge extends StatelessWidget {
  const _ParentHomeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 124,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFC4E5C6),
      ),
      padding: const EdgeInsets.all(8),
      child: ClipOval(
        child: Image.asset('assets/images/autiease.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _ParentModuleCard extends StatelessWidget {
  const _ParentModuleCard({
    required this.label,
    required this.assetPath,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String assetPath;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 248,
          height: 104,
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 25.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    height: 1.15,
                  ),
                ),
              ),
              Image.asset(
                assetPath,
                width: 48,
                height: 48,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParentHomeBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 48);
    path.quadraticBezierTo(size.width * 0.18, 72, size.width * 0.48, 104);
    path.quadraticBezierTo(size.width * 0.78, 138, size.width, 62);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DecorSquare extends StatelessWidget {
  const _DecorSquare({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, color: color);
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DecorTriangle extends StatelessWidget {
  const _DecorTriangle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _TrianglePainter(color),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UnavailableModuleScreen extends StatelessWidget {
  const _UnavailableModuleScreen({required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The route "${module.routeKey}" is active in Firestore but does not have a Flutter screen mapping yet.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
