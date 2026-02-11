import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sansebas_stock/utils/stock_doc_id.dart';

import 'cmr_field_layout.dart';
import 'cmr_models.dart';
import 'cmr_utils.dart';

class CmrPdfGenerator {
  static Future<CmrLayout>? _layoutCache;

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
    final almacenName = _valueForKey(almacenData, 'Almacen');
    final fechaSalida = _formatFecha(pedido.fechaSalida);
    final almacenLocation = _buildLocationLine(almacenData);
    final almacenPoblacion =
        _stringFromKeys(almacenData, const ['Población', 'Poblacion']);
    final layout = await _loadLayout();

    final expedidorBg = await _loadBg('assets/cmr/cmr_expedidor.bmp');
    final destinatarioBg = await _loadBg('assets/cmr/cmr_destinatario.bmp');
    final transportistaBg =
        await _loadBg('assets/cmr/cmr_transportista.bmp');

    final doc = pw.Document();
    final plataformas = _groupLineasByPlataforma(pedido);
    final plataformaEntries = plataformas.entries.toList()
      ..sort(
        (a, b) => _platformSortKey(a.key, pedido)
            .compareTo(_platformSortKey(b.key, pedido)),
      );
    if (plataformaEntries.isEmpty) {
      // No generamos CMR sin líneas: evitamos crear un PDF vacío.
      return Uint8List(0);
    }
    for (final entry in plataformaEntries) {
      final lineas = entry.value;
      final plataforma = _resolvePlataforma(entry.key, pedido);
      final paletsExpedidos = parsePaletsFromLines(
        lineas.expand((linea) => linea.palets),
      );
      final merchandiseData = await _buildMerchandiseRows(
        lineas: lineas,
        firestore: store,
      );
      final tipoPalet = _resolveTipoPalet(lineas);
      final cmrValues = buildCmrFieldValues(pedido)
        ..addAll({
          '1': remitenteLines.join('\n'),
          '2': pedido.cliente,
          '3': plataforma,
          '4': [
            [
              almacenName,
              fechaSalida,
            ].where((value) => value.trim().isNotEmpty).join('        '),
            almacenLocation,
          ].where((value) => value.trim().isNotEmpty).join('\n'),
          '5': pedido.termografos,
          '12':
              paletsExpedidos.isNotEmpty ? paletsExpedidos.length.toString() : '',
          '13': pedido.observaciones,
          '17': [
            pedido.transportista,
            pedido.matricula,
          ].where((value) => value.trim().isNotEmpty).join('\n'),
          '22A': almacenPoblacion,
          '22B': fechaSalida,
          '26A':
              'Palets Retornables Entregados: ${pedido.paletRetDev.trim()}',
          '26B':
              'Palets Retornables Devueltos: ${pedido.paletRetEntr.trim()}',
          '27': tipoPalet,
        });

      // Orden de páginas CMR: Rojo (Expedidor) → Verde (Transportista) → Azul (Destinatario).
      doc.addPage(
        _buildPage(
          background: expedidorBg,
          cmrValues: cmrValues,
          merchandiseData: merchandiseData,
          layout: layout,
        ),
      );
      doc.addPage(
        _buildPage(
          background: transportistaBg,
          cmrValues: cmrValues,
          merchandiseData: merchandiseData,
          layout: layout,
        ),
      );
      doc.addPage(
        _buildPage(
          background: destinatarioBg,
          cmrValues: cmrValues,
          merchandiseData: merchandiseData,
          layout: layout,
        ),
      );
    }

