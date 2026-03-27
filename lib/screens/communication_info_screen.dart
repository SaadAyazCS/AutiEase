import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';

class CommunicationInfoScreen extends StatelessWidget {
  const CommunicationInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaModuleScaffold(
      title: 'Communication Info',
      onBack: () => Navigator.pop(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
        children: const [
          _InfoCard(
            children: [
              Text(
                'This section helps children who have difficulty expressing their needs or feelings using speech. The app uses pictures and sounds to support communication.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textDark,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Children can tap images, and the app speaks for them, helping them communicate with parents and caretakers.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textDark,
                  height: 1.5,
                ),
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
                '- Helps non-verbal or minimally verbal children',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Improves understanding of words and meanings',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Builds confidence in expressing needs',
                style: TextStyle(fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                '- Supports early sentence building',
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
