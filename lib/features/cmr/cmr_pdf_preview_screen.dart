import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class CmrPdfPreviewScreen extends StatelessWidget {
  const CmrPdfPreviewScreen({
    super.key,
    required this.data,
    required this.title,
  });

  final Uint8List data;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) async => data,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
      ),
    );
  }
}
