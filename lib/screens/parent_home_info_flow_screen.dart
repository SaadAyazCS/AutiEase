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
        'The Dashboard is your central overview hub. It compiles your child\'s learning engagement, mood trends, and developmental analytics into interactive charts and detailed summaries.',
        'Keep a close eye on your child\'s weekly activity completion rates to stay actively involved in their progression.',
      ],
      bullets: <String>[
        'Visualize daily learning progress and achievements',
        'Review comprehensive weekly developmental logs',
        'Monitor emotional mood tracking inputs',
        'Audit completed and pending daily tasks',
      ],
    ),
    _InfoStep(
      title: 'Professional Support',
      paragraphs: <String>[
        'Directly consult and partner with certified child development therapists and behavioral specialists.',
        'Review licensed profiles, experience, and pricing packages to hire professional guidance customized to your family\'s needs.',
      ],
      bullets: <String>[
        'Browse verified clinical professional profiles',
        'Evaluate rates, specializations, and packages',
        'Initiate secure chat and exchange messaging',
        'Receive clinical guidance and action plans',
      ],
    ),
    _InfoStep(
      title: 'Learning Planner',
      paragraphs: <String>[
        'The planner serves as your control center. You select and curate the precise learning modules, communication folders, and activities accessible to your child.',
        'Configure customized speech categories, shapes, emotions, or daily routines to align with their learning path.',
      ],
      bullets: <String>[
        'Add communication flashcards and topics',
        'Enable matching, tracing, drag, and tap games',
        'Tune game difficulty and levels dynamically',
        'Schedule and structure routine daily tasks',
      ],
      closing: 'Selected modules synchronize instantly to the Child Profile environment.',
    ),
    _InfoStep(
      title: 'Child Profile',
      paragraphs: <String>[
        'A dedicated, distraction-free environment tailored exclusively for your child\'s learning and play.',
        'The portal presents only the communication flashcards, interactive games, and structured activities you enabled in the planner.',
      ],
      bullets: <String>[
        'Practice speech development and audio output',
        'Engage in interactive color, number, and animal games',
        'Complete gamified daily routine checkpoints',
        'Collect milestones as they progress',
      ],
      closing:
          'All gameplay records and analytics are sent to your dashboard in real-time.',
    ),
    _InfoStep(
      title: 'Settings',
      paragraphs: <String>[
        'Personalize account security, child profile details, and localized app configurations.',
        'Review platform terms of service, submit feedback, or modify subscription logs anytime.',
      ],
      bullets: <String>[
        'Manage secure account credentials and profiles',
        'Configure instant notification preferences',
        'Access billing, receipt, and subscription logs',
        'Provide feedback to our engineering team',
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
