import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cmr_models.dart';
import 'cmr_utils.dart';

class CmrPdfGenerator {
  static Future<Uint8List> generate({
    required CmrPedido pedido,
    FirebaseFirestore? firestore,
  }) async {
    final store = firestore ?? FirebaseFirestore.instance;
    final remitenteData = await obtenerDireccionRemitente(
      firestore: store,
      pedido: pedido,
    );
    final almacenData = await _fetchAlmacen(store);
    final isComercializador =
        pedido.remitente.trim().toUpperCase() == 'COMERCIALIZADOR';
    final remitenteLines = _buildRemitenteLines(
      data: remitenteData,
      pedido: pedido,
      isComercializador: isComercializador,
    );
    final plataforma = _resolvePlataforma(pedido);
    final almacenName = _valueForKey(almacenData, 'Almacen');
    final fechaSalida = _formatFecha(pedido.fechaSalida);
    final almacenLocation = _buildLocationLine(almacenData);

    final expedidorBg = await _loadBg('assets/cmr/cmr_expedidor.bmp');
    final destinatarioBg = await _loadBg('assets/cmr/cmr_destinatario.bmp');
    final transportistaBg =
        await _loadBg('assets/cmr/cmr_transportista.bmp');

    final doc = pw.Document();
    doc.addPage(
      _buildPage(
        background: expedidorBg,
        remitenteLines: remitenteLines,
        destinatario: pedido.cliente,
        plataforma: plataforma,
        almacen: almacenName,
        fechaSalida: fechaSalida,
        almacenLocation: almacenLocation,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
      ),
    );
    doc.addPage(
      _buildPage(
        background: destinatarioBg,
        remitenteLines: remitenteLines,
        destinatario: pedido.cliente,
        plataforma: plataforma,
        almacen: almacenName,
        fechaSalida: fechaSalida,
        almacenLocation: almacenLocation,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
      ),
    );
    doc.addPage(
      _buildPage(
        background: transportistaBg,
        remitenteLines: remitenteLines,
        destinatario: pedido.cliente,
        plataforma: plataforma,
        almacen: almacenName,
        fechaSalida: fechaSalida,
        almacenLocation: almacenLocation,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
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
    required List<String> remitenteLines,
    required String destinatario,
    required String plataforma,
    required String almacen,
    required String fechaSalida,
    required String almacenLocation,
    required String transportista,
    required String matricula,
  }) {
    const fontSize = 9.0;
    const field1Left = 250.0;
    const field1Top = 170.0;
    const field2Left = 250.0;
    const field2Top = 440.0;
    const field3Left = 250.0;
    const field3Top = 710.0;
    const field4Left = 250.0;
    const field4Top = 880.0;
    const field17Left = 1325.0;
    const field17Top = 445.0;

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
              left: field1Left,
              top: field1Top,
              child: pw.Text(
                remitenteLines.join('\n'),
                style: const pw.TextStyle(fontSize: fontSize),
              ),
            ),
            pw.Positioned(
              left: field2Left,
              top: field2Top,
              child: pw.Text(
                destinatario,
                style: const pw.TextStyle(fontSize: fontSize),
              ),
            ),
            pw.Positioned(
              left: field3Left,
              top: field3Top,
              child: pw.Text(
                plataforma,
                style: const pw.TextStyle(fontSize: fontSize),
              ),
            ),
            pw.Positioned(
              left: field4Left,
              top: field4Top,
              child: pw.Text(
                '$almacen        $fechaSalida\n$almacenLocation',
                style: const pw.TextStyle(fontSize: fontSize),
              ),
            ),
            pw.Positioned(
              left: field17Left,
              top: field17Top,
              child: pw.Text(
                '$transportista\n$matricula',
                style: const pw.TextStyle(fontSize: fontSize),
              ),
            ),
          ],
        );
      },
    );
  }

  static List<String> _buildRemitenteLines({
    required Map<String, dynamic> data,
    required CmrPedido pedido,
    required bool isComercializador,
  }) {
    final nif = _valueForKey(data, 'NIF');
    final nombre = isComercializador
        ? _valueForKey(data, 'Nombre')
        : _valueForKey(data, 'Cliente');
    final fallbackNombre =
        isComercializador ? pedido.comercializador : pedido.cliente;
    final direccion = _valueForKey(data, 'Direccion');
    final location = _buildLocationLine(data);

    return [
      nif,
      nombre.isNotEmpty ? nombre : fallbackNombre,
      direccion,
      location,
    ];
  }

  static String _buildLocationLine(Map<String, dynamic> data) {
    final cp = _valueForKey(data, 'CP');
    final poblacion = _valueForKey(data, 'Poblacion');
    final provincia = _valueForKey(data, 'Provincia');
    final pais = _valueForKey(data, 'Pais');

    final cpCity = [cp, poblacion].where((value) => value.isNotEmpty).join(' ');
    final provincePart = provincia.isNotEmpty ? provincia : '';
    final baseLine = [
      cpCity,
      if (cpCity.isNotEmpty && provincePart.isNotEmpty) '-',
      provincePart,
    ].where((value) => value.isNotEmpty).join(' ');

    if (pais.isEmpty) {
      return baseLine;
    }
    if (baseLine.isEmpty) {
      return '($pais)';
    }
    return '$baseLine ($pais)';
  }

  static String _valueForKey(Map<String, dynamic> data, String key) {
    return data[key]?.toString().trim() ?? '';
  }

  static String _formatFecha(DateTime? fecha) {
    final date = fecha ?? DateTime.now();
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String _resolvePlataforma(CmrPedido pedido) {
    final raw = pedido.raw['Plataforma']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      return raw;
    }
    for (final line in pedido.lineas) {
      final plataforma = line.plataforma?.trim() ?? '';
      if (plataforma.isNotEmpty) {
        return plataforma;
      }
    }
    return '';
  }

  static Future<Map<String, dynamic>> _fetchAlmacen(
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore.collection('MAlmacen').limit(1).get();
    if (snapshot.docs.isEmpty) {
      return <String, dynamic>{};
    }
    return snapshot.docs.first.data();
  }

  static Future<void> printPdf(Uint8List data) {
    return Printing.layoutPdf(onLayout: (_) => data);
  }
}
