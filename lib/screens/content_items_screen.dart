import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/tts_service.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class ContentItemsScreen extends StatelessWidget {
  const ContentItemsScreen({super.key, required this.category});

  final ContentCategory category;

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: category.title,
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<ContentItem>>(
          future: AppRepositories.content.getItemsForCategory(category.id),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No content items were found in Firestore for this category.',
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
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return GestureDetector(
                  onTap: () async {
                    final text = item.audioText.isEmpty
                        ? item.title
                        : item.audioText;
                    await TtsService().speak(text);
                    final child = await AppRepositories.users
                        .getActiveChildForCurrentParent();
                    if (child != null) {
                      await AppRepositories.planner.recordActivityCompletion(
                        childId: child.id,
                        itemId: item.id,
                        score: item.level,
                      );
                    }
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
                          Icons.image_outlined,
                          size: 44,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2D4B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.subtitle.isEmpty
                              ? 'Tap to hear and mark complete'
                              : item.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
        ),
      ),
    );
  }
}
