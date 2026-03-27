import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';

class LearningPlayInfoScreen extends StatelessWidget {
  const LearningPlayInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaModuleScaffold(
      title: 'Learning & Play Info',
      onBack: () => Navigator.pop(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
        children: const [
          _InfoCard(
            children: [
              Text(
                'This section includes fun learning activities and games designed to support children with different developmental needs.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textDark,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Activities are tailored for attention, speech, and motor skill development.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textDark,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Supports children with:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '- ADHD',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Speech Delay',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Motor Skill Difficulties',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              SizedBox(height: 20),
              Text(
                'Key benefits:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '- Improves focus and attention',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Develops speech and language skills',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Enhances hand-eye coordination',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Encourages learning through play',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: children,
      ),
    );
  }
}
