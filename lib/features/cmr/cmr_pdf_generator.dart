import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CmrPdfGenerator {
  static Future<Uint8List> generate({
    required String remitente,
    required String destinatario,
    required String transportista,
    required String fecha,
    required String palets,
    required String observaciones,
  }) async {
    final expedidorBg = await _loadBg('assets/cmr/cmr_expedidor.bmp');
    final destinatarioBg = await _loadBg('assets/cmr/cmr_destinatario.bmp');
    final transportistaBg =
        await _loadBg('assets/cmr/cmr_transportista.bmp');

    final doc = pw.Document();
    doc.addPage(
      _buildPage(
        background: expedidorBg,
        remitente: remitente,
        destinatario: destinatario,
        transportista: transportista,
        fecha: fecha,
        palets: palets,
        observaciones: observaciones,
      ),
    );
    doc.addPage(
      _buildPage(
        background: destinatarioBg,
        remitente: remitente,
        destinatario: destinatario,
        transportista: transportista,
        fecha: fecha,
        palets: palets,
        observaciones: observaciones,
      ),
    );
    doc.addPage(
      _buildPage(
        background: transportistaBg,
        remitente: remitente,
        destinatario: destinatario,
        transportista: transportista,
        fecha: fecha,
        palets: palets,
        observaciones: observaciones,
      ),
    );

    return doc.save();
  }

  static Future<pw.MemoryImage> _loadBg(String path) async {
    final bytes = await rootBundle.load(path);
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static pw.Page _buildPage({
    required pw.MemoryImage background,
    required String remitente,
    required String destinatario,
    required String transportista,
    required String fecha,
    required String palets,
    required String observaciones,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(background, fit: pw.BoxFit.fill),
            ),
            pw.Positioned(
              left: 60,
              top: 150,
              child: pw.Text(
                remitente,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Positioned(
              left: 60,
              top: 210,
              child: pw.Text(
                destinatario,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Positioned(
              left: 60,
              top: 270,
              child: pw.Text(
                transportista,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Positioned(
              left: 430,
              top: 110,
              child: pw.Text(
                fecha,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Positioned(
              left: 420,
              top: 470,
              child: pw.Text(
                palets,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Positioned(
              left: 60,
              top: 640,
              right: 60,
              child: pw.Text(
                observaciones,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> printPdf(Uint8List data) {
    return Printing.layoutPdf(onLayout: (_) => data);
  }
}
