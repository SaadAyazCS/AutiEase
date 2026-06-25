import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class ReceiptViewerScreen extends StatelessWidget {
  const ReceiptViewerScreen({
    super.key,
    required this.base64String,
    this.title = 'Payout Receipt',
  });

  final String base64String;
  final String title;

  @override
  Widget build(BuildContext context) {
    Uint8List bytes;
    try {
      bytes = base64Decode(base64String.trim());
    } catch (e) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('Failed to decode receipt file: $e')),
      );
    }

    final isPdfFile = _isPdf(bytes);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                if (isPdfFile) {
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: 'receipt.pdf',
                  );
                } else {
                  // share image
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: 'receipt.png',
                  );
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to share receipt: $e')),
                );
              }
            },
            tooltip: 'Share/Download Receipt',
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Center(
          child: isPdfFile
              ? PdfPreview(
                  build: (format) => bytes,
                  allowPrinting: true,
                  allowSharing: true,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  maxPageWidth: 700,
                  pdfFileName: 'receipt.pdf',
                  previewPageMargin: const EdgeInsets.all(16),
                  dynamicLayout: false,
                )
              : InteractiveViewer(
                  maxScale: 4.0,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(child: Text('Unsupported receipt format.'));
                    },
                  ),
                ),
        ),
      ),
    );
  }

  bool _isPdf(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  }
}
