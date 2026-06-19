import 'package:flutter/material.dart';

import '../widgets/figma_module_scaffold.dart';

class ParentHomeInfoFlowScreen extends StatefulWidget {
  const ParentHomeInfoFlowScreen({super.key});

  @override
  State<ParentHomeInfoFlowScreen> createState() =>
      _ParentHomeInfoFlowScreenState();
}

class _ParentHomeInfoFlowScreenState extends State<ParentHomeInfoFlowScreen> {
  static const List<_InfoStep> _steps = <_InfoStep>[
    _InfoStep(
      title: 'Dashboard',
      paragraphs: <String>[
        'The Dashboard provides a complete overview of your child\'s development and daily engagement. It brings together progress tracking, activity summaries, and reports in one easy-to-understand space.',
        'This helps you stay informed and involved in your child\'s learning journey.',
      ],
      bullets: <String>[
        'Track learning progress',
        'View weekly and monthly reports',
        'Monitor activity and mood',
        'See completed tasks',
      ],
    ),
    _InfoStep(
      title: 'Professional Support',
      paragraphs: <String>[
        'Professional Support connects you with qualified therapists and specialists who can guide you through your child\'s developmental journey.',
        'You can explore professional profiles, review expertise, and reach out for advice or support when needed.',
      ],
      bullets: <String>[
        'Browse therapist profiles',
        'View specialization and pricing',
        'Send messages',
        'Receive professional advice',
      ],
    ),
    _InfoStep(
      title: 'Learning Planner',
      paragraphs: <String>[
        'Learning Planner is the parent control center of the app. Here, you decide what content your child will access in their learning space.',
        'You can customize communication topics, select learning categories, choose levels, and manage daily activities.',
      ],
      bullets: <String>[
        'Select communication topics',
        'Choose learning categories',
        'Pick levels and games',
        'Add or remove daily activities',
      ],
      closing: 'All selected items automatically appear in the Child Profile.',
    ),
    _InfoStep(
      title: 'Child Profile',
      paragraphs: <String>[
        'Child Profile is your child\'s personalized learning area. It displays only the content you selected in Learning Planner.',
        'This ensures your child focuses on activities that match their learning needs and level.',
      ],
      bullets: <String>[
        'Practice communication topics',
        'Play selected learning games',
        'Progress through chosen levels',
        'Complete assigned daily activities',
      ],
      closing:
          'Any changes made in Learning Planner update here automatically.',
    ),
    _InfoStep(
      title: 'Settings',
      paragraphs: <String>[
        'Settings allows you to manage your account and personalize your app experience.',
        'You can update your profile, control notifications, and access important app information.',
      ],
      bullets: <String>[
        'Edit profile details',
        'Manage notification preferences',
        'Provide feedback',
        'View app information',
        'Logout securely',
      ],
    ),
  ];

  int _stepIndex = 0;

  void _goBack() {
    if (_stepIndex == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _stepIndex -= 1);
  }

  void _goNext() {
    if (_stepIndex == _steps.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _stepIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];
    final isLastStep = _stepIndex == _steps.length - 1;

    return FigmaModuleScaffold(
      title: step.title,
      onBack: _goBack,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final paragraph in step.paragraphs) ...[
                      Text(
                        paragraph,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (step.bullets.isNotEmpty) ...[
                      const Text(
                        'From here, you can:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final bullet in step.bullets) ...[
                        Text(
                          '• $bullet',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      const SizedBox(height: 10),
                    ],
                    if (step.closing != null)
                      Text(
                        step.closing!,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF111827),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 112,
            height: 42,
            child: ElevatedButton(
              onPressed: _goNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4BAEE7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(isLastStep ? 'Done' : 'Next'),
            ),
          ),
          const SizedBox(height: 200),
        ],
      ),
    );
  }
}

class _InfoStep {
  const _InfoStep({
    required this.title,
    required this.paragraphs,
    required this.bullets,
    this.closing,
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final String? closing;
}
