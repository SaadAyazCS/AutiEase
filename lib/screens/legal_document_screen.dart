import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';

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
    // Determine the correct hardcoded content based on audience + documentId.
    // These are always the authoritative source. Firestore can only override
    // if an admin explicitly provides substantially richer content.
    final String canonicalTitle;
    final String canonicalBody;
    if (documentId == 'privacy-policy') {
      canonicalTitle = audience == 'therapist'
          ? 'Therapist Privacy Policy'
          : 'Parent Privacy Policy';
      canonicalBody = audience == 'therapist'
          ? _defaultTherapistPrivacyPolicyBody
          : _defaultParentPrivacyPolicyBody;
    } else {
      canonicalTitle = audience == 'therapist'
          ? 'Therapist Terms & Conditions'
          : 'Parent Terms & Conditions';
      canonicalBody = audience == 'therapist'
          ? _defaultTherapistTermsBody
          : _defaultParentTermsBody;
    }

    return FigmaModuleScaffold(
      title: documentId == 'privacy-policy' ? 'Privacy Policy' : 'Terms & Conditions',
      onBack: () => Navigator.pop(context),
      child: FutureBuilder<LegalDocument?>(
        future: AppRepositories.content.getLegalDocument(audience, documentId),
        builder: (context, snapshot) {
          // Only use Firestore data if it has a body that is substantially
          // longer than our hardcoded version (meaning admin updated it).
          final doc = snapshot.data;
          final firestoreBodyLonger = doc != null &&
              doc.body.trim().length > canonicalBody.length + 200;

          final String title = firestoreBodyLonger
              ? doc.title.trim().isNotEmpty
                  ? doc.title.trim()
                  : canonicalTitle
              : canonicalTitle;
          final String body =
              firestoreBodyLonger ? doc.body : canonicalBody;

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
                    const SizedBox(height: 8),
                    const Text(
                      'Version 1.0 — July 2026',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF526482),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
    );
  }

  static const String _defaultParentTermsBody =
      '1. Acceptance of Terms\n'
      'By registering and using the AutiEase application as a parent, you agree to comply with and be bound by these Terms of Service. If you do not agree, you must immediately cease using the platform.\n\n'
      '2. Description of Services\n'
      'AutiEase provides parent-guided developmental planners, gamified learning modules for children on the Autism Spectrum (ASD), and a marketplace directory to connect with and subscribe to independent clinical therapists and child behavioral specialists.\n\n'
      '3. Health & Medical Disclaimers\n'
      'AutiEase is an educational support tool and does not provide clinical diagnoses, medical treatments, or emergency healthcare services. Any recommendations, planners, or resources provided on the app are for supportive educational engagement and do not substitute for formal clinical advice or primary medical intervention.\n\n'
      '4. Account Security & Child Profiles\n'
      'You are responsible for keeping your login credentials confidential and for all activities that occur under your account. You agree to provide accurate child profile details to ensure the developmental planner maps content appropriately.\n\n'
      '5. Subscription & Payment Terms\n'
      'Subscription to a therapist\'s service package is billed monthly on a recurring basis. You may cancel your subscription at any time. Tapping on a package details card initiates checkout. If you are under active moderation restriction, you will be blocked from switching packages or purchasing new subscriptions.\n\n'
      '6. Platform Moderation & Restrictive Actions\n'
      'AutiEase maintains a strict zero-tolerance policy for abuse, harassment, or non-professional conduct. Reports filed against parent accounts are investigated by administrators and may result in warning states, active communication restrictions with specific therapists, account suspension, or permanent banning.';

  static const String _defaultTherapistTermsBody =
      '1. Professional Engagement & Acceptance of Terms\n'
      'By creating a professional therapist account and listing your profile on AutiEase, you represent and warrant that you hold the necessary clinical licenses, credentials, and experience to provide behavioral and development support services.\n\n'
      '2. Scope of Consulting & Disclaimers\n'
      'You act as an independent consultant. You agree to use the platform solely to communicate clinical progress insights, manage scheduler availability, and support parents. AutiEase does not dictate clinical treatment plans or assume liability for patient-provider disputes.\n\n'
      '3. Profile Verification & Quality Assurance\n'
      'All therapist profiles are subject to manual administrative review and verification of credentials. You agree to provide genuine certificates and background information. Any changes to key profile fields may trigger review flags in the admin panel.\n\n'
      '4. Scheduling & Service Packages\n'
      'You have the authority to establish your availability slots, rate cards, and service packages. Booked slots are subject to platform terms and therapist-parent agreements. You must honor booked appointments or provide adequate notice.\n\n'
      '5. Billing, Earnings & Withdrawals\n'
      'Earnings from parent subscriptions are accumulated in your platform wallet. You may request withdrawals through the platform\'s payment gateway, subject to withdrawal limits, admin verification, and cooldown periods.\n\n'
      '6. Moderation, Warning & Restriction Policies\n'
      'If a parent reports a therapist, administrators will review the report. Depending on the severity of the investigation, actions may include warnings, active communication restrictions with specific parents, profile list hiding, temporary dashboard suspension, or permanent account banning.';

  static const String _defaultParentPrivacyPolicyBody =
      'LAST UPDATED: July 12, 2026\n\n'
      'This Privacy Policy for AutiEase ("we," "us," or "our") describes how and why we might access, collect, store, use, and/or share ("process") your personal information when you use our services ("Services"), including when you:\n'
      '• Download and use our mobile application (AutiEase).\n'
      '• Use AutiEase as an educational support mobile application for children on the Autism Spectrum (ASD) that provides parent-guided developmental planners, interactive learning games, and a secure communication consulting channel connecting parents with clinical therapists.\n'
      '• Engage with us in other related ways, including feedback submissions.\n\n'
      '1. WHAT INFORMATION DO WE COLLECT?\n'
      'Personal information you disclose to us:\n'
      '• Standard Identifiers: Names (parent and child first names), email addresses, passwords, phone numbers (mobile wallets for payment verification).\n'
      '• Sensitive Data: Health data (child\'s developmental milestones and practice performance records), personal data from a known child (first name and age), and social security numbers or other government identifiers (where applicable).\n'
      '• Payment Data: SafePay is used to process your payment credentials. We do not store or collect your payment card details directly. SafePay\'s policy is available at https://getsafepay.pk/legal/content/privacy.\n'
      '• Application Permissions:\n'
      '  - Camera access: To upload profile pictures.\n'
      '  - Microphone access: Used for speech practice games and speech-to-text recognition.\n'
      '  - Storage access: To upload local documents and photos.\n'
      '  - Push Notifications: To send chat messages and schedule updates.\n\n'
      'Information automatically collected:\n'
      '• Log and Usage Data: Firebase Analytics automatically records app interactions, device version specifications, page views, and crash reports.\n\n'
      '2. HOW DO WE PROCESS YOUR INFORMATION?\n'
      'We process your information to:\n'
      '• Facilitate account registration, logins, and profile validation.\n'
      '• Deliver and facilitate the delivery of developmental planners and games.\n'
      '• Enable secure chat messaging and coordination with independent therapists.\n'
      '• Enforce app safety, respond to reports, and prevent fraud.\n'
      '• Identify usage trends and improve user experience.\n\n'
      '3. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?\n'
      'We only share information with the following third-party categories:\n'
      '• Cloud Computing Services (Firebase)\n'
      '• Data Analytics Services (Firebase Analytics)\n'
      '• Data Storage Service Providers (Firestore & Storage)\n'
      '• Payment Processors (SafePay)\n'
      '• User Account Registration & Authentication Services (Firebase Auth, Google Sign-In)\n\n'
      'Your data is NOT sold, shared, or rented to third-party ad networks.\n\n'
      '4. INTERNATIONAL TRANSFERS\n'
      'Your data is stored in the United States on Firebase servers. We adhere to the European Commission\'s Standard Contractual Clauses (SCCs) to ensure secure data transfer safeguards.\n\n'
      '5. RETENTION OF INFORMATION\n'
      'We keep your personal information only as long as you maintain an active account with us. When you request account deletion, all personal data is permanently wiped from our databases.\n\n'
      '6. HOW DO WE KEEP YOUR INFORMATION SAFE?\n'
      'We implement industry-standard organizational and technical security measures. However, no transmission over the internet can be guaranteed 100% secure.\n\n'
      '7. WHAT ARE YOUR PRIVACY RIGHTS?\n'
      'You have the right to request access, correction, or deletion of your personal data at any time.\n\n'
      '8. CONTACT US ABOUT THIS NOTICE\n'
      'If you have questions or comments, you may email us at autieasefyp@gmail.com or contact us by post at:\n'
      'AutiEase\n'
      'Model Town Humak, Islamabad\n'
      'Federal 45700, Pakistan';

  static const String _defaultTherapistPrivacyPolicyBody =
      'LAST UPDATED: July 12, 2026\n\n'
      'This Privacy Policy for AutiEase ("we," "us," or "our") describes how and why we might access, collect, store, use, and/or share ("process") your professional information when you use our services ("Services"), including when you:\n'
      '• Register as a professional clinical consultant or behavioral therapist.\n'
      '• Complete your public listing profile to connect with parent clients.\n'
      '• Interact with parents and kids to guide autism development schedules.\n\n'
      '1. WHAT INFORMATION DO WE COLLECT?\n'
      'Personal and professional information you disclose to us:\n'
      '• Standard Identifiers: Name, email address, password, phone number.\n'
      '• Professional Details: Bio, years and months of experience, clinical specializations, and uploaded qualification certificates (PDF).\n'
      '• Sensitive Data: CNIC (National ID Card Number) for professional verification, and bank account details / IBAN (for payout withdrawals).\n'
      '• Chat Logs: Transcripts of secure communication with parent clients.\n'
      '• Application Permissions:\n'
      '  - Camera access: To upload profile pictures.\n'
      '  - Storage access: To upload qualification certificates and files.\n'
      '  - Push Notifications: To receive real-time messages and booking updates.\n\n'
      'Information automatically collected:\n'
      '• Log and Usage Data: Firebase Analytics automatically records app interactions, device version specifications, page views, and crash reports.\n\n'
      '2. HOW DO WE PROCESS YOUR INFORMATION?\n'
      'We process your information to:\n'
      '• Verify identity, licensing, and professional credentials before listing on the directory.\n'
      '• Provide a public consulting profile for parents to discover.\n'
      '• Manage appointment scheduling and slot bookings.\n'
      '• Transfer accumulated subscription earnings to your bank account or mobile wallet.\n'
      '• Maintain security, safety checks, and moderation policies.\n\n'
      '3. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?\n'
      'We only share information with the following third-party categories:\n'
      '• Cloud Computing Services (Firebase)\n'
      '• Data Analytics Services (Firebase Analytics)\n'
      '• Data Storage Service Providers (Firestore & Storage)\n'
      '• Payment Processors (SafePay)\n'
      '• User Account Registration & Authentication Services (Firebase Auth, Google Sign-In)\n\n'
      'Your private credentials (CNIC, bank details) are strictly confidential and visible only to platform administrators.\n\n'
      '4. INTERNATIONAL TRANSFERS\n'
      'Your data is stored in the United States on Firebase servers. We adhere to the European Commission\'s Standard Contractual Clauses (SCCs) to ensure secure data transfer safeguards.\n\n'
      '5. RETENTION OF INFORMATION\n'
      'We keep your personal information only as long as you maintain an active account with us. When you request account deletion, all personal data is permanently wiped from our databases.\n\n'
      '6. HOW DO WE KEEP YOUR INFORMATION SAFE?\n'
      'We implement industry-standard organizational and technical security measures. However, no transmission over the internet can be guaranteed 100% secure.\n\n'
      '7. WHAT ARE YOUR PRIVACY RIGHTS?\n'
      'You have the right to request access, correction, or deletion of your personal data at any time.\n\n'
      '8. CONTACT US ABOUT THIS NOTICE\n'
      'If you have questions or comments, you may email us at autieasefyp@gmail.com or contact us by post at:\n'
      'AutiEase\n'
      'Model Town Humak, Islamabad\n'
      'Federal 45700, Pakistan';
}
