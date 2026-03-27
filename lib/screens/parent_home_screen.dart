import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_home_shell.dart';
import '../widgets/session_guard.dart';
import 'child_profile_home_screen.dart';
import 'dashboard_screen.dart';
import 'learning_planner_screen.dart';
import 'login_screen.dart';
import 'professional_support_screen.dart';
import 'settings_screen.dart';

class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseService().logout();
    if (!context.mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
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

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaHomeShell(
        title: 'Parent Home',
        onLogout: () => _logout(context),
        avatar: const CircleAvatar(
          radius: 36,
          backgroundColor: Colors.white,
          child: Icon(
            Icons.family_restroom,
            size: 34,
            color: AppColors.primaryBlue,
          ),
        ),
        child: StreamBuilder<List<AppModule>>(
          stream: AppRepositories.content.watchModules('parent'),
          builder: (context, snapshot) {
            final modules = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                modules.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (modules.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No parent modules are configured in Firestore. Seed the app_modules collection to render the home shell.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 170),
              itemCount: modules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final module = modules[index];
                return _ModuleCard(
                  module: module,
                  assetPath: _assetForModule(module),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _buildScreenForModule(module),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.assetPath,
    required this.onTap,
  });

  final AppModule module;
  final String assetPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: module.routeKey == 'professional_support'
                ? const Color(0xFFC5E5C8)
                : const Color(0xFFCFC5E5),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(10),
                child: Image.asset(assetPath, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF223651),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      module.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2D3A55),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
      ),
    );
  }
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
