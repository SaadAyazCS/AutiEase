import 'legal_document_screen.dart';

class ParentTermsScreen extends LegalDocumentScreen {
  const ParentTermsScreen({super.key})
      : super(
          audience: 'parent',
          documentId: 'parent-terms',
          fallbackTitle: 'Parent Terms',
        );
}
