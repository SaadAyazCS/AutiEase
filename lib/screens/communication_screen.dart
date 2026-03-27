import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'content_items_screen.dart';

class CommunicationScreen extends StatelessWidget {
  const CommunicationScreen({super.key, this.childId});

  final String? childId;

  Future<String?> _resolveChildId() async {
    if (childId != null && childId!.isNotEmpty) {
      return childId;
    }
    return (await AppRepositories.users.getActiveChildForCurrentParent())?.id;
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Communication',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<String?>(
          future: _resolveChildId(),
          builder: (context, childSnapshot) {
            final resolvedChildId = childSnapshot.data;
            if (resolvedChildId == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No active child profile was found for this communication space.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return FutureBuilder<List<ContentCategory>>(
              future: AppRepositories.content.getAssignedCategories(
                resolvedChildId,
                type: 'communication',
              ),
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    categories.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (categories.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No communication categories are assigned in Firestore yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ContentItemsScreen(category: category),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.record_voice_over_outlined,
                              color: AppColors.primaryBlue,
                              size: 42,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              category.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A2D4B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'DB-assigned topic',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.black54,
                              ),
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
