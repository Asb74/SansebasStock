import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'cmr_models.dart';

class CmrPdfService {
  CmrPdfService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<File> generatePdf({
    required CmrPedido pedido,
    required List<String> palets,
    required Map<String, int?> lineaByPalet,
  }) async {
    final remitente = await _fetchRemitente(pedido);
    final destinatario = await _fetchDestinatario(pedido);
    final almacen = await _fetchAlmacen();

    final doc = pw.Document();
    final copies = <_CmrCopyInfo>[
      _CmrCopyInfo(
        label: 'Ejemplar para el remitente',
        color: PdfColors.red,
      ),
      _CmrCopyInfo(
        label: 'Ejemplar para el consignatario/destinatario',
        color: PdfColors.blue,
      ),
      _CmrCopyInfo(
        label: 'Ejemplar para el porteador',
        color: PdfColors.green,
      ),
      _CmrCopyInfo(
        label: 'Ejemplar para el almacén',
        color: PdfColors.black,
      ),
    ];

    for (final copy in copies) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => _buildCopyPage(
            pedido: pedido,
            palets: palets,
            remitente: remitente,
            destinatario: destinatario,
            almacen: almacen,
            copy: copy,
          ),
        ),
      );
    }

    if (palets.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return _buildAnnex(
              palets: palets,
              lineaByPalet: lineaByPalet,
            );
          },
        ),
      );
    }

    final bytes = await doc.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${Directory.systemTemp.path}/cmr_$timestamp.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  pw.Widget _buildCopyPage({
    required CmrPedido pedido,
    required List<String> palets,
    required _CmrAddress remitente,
    required _CmrAddress destinatario,
    required _CmrAddress almacen,
    required _CmrCopyInfo copy,
  }) {
    final formatter = DateFormat('dd/MM/yyyy');
    final salida = pedido.fechaSalida != null
        ? formatter.format(pedido.fechaSalida!)
        : '—';

    final paletsTotal = palets.length;
    final rows = <List<String>>[];
    for (final line in pedido.lineas) {
      rows.add(
        <String>[
          line.linea?.toString() ?? '—',
          line.plataforma ?? '—',
          line.tipoPalet ?? '—',
          line.palets.length.toString(),
        ],
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: copy.color, width: 2),
      ),
      padding: const pw.EdgeInsets.all(16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            copy.label,
            style: pw.TextStyle(
              color: copy.color,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'CMR',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Pedido: ${pedido.idPedidoLora}'),
          pw.Text('Fecha salida: $salida'),
          pw.Text('Transportista: ${pedido.transportista}'),
          pw.Text('Matrícula: ${pedido.matricula}'),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildAddressBlock('Remitente', remitente),
              pw.SizedBox(width: 12),
              _buildAddressBlock('Destinatario', destinatario),
            ],
          ),
          pw.SizedBox(height: 12),
          _buildAddressBlock('Lugar de carga', almacen),
          pw.SizedBox(height: 12),
          pw.Text(
            'Líneas del pedido',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headers: const ['Línea', 'Plataforma', 'Tipo palet', 'Palets'],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Text('Palets totales: $paletsTotal'),
          pw.SizedBox(height: 6),
          pw.Text('Termógrafos: ${pedido.termografos.isNotEmpty ? pedido.termografos : '—'}'),
          pw.Text('Observaciones: ${pedido.observaciones.isNotEmpty ? pedido.observaciones : '—'}'),
          pw.SizedBox(height: 6),
          pw.Text('Palet retorno entrada: ${pedido.paletRetEntr.isNotEmpty ? pedido.paletRetEntr : '—'}'),
          pw.Text('Palet retorno devolución: ${pedido.paletRetDev.isNotEmpty ? pedido.paletRetDev : '—'}'),
        ],
      ),
    );
  }

  pw.Widget _buildAddressBlock(String title, _CmrAddress address) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            if (address.name.isNotEmpty) pw.Text(address.name),
            for (final line in address.lines) pw.Text(line),
          ],
        ),
      ),
    );
  }

  List<pw.Widget> _buildAnnex({
    required List<String> palets,
    required Map<String, int?> lineaByPalet,
  }) {
    final rows = palets
        .map(
          (palet) => [
            palet,
            lineaByPalet[palet]?.toString() ?? '—',
          ],
        )
        .toList();

    return [
      pw.Text(
        'Anexo palets',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
      pw.Table.fromTextArray(
        headers: const ['Palet', 'Línea'],
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignment: pw.Alignment.centerLeft,
      ),
    ];
  }

  Future<_CmrAddress> _fetchRemitente(CmrPedido pedido) async {
    if (pedido.remitente.toUpperCase() == 'COMERCIALIZADOR') {
      final comercial = await _findByName(
        collection: 'MComercial',
        name: pedido.comercializador,
        fields: const ['Nombre', 'Comercializador', 'COMERCIALIZADOR'],
      );
      return _addressFromMap(
        name: pedido.comercializador,
        data: comercial,
      );
    }

    final destinatario = await _findByName(
      collection: 'MCliente_Pais',
      name: pedido.cliente,
      fields: const ['Cliente', 'Nombre', 'ID', 'Id', 'IdPedidoCliente'],
    );
    return _addressFromMap(name: pedido.cliente, data: destinatario);
  }

  Future<_CmrAddress> _fetchDestinatario(CmrPedido pedido) async {
    final destinatario = await _findByName(
      collection: 'MCliente_Pais',
      name: pedido.cliente,
      fields: const ['Cliente', 'Nombre', 'ID', 'Id', 'IdPedidoCliente'],
    );
    return _addressFromMap(name: pedido.cliente, data: destinatario);
  }

  Future<_CmrAddress> _fetchAlmacen() async {
    final snapshot = await _firestore.collection('MAlmacen').limit(1).get();
    final data = snapshot.docs.isNotEmpty ? snapshot.docs.first.data() : null;
    return _addressFromMap(name: 'Almacén', data: data);
  }

  Future<Map<String, dynamic>?> _findByName({
    required String collection,
    required String name,
    required List<String> fields,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final field in fields) {
      final snapshot = await _firestore
          .collection(collection)
          .where(field, isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
    }

    final docSnap = await _firestore.collection(collection).doc(trimmed).get();
    if (docSnap.exists) {
      return docSnap.data();
    }

    return null;
  }

  _CmrAddress _addressFromMap({
    required String name,
    Map<String, dynamic>? data,
  }) {
    if (data == null) {
      return _CmrAddress(name: name, lines: const []);
    }

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = data[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }

    final address = pick(const ['Direccion', 'Dirección', 'Direccion1']);
    final address2 = pick(const ['Direccion2', 'Dirección2', 'Direccion_2']);
    final city = pick(const ['Localidad', 'Poblacion', 'Ciudad']);
    final province = pick(const ['Provincia', 'Estado']);
    final postal = pick(const ['CP', 'CodigoPostal', 'Postal']);
    final country = pick(const ['Pais', 'País']);
    final phone = pick(const ['Telefono', 'Teléfono', 'Telefono1']);

    final lines = <String>[];
    if (address.isNotEmpty) lines.add(address);
    if (address2.isNotEmpty) lines.add(address2);
    final cityLine = [postal, city, province]
        .where((value) => value.isNotEmpty)
        .join(' ');
    if (cityLine.isNotEmpty) lines.add(cityLine);
    if (country.isNotEmpty) lines.add(country);
    if (phone.isNotEmpty) lines.add('Tel: $phone');

    return _CmrAddress(name: name, lines: lines);
  }
}

class _CmrCopyInfo {
  _CmrCopyInfo({required this.label, required this.color});

  final String label;
  final PdfColor color;
}

class _CmrAddress {
  _CmrAddress({required this.name, required this.lines});

  final String name;
  final List<String> lines;
}
