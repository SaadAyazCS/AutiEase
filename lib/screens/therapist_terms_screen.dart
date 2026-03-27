import 'legal_document_screen.dart';

class TherapistTermsScreen extends LegalDocumentScreen {
  const TherapistTermsScreen({super.key})
      : super(
          audience: 'therapist',
          documentId: 'therapist-terms',
          fallbackTitle: 'Therapist Terms',
        );
}
