import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cmr_field_layout.dart';
import 'cmr_models.dart';
import 'cmr_utils.dart';

class CmrPdfGenerator {
  static Future<CmrLayoutMap>? _layoutCache;

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
    final almacenPoblacion =
        _stringFromKeys(almacenData, const ['Población', 'Poblacion']);
    final merchandiseData =
        await _buildMerchandiseRows(pedido: pedido, firestore: store);
    final tipoPalet = _resolveTipoPalet(pedido);
    final layout = await _loadLayout();

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
        almacenPoblacion: almacenPoblacion,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
        termografos: pedido.termografos,
        observaciones: pedido.observaciones,
        paletRetEntr: pedido.paletRetEntr,
        paletRetDev: pedido.paletRetDev,
        tipoPalet: tipoPalet,
        merchandiseData: merchandiseData,
        layout: layout,
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
        almacenPoblacion: almacenPoblacion,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
        termografos: pedido.termografos,
        observaciones: pedido.observaciones,
        paletRetEntr: pedido.paletRetEntr,
        paletRetDev: pedido.paletRetDev,
        tipoPalet: tipoPalet,
        merchandiseData: merchandiseData,
        layout: layout,
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
        almacenPoblacion: almacenPoblacion,
        transportista: pedido.transportista,
        matricula: pedido.matricula,
        termografos: pedido.termografos,
        observaciones: pedido.observaciones,
        paletRetEntr: pedido.paletRetEntr,
        paletRetDev: pedido.paletRetDev,
        tipoPalet: tipoPalet,
        merchandiseData: merchandiseData,
        layout: layout,
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
    required String almacenPoblacion,
    required String transportista,
    required String matricula,
    required String termografos,
    required String observaciones,
    required String paletRetEntr,
    required String paletRetDev,
    required String tipoPalet,
    required _CmrMerchandiseData merchandiseData,
    required CmrLayoutMap layout,
  }) {
    const fontSize = 9.0;
    const merchFontSize = 8.0;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(background, fit: pw.BoxFit.fill),
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '1',
              value: remitenteLines.join('\n'),
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '2',
              value: destinatario,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '3',
              value: plataforma,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '4',
              value: '$almacen        $fechaSalida\n$almacenLocation',
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '5',
              value: termografos,
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '13',
              value: observaciones,
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '17',
              value: '$transportista\n$matricula',
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '22A',
              value: almacenPoblacion,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '22B',
              value: fechaSalida,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '26A',
              value: paletRetEntr,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '26B',
              value: paletRetDev,
              fontSize: fontSize,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '27',
              value: tipoPalet,
              fontSize: fontSize,
              multiline: true,
            ),
            ..._buildMerchandiseWidgets(
              merchandiseData,
              fontSize: merchFontSize,
              layout: layout,
            ),
          ],
        );
      },
    );
  }

  static List<pw.Widget> _buildMerchandiseWidgets(
    _CmrMerchandiseData data, {
    required double fontSize,
    required CmrLayoutMap layout,
  }) {
    final widgets = <pw.Widget>[];
    final textStyle = pw.TextStyle(fontSize: fontSize);
    final rows = data.rows;
    final rowHeight = _resolveMerchandiseRowHeight(layout);
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final fields = [
        _MerchandiseField('6', row.marca),
        _MerchandiseField('7', row.totalCajas),
        _MerchandiseField('8', row.idConfeccion),
        _MerchandiseField('9', row.cultivo),
        _MerchandiseField('11', row.totalNeto),
        _MerchandiseField('12', row.totalPalets),
      ];

      for (final field in fields) {
        final layoutField = layout.getField(field.casilla);
        if (layoutField == null) continue;
        final effectiveHeight =
            rowHeight > 0 ? rowHeight : layoutField.height;
        final top = layoutField.y + (rowIndex * effectiveHeight);
        widgets.add(
          pw.Positioned(
            left: layoutField.x,
            top: top,
            child: pw.SizedBox(
              width: layoutField.width,
              height: layoutField.height,
              child: pw.Text(
                field.value,
                style: textStyle,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ),
          ),
        );
      }
    }
    if (rows.isNotEmpty) {
      final totalRowIndex = rows.length;
      final totalFields = [
        _MerchandiseField('7', _formatNum(data.totalCajas)),
        _MerchandiseField('11', _formatNum(data.totalNeto)),
        _MerchandiseField('12', data.totalPalets.toString()),
      ];
      for (final field in totalFields) {
        final layoutField = layout.getField(field.casilla);
        if (layoutField == null) continue;
        final effectiveHeight =
            rowHeight > 0 ? rowHeight : layoutField.height;
        final top = layoutField.y + (totalRowIndex * effectiveHeight);
        widgets.add(
          pw.Positioned(
            left: layoutField.x,
            top: top,
            child: pw.SizedBox(
              width: layoutField.width,
              height: layoutField.height,
              child: pw.Text(
                field.value,
                style: textStyle,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  static List<pw.Widget> _buildFieldWidgets(
    CmrLayoutMap layout, {
    required String casilla,
    required String value,
    required double fontSize,
    bool multiline = false,
  }) {
    final field = layout.getField(casilla);
    if (field == null) {
      return const [];
    }
    return [
      pw.Positioned(
        left: field.x,
        top: field.y,
        child: _buildCmrText(
          value: value,
          field: field,
          fontSize: fontSize,
          multiline: multiline,
        ),
      ),
    ];
  }

  static pw.Widget _buildCmrText({
    required String value,
    required CmrFieldLayout field,
    required double fontSize,
    required bool multiline,
  }) {
    final text = pw.Text(
      value,
      style: pw.TextStyle(fontSize: fontSize),
      softWrap: multiline,
      maxLines: multiline ? null : 1,
      overflow: pw.TextOverflow.clip,
    );

    final box = pw.SizedBox(
      width: field.width,
      height: field.height,
      child: text,
    );

    return multiline ? pw.ClipRect(child: box) : box;
  }

  static Future<CmrLayoutMap> _loadLayout() {
    _layoutCache ??= CmrLayoutLoader.loadFromAssets();
    return _layoutCache!;
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

  static Future<_CmrMerchandiseData> _buildMerchandiseRows({
    required CmrPedido pedido,
    required FirebaseFirestore firestore,
  }) async {
    final paletIds = parsePaletsFromLines(
      pedido.lineas.expand((linea) => linea.palets),
    );
    if (paletIds.isEmpty) {
      return const _CmrMerchandiseData.empty();
    }

    final grouped = <_MerchandiseKey, _MerchandiseGroup>{};
    final confeccionCache = <String, String>{};
    for (final paletId in paletIds) {
      final stockDocId = '1$paletId';
      final snapshot =
          await firestore.collection('Stock').doc(stockDocId).get();
      if (!snapshot.exists) {
        continue;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final marca = _stringFromKeys(data, const ['MARCA', 'Marca', 'marca']);
      final idConfeccion =
          _stringFromKeys(data, const ['IDCONFECCION', 'IdConfeccion']);
      String confeccionDescripcion = '';
      if (idConfeccion.isNotEmpty) {
        confeccionDescripcion = confeccionCache[idConfeccion] ??
            await _fetchConfeccionDescripcion(
              firestore: firestore,
              idConfeccion: idConfeccion,
            );
        confeccionCache[idConfeccion] = confeccionDescripcion;
      }
      final cultivo =
          _stringFromKeys(data, const ['CULTIVO', 'Cultivo', 'cultivo']);
      final cajas =
          _numFromKeys(data, const ['CAJAS', 'Cajas', 'cajas']) ?? 0;
      final neto =
          _numFromKeys(data, const ['NETO', 'Neto', 'neto']) ?? 0;

      final key = _MerchandiseKey(
        marca: marca,
        idConfeccion: idConfeccion,
        cultivo: cultivo,
      );
      final group = grouped.putIfAbsent(
        key,
        () => _MerchandiseGroup(
          marca: marca,
          idConfeccion: idConfeccion,
          cultivo: cultivo,
          confeccionDescripcion: confeccionDescripcion,
        ),
      );
      if (group.confeccionDescripcion.isEmpty &&
          confeccionDescripcion.isNotEmpty) {
        group.confeccionDescripcion = confeccionDescripcion;
      }
      group.totalCajas += cajas;
      group.totalNeto += neto;
      group.totalPalets += 1;
    }

    if (grouped.isEmpty) {
      return const _CmrMerchandiseData.empty();
    }

    num totalCajas = 0;
    num totalNeto = 0;
    var totalPalets = 0;

    final rows = grouped.values.map((group) {
      totalCajas += group.totalCajas;
      totalNeto += group.totalNeto;
      totalPalets += group.totalPalets;
      return _CmrMerchandiseRow(
        marca: group.marca,
        idConfeccion: group.confeccionDescripcion.isNotEmpty
            ? group.confeccionDescripcion
            : group.idConfeccion,
        cultivo: group.cultivo,
        totalCajas: _formatNum(group.totalCajas),
        totalNeto: _formatNum(group.totalNeto),
        totalPalets: group.totalPalets.toString(),
      );
    }).toList();

    return _CmrMerchandiseData(
      rows: rows,
      totalCajas: totalCajas,
      totalNeto: totalNeto,
      totalPalets: totalPalets,
    );
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

  static Future<String> _fetchConfeccionDescripcion({
    required FirebaseFirestore firestore,
    required String idConfeccion,
  }) async {
    final snapshot = await firestore
        .collection('MConfecciones')
        .where('CODIGO', isEqualTo: idConfeccion)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return '';
    }
    final data = snapshot.docs.first.data();
    return data['DESCRIPCORTA']?.toString().trim() ?? '';
  }

  static String _valueForKey(Map<String, dynamic> data, String key) {
    return data[key]?.toString().trim() ?? '';
  }

  static String _stringFromKeys(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static num? _numFromKeys(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = data[key];
      if (raw == null) continue;
      if (raw is num) return raw;
      final parsed = num.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _formatNum(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final formatted = value.toStringAsFixed(2);
    return formatted
        .replaceFirst(RegExp(r'\.0+$'), '')
        .replaceFirst(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
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

  static String _resolveTipoPalet(CmrPedido pedido) {
    final tipoPalets = pedido.lineas
        .map((linea) => linea.tipoPalet?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    if (tipoPalets.isEmpty) {
      return '';
    }
    final unique = <String>{};
    final ordered = <String>[];
    for (final value in tipoPalets) {
      if (unique.add(value)) {
        ordered.add(value);
      }
    }
    return ordered.join('\n');
  }

  static double _resolveMerchandiseRowHeight(CmrLayoutMap layout) {
    final primary = layout.getField('6');
    if (primary != null) return primary.height;
    final fallback = layout.getField('7');
    if (fallback != null) return fallback.height;
    return layout.getField('8')?.height ?? 0;
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

class _CmrMerchandiseData {
  const _CmrMerchandiseData({
    required this.rows,
    required this.totalCajas,
    required this.totalNeto,
    required this.totalPalets,
  });

  const _CmrMerchandiseData.empty()
      : rows = const [],
        totalCajas = 0,
        totalNeto = 0,
        totalPalets = 0;

  final List<_CmrMerchandiseRow> rows;
  final num totalCajas;
  final num totalNeto;
  final int totalPalets;
}

class _CmrMerchandiseRow {
  const _CmrMerchandiseRow({
    required this.marca,
    required this.idConfeccion,
    required this.cultivo,
    required this.totalCajas,
    required this.totalNeto,
    required this.totalPalets,
  });

  final String marca;
  final String idConfeccion;
  final String cultivo;
  final String totalCajas;
  final String totalNeto;
  final String totalPalets;
}

class _MerchandiseField {
  const _MerchandiseField(this.casilla, this.value);

  final String casilla;
  final String value;
}

class _MerchandiseKey {
  const _MerchandiseKey({
    required this.marca,
    required this.idConfeccion,
    required this.cultivo,
  });

  final String marca;
  final String idConfeccion;
  final String cultivo;

  @override
  bool operator ==(Object other) {
    return other is _MerchandiseKey &&
        other.marca == marca &&
        other.idConfeccion == idConfeccion &&
        other.cultivo == cultivo;
  }

  @override
  int get hashCode => Object.hash(marca, idConfeccion, cultivo);
}

class _MerchandiseGroup {
  _MerchandiseGroup({
    required this.marca,
    required this.idConfeccion,
    required this.cultivo,
    required this.confeccionDescripcion,
  });

  final String marca;
  final String idConfeccion;
  final String cultivo;
  String confeccionDescripcion;
  num totalCajas = 0;
  num totalNeto = 0;
  int totalPalets = 0;
}
