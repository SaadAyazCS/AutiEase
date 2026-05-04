import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class CertificateViewerScreen extends StatelessWidget {
  const CertificateViewerScreen({
    super.key,
    required this.pdfBytes,
    required this.title,
  });

  final Uint8List pdfBytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF77C6F0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'therapist_certificate.pdf',
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to download: $e')),
                );
              }
            },
            tooltip: 'Download Certificate',
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Center(
          child: PdfPreview(
            build: (format) => pdfBytes,
            allowPrinting: true,
            allowSharing: true,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            maxPageWidth: 700,
            pdfFileName: 'therapist_certificate.pdf',
            previewPageMargin: const EdgeInsets.all(16),
            dynamicLayout: false,
          ),
        ),
      ),
    );
  }
}