    return doc.save();
  }

  static Future<pw.MemoryImage> _loadBg(String path) async {
    final bytes = await rootBundle.load(path);
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static pw.Page _buildPage({
    required pw.MemoryImage background,
    required Map<String, String> cmrValues,
    required _CmrMerchandiseData merchandiseData,
    required CmrLayout layout,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        final backgroundWidgets = <pw.Widget>[
          pw.Positioned.fill(
            child: pw.Image(background, fit: pw.BoxFit.fill),
          ),
        ];
        final foregroundWidgets = <pw.Widget>[
          ..._buildCmrValueWidgets(cmrValues, layout),
          ..._buildMerchandiseWidgets(
            merchandiseData,
            layout: layout,
          ),
        ];
        return pw.Stack(
          children: [
            ...backgroundWidgets,
            ...foregroundWidgets,
          ],
        );
      },
    );
  }

  static List<pw.Widget> _buildMerchandiseWidgets(
    _CmrMerchandiseData data, {
    required CmrLayout layout,
  }) {
    final widgets = <pw.Widget>[];
    final fields = ['6', '7', '8', '9', '11', '12'];
    if (layout.field('6') == null) {
      return widgets;
    }
    final rowHeight = _maxRowHeight(layout, fields);
    var currentOffsetY = 0.0;

    for (final row in data.rows) {
      final rowFields = [
        _MerchandiseField('6', row.marca),
        _MerchandiseField('7', row.totalCajas),
        _MerchandiseField('8', row.idConfeccion),
        _MerchandiseField('9', row.cultivo),
        _MerchandiseField('11', row.totalBruto),
        // _MerchandiseField('12', row.totalPalets),
      ];
      widgets.addAll(
        _buildMerchandiseRowWidgets(
          layout: layout,
          fields: rowFields,
          offsetY: currentOffsetY,
          rowHeight: rowHeight,
        ),
      );
      currentOffsetY += rowHeight;
    }

    widgets.addAll(
      _buildMerchandiseTotalsWidgets(
        data,
        layout: layout,
        currentOffsetY: currentOffsetY,
        rowHeight: rowHeight,
      ),
    );

    return widgets;
  }

  static List<pw.Widget> _buildMerchandiseTotalsWidgets(
    _CmrMerchandiseData data, {
    required CmrLayout layout,
    required double currentOffsetY,
    required double rowHeight,
  }) {
    if (data.rows.isEmpty) {
      return const [];
    }

    final rowStartField = layout.field('6');
    if (rowStartField == null) {
      return const [];
    }

    final widgets = <pw.Widget>[];
    final rowsBottomY = rowStartField.y + currentOffsetY;
    final tableBottom = layout.field('13')?.y ?? (rowsBottomY + rowHeight);
    final totalsY = min(rowsBottomY, tableBottom - rowHeight);

    final totalFields = [
      _MerchandiseField('7', _formatNum(data.totalCajas)),
      _MerchandiseField('11', _formatNum(data.totalBruto)),
      // _MerchandiseField('12', data.totalPalets.toString()),
    ];

    for (final field in totalFields) {
      final layoutField = layout.field(field.casilla);
      if (layoutField == null) continue;
      widgets.addAll(
        _renderField(
          layout,
          casilla: field.casilla,
          value: field.value,
          y: totalsY,
          height: rowHeight,
        ),
      );
    }

    return widgets;
  }

  static List<pw.Widget> _buildMerchandiseRowWidgets({
    required CmrLayout layout,
    required List<_MerchandiseField> fields,
    required double offsetY,
    required double rowHeight,
  }) {
    final widgets = <pw.Widget>[];
    for (final field in fields) {
      final layoutField = layout.field(field.casilla);
      if (layoutField == null) continue;
      widgets.addAll(
        _renderField(
          layout,
          casilla: field.casilla,
          value: field.value,
          y: layoutField.y + offsetY,
          height: rowHeight,
        ),
      );
    }
    return widgets;
  }

  static double _maxRowHeight(CmrLayout layout, List<String> casillas) {
    var maxHeight = 0.0;
    for (final casilla in casillas) {
      final field = layout.field(casilla);
      if (field == null) continue;
      maxHeight = max(maxHeight, field.height);
    }
    return maxHeight;
  }

  static List<pw.Widget> _renderField(
    CmrLayout layout, {
    required String casilla,
    required String value,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    final field = layout.field(casilla);
    if (field == null) {
      return const [];
    }

    final effectiveField = field.copyWith(
      x: x,
      y: y,
      width: width,
      height: height,
    );

    final maxLines = effectiveField.multiline
        ? max(1, (effectiveField.height / effectiveField.lineHeight).floor())
        : 1;

    return [
      pw.Positioned(
        left: effectiveField.x,
        top: effectiveField.y,
        child: pw.ClipRect(
          child: pw.SizedBox(
            width: effectiveField.width,
            height: effectiveField.height,
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: effectiveField.fontSize),
              maxLines: maxLines,
              overflow: pw.TextOverflow.clip,
              softWrap: effectiveField.multiline,
            ),
          ),
        ),
      ),
    ];
  }

  static List<pw.Widget> _buildCmrValueWidgets(
    Map<String, String> values,
    CmrLayout layout,
  ) {
    final widgets = <pw.Widget>[];
    for (final field in layout.fields) {
      final value = values[field.casilla] ?? '';
      if (value.trim().isEmpty) {
        continue;
      }
      widgets.addAll(
        _renderField(
          layout,
          casilla: field.casilla,
          value: value,
        ),
      );
    }
    return widgets;
  }

  static Future<CmrLayout> _loadLayout() {
    _layoutCache ??= CmrLayoutLoader.loadFromAssets();
    return _layoutCache!;
  }

  static Map<String, List<CmrPedidoLine>> _groupLineasByPlataforma(
    CmrPedido pedido,
  ) {
    final grouped = <String, List<CmrPedidoLine>>{};
    for (final linea in pedido.lineas) {
      final plataforma = linea.plataforma?.trim() ?? '';
      grouped.putIfAbsent(plataforma, () => []).add(linea);
    }

    if (grouped.isEmpty) {
      // Sin líneas no debemos crear una plataforma ficticia para evitar CMR vacíos.
    }

    return grouped;
  }

  static String _resolvePlataforma(String plataforma, CmrPedido pedido) {
    final trimmed = plataforma.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return _fallbackPlataforma(pedido);
  }

  static String _platformSortKey(String plataforma, CmrPedido pedido) {
    return _resolvePlataforma(plataforma, pedido).toLowerCase();
  }

  static String _fallbackPlataforma(CmrPedido pedido) {
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
    required List<CmrPedidoLine> lineas,
    required FirebaseFirestore firestore,
  }) async {
    final paletIds = parsePaletsFromLines(
      lineas.expand((linea) => linea.palets),
    );
    if (paletIds.isEmpty) {
      return const _CmrMerchandiseData.empty();
    }

    final grouped = <_MerchandiseKey, _MerchandiseGroup>{};
    final confeccionCache = <String, String>{};
    for (final paletId in paletIds) {
      final stockDocId = buildStockDocId(paletId);
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
      final bruto =
          _numFromKeys(data, const ['BRUTO', 'Bruto', 'bruto']) ?? 0;

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
      group.totalBruto += bruto;
      group.rowPalets += 1;
    }

    if (grouped.isEmpty) {
      return const _CmrMerchandiseData.empty();
    }

    num totalCajas = 0;
    num totalBruto = 0;
    var totalPalets = 0;

    final rows = grouped.values.map((group) {
      final rowPalets = group.rowPalets;
      totalCajas += group.totalCajas;
      totalBruto += group.totalBruto;
      totalPalets += rowPalets;
      return _CmrMerchandiseRow(
        marca: group.marca,
        idConfeccion: group.confeccionDescripcion.isNotEmpty
            ? group.confeccionDescripcion
            : group.idConfeccion,
        cultivo: group.cultivo,
        totalCajas: _formatNum(group.totalCajas),
        totalBruto: _formatNum(group.totalBruto),
        totalPalets: rowPalets.toString(),
      );
    }).toList();

    return _CmrMerchandiseData(
      rows: rows,
      totalCajas: totalCajas,
      totalBruto: totalBruto,
      totalPalets: totalPalets,
    );
  }

  static String _resolveTipoPalet(List<CmrPedidoLine> lineas) {
    final tipoPalets = lineas
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

  static Map<String, String> buildCmrFieldValues(CmrPedido pedido) {
    return {
      '1': pedido.remitente,
      '2': pedido.cliente,
      '3': _fallbackPlataforma(pedido),
      '5': pedido.termografos,
      '13': pedido.observaciones,
      '17': [
        pedido.transportista,
        pedido.matricula,
      ].where((value) => value.trim().isNotEmpty).join('\n'),
      '26A': 'Palets Retornables Entregados: ${pedido.paletRetDev.trim()}',
      '26B': 'Palets Retornables Devueltos: ${pedido.paletRetEntr.trim()}',
      '27': _resolveTipoPalet(pedido.lineas),
    };
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
    required this.totalBruto,
    required this.totalPalets,
  });

  const _CmrMerchandiseData.empty()
      : rows = const [],
        totalCajas = 0,
        totalBruto = 0,
        totalPalets = 0;

  final List<_CmrMerchandiseRow> rows;
  final num totalCajas;
  final num totalBruto;
  final int totalPalets;
}

class _CmrMerchandiseRow {
  const _CmrMerchandiseRow({
    required this.marca,
    required this.idConfeccion,
    required this.cultivo,
    required this.totalCajas,
    required this.totalBruto,
    required this.totalPalets,
  });

  final String marca;
  final String idConfeccion;
  final String cultivo;
  final String totalCajas;
  final String totalBruto;
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
  num totalBruto = 0;
  int rowPalets = 0;
}
