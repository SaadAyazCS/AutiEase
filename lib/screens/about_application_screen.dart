import 'package:flutter/material.dart';

import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class AboutApplicationScreen extends StatelessWidget {
  const AboutApplicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'About Application',
        onBack: () => Navigator.pop(context),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 170),
            children: const [
              Text(
                'AutiEase is an easy-to-use support application created to help children with Autism Spectrum Disorder (ASD) improve communication, learning, and daily living skills in a friendly and interactive way.',
                style: TextStyle(
                  fontSize: 18 / 1.2,
                  height: 1.45,
                  color: Color(0xFF1F1F1F),
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Key Features',
                style: TextStyle(
                  fontSize: 34 / 1.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: 4),
              _AboutBullet('AAC Board Support'),
              _AboutBullet('Daily Routine Visual Schedules'),
              _AboutBullet('Interactive Learning Activities'),
              _AboutBullet('Caretaker & Therapist Support Tools'),
              SizedBox(height: 14),
              Text(
                'Purpose / Mission Statement',
                style: TextStyle(
                  fontSize: 34 / 1.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Our mission is to provide accessible digital support to help children with ASD learn, express themselves, and build meaningful daily skills.',
                style: TextStyle(
                  fontSize: 18 / 1.2,
                  height: 1.45,
                  color: Color(0xFF1F1F1F),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Developer / Organization',
                style: TextStyle(
                  fontSize: 34 / 1.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Developed by: AutiEase Team\nDesigned for educational and support purposes.',
                style: TextStyle(
                  fontSize: 18 / 1.2,
                  height: 1.45,
                  color: Color(0xFF1F1F1F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutBullet extends StatelessWidget {
  const _AboutBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '• $text',
        style: const TextStyle(
          fontSize: 18 / 1.2,
          color: Color(0xFF1F1F1F),
          height: 1.4,
        ),
      ),
    );
  }
}
