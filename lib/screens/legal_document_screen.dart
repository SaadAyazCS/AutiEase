import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.audience,
    required this.documentId,
    required this.fallbackTitle,
  });

  final String audience;
  final String documentId;
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Terms & Conditions',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<LegalDocument?>(
          future: AppRepositories.content.getLegalDocument(
            audience,
            documentId,
          ),
          builder: (context, snapshot) {
            final doc = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting &&
                doc == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final title = (doc?.title ?? fallbackTitle).trim().isEmpty
                ? 'Terms & Conditions'
                : (doc?.title ?? fallbackTitle).trim();
            final body = (doc?.body ?? _defaultTermsBody).trim().isEmpty
                ? _defaultTermsBody
                : (doc?.body ?? _defaultTermsBody);

            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              children: [
                Container(
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
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16243F),
                        ),
                      ),
                      if (doc != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Version ${doc.version}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF526482),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Color(0xFF1B2A45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const String _defaultTermsBody =
      '1. Acceptance of Terms\n'
      'By using the AutiEase app, you agree to these terms. If you disagree, stop using the app.\n\n'
      '2. User Responsibilities\n'
      'You must use the app only for lawful and safe purposes. Misuse of features, data, or services is prohibited.\n\n'
      '3. Parent/Therapist and Child Accounts\n'
      'Parents and therapists are responsible for managing accounts under their control. AutiEase is not liable for unauthorized misuse.\n\n'
      '4. Data Collection and Privacy\n'
      'AutiEase may collect essential information such as profile details, learning preferences, and app usage data to improve experience.\n\n'
      '5. Service and Safety Disclaimer\n'
      'AutiEase supports learning and communication but does not replace adult supervision or clinical judgment.\n\n'
      '6. Changes to Services\n'
      'We may update app features and content at any time to improve reliability, quality, and user experience.';
}
