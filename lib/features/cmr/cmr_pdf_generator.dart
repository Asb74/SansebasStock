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
        copia: 'Ejemplar expedidor',
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
        copia: 'Ejemplar destinatario',
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
        copia: 'Ejemplar transportista',
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
    required String copia,
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
            // Textos de prueba para validar el layout. Ajustar posiciones
            // cuando se mapeen todas las casillas definitivas.
            pw.Positioned(
              left: 40,
              top: 70,
              child: pw.Text(
                copia,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Positioned(
              left: 40,
              top: 120,
              child: pw.Text('Remitente: $remitente'),
            ),
            pw.Positioned(
              left: 40,
              top: 170,
              child: pw.Text('Destinatario: $destinatario'),
            ),
            pw.Positioned(
              left: 40,
              top: 220,
              child: pw.Text('Transportista: $transportista'),
            ),
            pw.Positioned(
              left: 40,
              top: 270,
              child: pw.Text('Fecha: $fecha'),
            ),
            pw.Positioned(
              left: 40,
              top: 320,
              child: pw.Text('Número de palets: $palets'),
            ),
            pw.Positioned(
              left: 40,
              top: 370,
              right: 40,
              child: pw.Text('Observaciones: $observaciones'),
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
