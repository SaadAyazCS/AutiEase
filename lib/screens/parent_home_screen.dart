import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/responsive.dart';
import '../widgets/session_guard.dart';
import 'child_profile_home_screen.dart';
import 'dashboard_screen.dart';
import 'learning_planner_screen.dart';
import 'parent_home_info_flow_screen.dart';
import 'professional_support_screen.dart';
import 'settings_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

/// Persisted so the welcome coachmark appears only once per parent account.
const String parentHomeCoachmarkSeenField = 'hasSeenParentHomeInfoCoachmark';

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  bool _showCoachmark = false;
  bool _pulseInfoGlow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluateParentCoachmark());
  }

  Future<void> _evaluateParentCoachmark() async {
    if (!mounted) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      final hasSeen =
          snapshot.data()?[parentHomeCoachmarkSeenField] == true;
      if (!mounted || hasSeen) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) {
        return;
      }
      setState(() {
        _showCoachmark = true;
        _pulseInfoGlow = true;
      });
    } catch (_) {
      // Non-blocking: omit coachmark when Firestore is unavailable.
    }
  }

  Future<void> _markCoachmarkSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .set(
            {parentHomeCoachmarkSeenField: true},
            SetOptions(merge: true),
          );
    } catch (_) {
      // Best-effort; avoid blocking the UI.
    }
  }

  Future<void> _startInfoWalkthrough() async {
    if (_showCoachmark || _pulseInfoGlow) {
      await _markCoachmarkSeen();
      if (!mounted) {
        return;
      }
      setState(() {
        _showCoachmark = false;
        _pulseInfoGlow = false;
      });
    }
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ParentHomeInfoFlowScreen()),
    );
  }

  Future<void> _dismissCoachmarkWithoutWalkthrough() async {
    await _markCoachmarkSeen();
    if (!mounted) {
      return;
    }
    setState(() {
      _showCoachmark = false;
      _pulseInfoGlow = false;
    });
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
    final r = context.responsive;

    Widget coachmarkTriangle() {
      return CustomPaint(
        size: Size(r.w(26), r.h(12)),
        painter: _CoachmarkBubbleTrianglePainter(
          color: const Color(0xFF3D8BD4),
        ),
      );
    }

    Widget coachmarkBubble() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: r.w(248)),
            padding: EdgeInsets.fromLTRB(
              r.w(14),
              r.h(14),
              r.w(14),
              r.h(12),
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF56B9F5),
                  Color(0xFF3D8BD4),
                ],
              ),
              borderRadius: BorderRadius.circular(r.w(16)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3D8BD4).withValues(alpha: 0.28),
                  blurRadius: r.h(14),
                  offset: Offset(0, r.h(8)),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: r.h(8),
                  offset: Offset(0, r.h(4)),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(r.w(5)),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(r.w(8)),
                      ),
                      child: Icon(
                        Icons.waving_hand_rounded,
                        color: Colors.white,
                        size: r.sp(17, min: 14, max: 20),
                      ),
                    ),
                    SizedBox(width: r.w(8)),
                    Expanded(
                      child: Text(
                        'Welcome!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: r.sp(15.5, min: 13, max: 18),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: r.h(8)),
                Text(
                  'Tap the circular (i) icon just below Settings to explore '
                  'what each tab does. That opens a step-by-step tour of your '
                  'home—starting with Dashboard, then the other sections.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.94),
                    fontSize: r.sp(13, min: 11.5, max: 15),
                    height: 1.45,
                  ),
                ),
                SizedBox(height: r.h(10)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _dismissCoachmarkWithoutWalkthrough,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(horizontal: r.w(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Maybe later',
                      style: TextStyle(
                        fontSize: r.sp(12.5),
                        decoration: TextDecoration.underline,
                        decorationColor:
                            Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: r.w(28)),
            child: Transform.translate(
              offset: Offset(r.w(-2), 0),
              child: coachmarkTriangle(),
            ),
          ),
        ],
      );
    }

    return SessionGuard(
      role: SessionGuardRole.parent,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF9ED7F4))),
            Positioned(
              top: r.h(96),
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(r.w(14)),
                  topRight: Radius.circular(r.w(14)),
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
                  height: r.h(92),
                  decoration: BoxDecoration(
                    color: Color(0xFF77C6F0),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(r.w(18)),
                      bottomRight: Radius.circular(r.w(18)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: r.h(160),
              child: ClipPath(
                clipper: _ParentHomeBottomClipper(),
                child: const ColoredBox(color: Color(0xFF60BEEF)),
              ),
            ),
            Positioned(
              left: r.w(44),
              bottom: r.h(34),
              child: _DecorSquare(
                color: const Color(0xFFF6E72F),
                size: r.w(16),
              ),
            ),
            Positioned(
              left: r.w(100),
              bottom: r.h(54),
              child: Icon(
                Icons.star,
                size: r.sp(20, min: 16, max: 24),
                color: const Color(0xFFFF4081),
              ),
            ),
            Positioned(
              left: r.w(188),
              bottom: r.h(20),
              child: _DecorTriangle(
                color: const Color(0xFFFF5B47),
                size: r.w(18),
              ),
            ),
            Positioned(
              right: r.w(44),
              bottom: r.h(10),
              child: _DecorCircle(
                color: const Color(0xFF24C235),
                size: r.w(15),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + r.h(10),
              left: 0,
              right: 0,
              child: Center(child: _ParentHomeBadge(size: r.w(124))),
            ),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(height: r.h(140)),
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
                          return Center(
                            child: Padding(
                              padding: EdgeInsets.all(r.w(24)),
                              child: const Text(
                                'No parent modules are configured in Firestore.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: EdgeInsets.fromLTRB(0, r.h(8), 0, r.h(172)),
                          itemCount: modules.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: r.h(12)),
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
            if (_showCoachmark)
              Positioned(
                right: r.w(36),
                bottom: r.h(88) + r.w(30) + r.h(10),
                child: coachmarkBubble(),
              ),
            Positioned(
              right: r.w(48),
              bottom: r.h(90),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async => _startInfoWalkthrough(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  width: r.w(30),
                  height: r.w(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF101010),
                      width: r.w(1.8),
                    ),
                    boxShadow: [
                      if (_pulseInfoGlow) ...[
                        BoxShadow(
                          color: const Color(0xFF4EA9E3).withValues(alpha: 0.55),
                          blurRadius: r.h(16),
                          spreadRadius: r.h(1.5),
                        ),
                        BoxShadow(
                          color: const Color(0xFF56B9F5).withValues(alpha: 0.35),
                          blurRadius: r.h(24),
                          spreadRadius: 0,
                          offset: Offset(0, r.h(6)),
                        ),
                      ],
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: r.h(6),
                        offset: Offset(0, r.h(3)),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: r.sp(20, min: 14, max: 22),
                    color: const Color(0xFF101010),
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

class _CoachmarkBubbleTrianglePainter extends CustomPainter {
  const _CoachmarkBubbleTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParentHomeBadge extends StatelessWidget {
  const _ParentHomeBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFC4E5C6),
      ),
      padding: EdgeInsets.all(size * 0.065),
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
    final r = context.responsive;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - r.w(56))
        .clamp(r.w(220), r.w(280))
        .toDouble();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r.w(16)),
        child: Ink(
          width: cardWidth,
          height: r.h(104),
          padding: EdgeInsets.fromLTRB(r.w(16), r.h(14), r.w(14), r.h(14)),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(r.w(16)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: r.sp(25.5, min: 18, max: 28),
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    height: 1.15,
                  ),
                ),
              ),
              Image.asset(
                assetPath,
                width: r.w(48),
                height: r.w(48),
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
  const _DecorTriangle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
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
