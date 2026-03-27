import 'legal_document_screen.dart';

class AboutApplicationScreen extends LegalDocumentScreen {
  const AboutApplicationScreen({super.key})
      : super(
          audience: 'all',
          documentId: 'about-app',
          fallbackTitle: 'About Application',
        );
}
