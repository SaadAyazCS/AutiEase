import 'package:flutter/material.dart';

import '../utils/responsive.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'parent_terms_screen.dart';
import 'therapist_terms_screen.dart';
import 'legal_document_screen.dart';

class AboutApplicationScreen extends StatelessWidget {
  final String? audience;
  const AboutApplicationScreen({super.key, this.audience});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'About Application',
        onBack: () => Navigator.pop(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(r.w(16), r.h(16), r.w(16), r.h(160)),
          children: [
            // App Logo Section
            Center(
              child: Container(
                width: r.w(110),
                height: r.w(110),
                padding: EdgeInsets.all(r.w(14)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/autiease.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SizedBox(height: r.h(16)),
            Center(
              child: Text(
                'AutiEase',
                style: TextStyle(
                  fontSize: r.sp(28, min: 22, max: 34),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A2D4B),
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Center(
              child: Text(
                'Empowering Communication • Version 1.0.0',
                style: TextStyle(
                  fontSize: r.sp(13, min: 11, max: 15),
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(height: r.h(28)),

            // Introduction Section
            _AboutSection(
              title: 'Overview',
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF3B82F6),
              child: Text(
                'AutiEase is a dedicated support platform designed to empower children with Autism Spectrum Disorder (ASD). We focus on improving communication, fostering independent learning, and enhancing daily living skills through an interactive, friendly interface.',
                style: TextStyle(
                  fontSize: r.sp(14.5, min: 13, max: 17),
                  height: 1.5,
                  color: const Color(0xFF334155),
                ),
              ),
            ),

            SizedBox(height: r.h(20)),

            // Key Features Grid
            Text(
              'Key Capabilities',
              style: TextStyle(
                fontSize: r.sp(19, min: 16, max: 23),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            SizedBox(height: r.h(12)),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: r.w(12),
              crossAxisSpacing: r.w(12),
              childAspectRatio: 1.45,
              children: [
                _FeatureTile(
                  icon: Icons.dashboard_customize_outlined,
                  title: 'AAC Board',
                  color: const Color(0xFFF59E0B),
                ),
                _FeatureTile(
                  icon: Icons.calendar_today_outlined,
                  title: 'Visual Schedules',
                  color: const Color(0xFF10B981),
                ),
                _FeatureTile(
                  icon: Icons.games_outlined,
                  title: 'Learning Games',
                  color: const Color(0xFF8B5CF6),
                ),
                _FeatureTile(
                  icon: Icons.people_outline,
                  title: 'Therapist Hub',
                  color: const Color(0xFFEC4899),
                ),
              ],
            ),

            SizedBox(height: r.h(24)),

            // Mission Section
            _AboutSection(
              title: 'Our Mission',
              icon: Icons.auto_awesome_outlined,
              color: const Color(0xFF10B981),
              child: Text(
                'To provide a seamless digital companion that helps every child express their world and navigate their daily life with confidence and joy.',
                style: TextStyle(
                  fontSize: r.sp(14.5, min: 13, max: 17),
                  height: 1.5,
                  color: const Color(0xFF334155),
                ),
              ),
            ),

            SizedBox(height: r.h(20)),

            // Credits Section
            _AboutSection(
              title: 'Credits',
              icon: Icons.favorite_border_rounded,
              color: const Color(0xFFF43F5E),
              child: Text(
                'Developed with love by the AutiEase Team. Built for the community to make a difference in specialized education.',
                style: TextStyle(
                  fontSize: r.sp(14, min: 12, max: 16),
                  height: 1.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),

            SizedBox(height: r.h(20)),

            // Contact & Support Section
            _AboutSection(
              title: 'Contact & Support',
              icon: Icons.support_agent_rounded,
              color: const Color(0xFF0D9488),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined, color: Color(0xFF0D9488)),
                title: Text(
                  'autieasefyp@gmail.com',
                  style: TextStyle(
                    fontSize: r.sp(14),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                subtitle: Text(
                  'Reach out for any queries or help',
                  style: TextStyle(
                    fontSize: r.sp(12),
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ),

            SizedBox(height: r.h(20)),

            // Legal Section
            _AboutSection(
              title: 'Legal & Policies',
              icon: Icons.gavel_rounded,
              color: const Color(0xFF64748B),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined, color: Color(0xFF3B82F6)),
                    title: Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        fontSize: r.sp(14),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => audience == 'therapist'
                              ? const TherapistTermsScreen()
                              : const ParentTermsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF10B981)),
                    title: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: r.sp(14),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen(
                            audience: audience ?? 'parent',
                            documentId: 'privacy-policy',
                            fallbackTitle: 'Privacy Policy',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      padding: EdgeInsets.all(r.w(16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(r.w(6)),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: r.sp(18)),
              ),
              SizedBox(width: r.w(10)),
              Text(
                title,
                style: TextStyle(
                  fontSize: r.sp(17, min: 14, max: 20),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: r.h(12)),
          child,
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      padding: EdgeInsets.all(r.w(12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: r.sp(26)),
          SizedBox(height: r.h(8)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: r.sp(13.5, min: 12, max: 16),
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
