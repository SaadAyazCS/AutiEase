import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_home_shell.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'therapist_chat_screen.dart';

class TherapistHomeScreen extends StatelessWidget {
  const TherapistHomeScreen({super.key});

  static const List<AppModule> _fallbackModules = [
    AppModule(
      id: 'therapist_dashboard',
      title: 'Therapist Inbox',
      subtitle: 'Open therapist conversations and support activity',
      routeKey: 'therapist_threads',
      targetRole: 'therapist',
      sortOrder: 1,
      isActive: true,
    ),
    AppModule(
      id: 'therapist_settings',
      title: 'Settings',
      subtitle: 'Profile, notifications, legal docs, and app info',
      routeKey: 'settings',
      targetRole: 'therapist',
      sortOrder: 2,
      isActive: true,
    ),
  ];

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
      case 'therapist_threads':
        return const TherapistThreadsScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return _UnavailableModuleScreen(module: module);
    }
  }

  String _assetForModule(AppModule module) {
    switch (module.routeKey) {
      case 'settings':
        return 'assets/images/Settings.png';
      case 'therapist_threads':
        return 'assets/images/Professional_Support.png';
      default:
        return 'assets/images/Professional_Support.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaHomeShell(
        title: 'Therapist Home',
        onLogout: () => _logout(context),
        avatar: const CircleAvatar(
          radius: 36,
          backgroundColor: Colors.white,
          child: Icon(
            Icons.medical_services,
            size: 34,
            color: AppColors.primaryBlue,
          ),
        ),
        child: StreamBuilder<List<AppModule>>(
          stream: AppRepositories.content.watchModules('therapist'),
          builder: (context, snapshot) {
            final modules = snapshot.data?.isNotEmpty == true
                ? snapshot.data!
                : _fallbackModules;
            if (snapshot.connectionState == ConnectionState.waiting &&
                modules.isEmpty) {
              return const Center(child: CircularProgressIndicator());
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

class TherapistThreadsScreen extends StatelessWidget {
  const TherapistThreadsScreen({super.key});

  Future<Map<String, UserProfile>> _loadParentProfiles(
    List<TherapistThread> threads,
  ) async {
    final parentIds = threads.map((thread) => thread.parentId).toSet();
    final entries = await Future.wait(
      parentIds.map((parentId) async {
        final profile = await AppRepositories.users.getUserProfile(parentId);
        return MapEntry(parentId, profile);
      }),
    );

    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaModuleScaffold(
        title: 'Therapist Inbox',
        onBack: () => Navigator.pop(context),
        child: StreamBuilder<List<TherapistThread>>(
          stream: AppRepositories.support.watchThreadsForRole('therapist'),
          builder: (context, snapshot) {
            final threads = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                threads.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (threads.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No parent conversations yet. Once a subscribed parent starts a thread, it will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return FutureBuilder<Map<String, UserProfile>>(
              future: _loadParentProfiles(threads),
              builder: (context, parentsSnapshot) {
                final parentMap = parentsSnapshot.data ?? const {};
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                  itemCount: threads.length,
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    final parentName = thread.parentDisplayName.isNotEmpty
                        ? thread.parentDisplayName
                        : (parentMap[thread.parentId]?.fullName.isNotEmpty ==
                                  true
                              ? parentMap[thread.parentId]!.fullName
                              : parentMap[thread.parentId]?.email ??
                                    'Parent ${thread.parentId.substring(0, 6)}');

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TherapistChatScreen(
                              thread: thread,
                              participantName: parentName,
                              senderRole: 'therapist',
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
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
                              parentName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A2D4B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Child ID: ${thread.childId}'),
                            const SizedBox(height: 6),
                            Text('Status: ${thread.status}'),
                            const SizedBox(height: 6),
                            Text(
                              thread.lastMessagePreview.isEmpty
                                  ? 'No messages yet'
                                  : 'Last message: ${thread.lastMessagePreview}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
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
            color: module.routeKey == 'settings'
                ? const Color(0xFFCFC5E5)
                : const Color(0xFFC5E5C8),
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
