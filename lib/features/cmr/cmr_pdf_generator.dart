import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cmr_field_layout.dart';
import 'cmr_models.dart';
import 'cmr_utils.dart';

enum CmrBoxType { table, multiline, longline }

CmrBoxType getBoxType(String casilla) {
  if (['5', '13'].contains(casilla)) return CmrBoxType.multiline;
  if (['27'].contains(casilla)) return CmrBoxType.longline;
  return CmrBoxType.table;
}

class CmrPdfGenerator {
  static Future<CmrLayoutMap>? _layoutCache;

  static const Map<String, int> _tableMaxCharsByCasilla = {
    '6': 16,
    '7': 6,
    '8': 14,
    '9': 12,
    '11': 8,
    '12': 6,
  };

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
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '2',
              value: destinatario,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '3',
              value: plataforma,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '4',
              value: '$almacen        $fechaSalida\n$almacenLocation',
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '5',
              value: termografos,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '13',
              value: observaciones,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '17',
              value: '$transportista\n$matricula',
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '22A',
              value: almacenPoblacion,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '22B',
              value: fechaSalida,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '26A',
              value: paletRetEntr,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '26B',
              value: paletRetDev,
            ),
            ..._buildFieldWidgets(
              layout,
              casilla: '27',
              value: tipoPalet,
            ),
            ..._buildMerchandiseWidgets(
              merchandiseData,
              layout: layout,
            ),
          ],
        );
      },
    );
  }

  static List<pw.Widget> _buildMerchandiseWidgets(
    _CmrMerchandiseData data, {
    required CmrLayoutMap layout,
  }) {
    final widgets = <pw.Widget>[];
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
        final boxType = getBoxType(field.casilla);
        final widget = _buildBoxWidget(
          value: field.value,
          field: layoutField,
          boxType: boxType,
        );
        widgets.add(
          pw.Positioned(
            left: layoutField.x,
            top: top,
            child: widget,
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
        final boxType = getBoxType(field.casilla);
        final widget = _buildBoxWidget(
          value: field.value,
          field: layoutField,
          boxType: boxType,
        );
        widgets.add(
          pw.Positioned(
            left: layoutField.x,
            top: top,
            child: widget,
          ),
        );
      }
    }
    return widgets;
  }

  static String hardWrap(String text, int maxChars) {
    if (maxChars <= 0) return text;
    final buffer = StringBuffer();
    var count = 0;
    for (final char in text.characters) {
      buffer.write(char);
      count++;
      if (count >= maxChars) {
        buffer.write('\n');
        count = 0;
      }
    }
    return buffer.toString();
  }

  static pw.Widget multilineBox(String text, CmrFieldLayout field) {
    final maxLines = (field.height / 9).floor();
    return pw.ClipRect(
      child: pw.SizedBox(
        width: field.width,
        height: field.height,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 8),
          softWrap: true,
          maxLines: maxLines,
          overflow: pw.TextOverflow.clip,
        ),
      ),
    );
  }

  static pw.Widget longLineBox(String text, CmrFieldLayout field) {
    return pw.SizedBox(
      width: field.width,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8),
        maxLines: 1,
      ),
    );
  }

  static pw.Widget tableBox(String text, CmrFieldLayout field) {
    return pw.SizedBox(
      width: field.width,
      height: field.height,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8),
        maxLines: null,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static int _maxCharsForTableCasilla(String casilla) {
    return _tableMaxCharsByCasilla[casilla] ?? 9999;
  }

  static pw.Widget _buildBoxWidget({
    required String value,
    required CmrFieldLayout field,
    required CmrBoxType boxType,
  }) {
    switch (boxType) {
      case CmrBoxType.multiline:
        return multilineBox(value, field);
      case CmrBoxType.longline:
        return longLineBox(value, field);
      case CmrBoxType.table:
        final maxChars = _maxCharsForTableCasilla(field.casilla);
        final wrapped = hardWrap(value, maxChars);
        return tableBox(wrapped, field);
    }
  }

  static List<pw.Widget> _buildFieldWidgets(
    CmrLayoutMap layout, {
    required String casilla,
    required String value,
  }) {
    final field = layout.getField(casilla);
    if (field == null) {
      return const [];
    }
    final boxType = getBoxType(field.casilla);
    return [
      pw.Positioned(
        left: field.x,
        top: field.y,
        child: _buildBoxWidget(
          value: value,
          field: field,
          boxType: boxType,
        ),
      ),
    ];
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
