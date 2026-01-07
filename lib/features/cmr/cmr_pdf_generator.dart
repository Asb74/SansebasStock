import 'dart:math';
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

class CmrPdfGenerator {
  static Future<CmrLayout>? _layoutCache;
  static final PdfDocument _fontDocument = PdfDocument();
  static final PdfFont _defaultFont = PdfFont.helvetica(_fontDocument);

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
    for (final entry in plataformas.entries) {
      final lineas = entry.value;
      final plataforma = entry.key.isNotEmpty
          ? entry.key
          : _fallbackPlataforma(pedido);
      final paletsExpedidos = parsePaletsFromLines(
        lineas.expand((linea) => linea.palets),
      );
      final merchandiseData = await _buildMerchandiseRows(
        lineas: lineas,
        firestore: store,
      );
      final tipoPalet = _resolveTipoPalet(lineas);
      final cmrValues = buildCmrValues(
        pedido: pedido,
        paletsExpedidos: paletsExpedidos,
        remitente: remitenteLines.join('\n'),
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
      );

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
          background: destinatarioBg,
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
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(background, fit: pw.BoxFit.fill),
            ),
            ..._buildCmrValueWidgets(cmrValues, layout),
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
    required CmrLayout layout,
  }) {
    final widgets = <pw.Widget>[];
    final fields = ['6', '7', '8', '9', '11', '12'];
    final baseField = layout.field('6');
    if (baseField == null) {
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
        _MerchandiseField('11', row.totalNeto),
        _MerchandiseField('12', row.totalPalets),
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

    if (data.rows.isNotEmpty) {
      final totalFields = [
        _MerchandiseField('7', _formatNum(data.totalCajas)),
        _MerchandiseField('11', _formatNum(data.totalNeto)),
        _MerchandiseField('12', data.totalPalets.toString()),
      ];
      widgets.addAll(
        _buildMerchandiseRowWidgets(
          layout: layout,
          fields: totalFields,
          offsetY: currentOffsetY,
          rowHeight: rowHeight,
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

    if (effectiveField.multiline) {
      return _renderMultilineText(effectiveField, value);
    }

    final truncated = _truncateToWidth(
      value,
      field: effectiveField,
      font: _defaultFont,
    );

    return [
      pw.Positioned(
        left: effectiveField.x,
        top: effectiveField.y,
        child: pw.ClipRect(
          child: pw.SizedBox(
            width: effectiveField.width,
            height: effectiveField.height,
            child: pw.Text(
              truncated,
              style: pw.TextStyle(fontSize: effectiveField.fontSize),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              softWrap: false,
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
      if (field.casilla == '13' || field.casilla == '27') {
        widgets.addAll(_renderFixedCharMultiline(field, value));
      } else {
        widgets.addAll(
          _renderField(
            layout,
            casilla: field.casilla,
            value: value,
          ),
        );
      }
    }
    return widgets;
  }

  static List<pw.Widget> _renderMultilineText(
    CmrFieldLayout field,
    String text,
  ) {
    final maxLines = max(1, (field.height / field.lineHeight).floor());
    final lines = _splitTextToLines(
      text,
      field: field,
      font: _defaultFont,
      maxLines: maxLines,
    );

    return [
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
        pw.Positioned(
          left: field.x,
          top: field.y + (lineIndex * field.lineHeight),
          child: pw.SizedBox(
            width: field.width,
            height: field.lineHeight,
            child: pw.Text(
              lines[lineIndex],
              style: pw.TextStyle(fontSize: field.fontSize),
            ),
          ),
        ),
    ];
  }

  static List<String> _splitTextToLines(
    String text, {
    required CmrFieldLayout field,
    required PdfFont font,
    required int maxLines,
  }) {
    if (text.isEmpty) {
      return const [''];
    }

    final lines = <String>[];
    final buffer = StringBuffer();
    for (final char in text.characters) {
      if (char == '\n') {
        lines.add(buffer.toString());
        buffer.clear();
        if (lines.length >= maxLines) {
          return lines;
        }
        continue;
      }

      final candidate = '${buffer.toString()}$char';
      if (_measureTextWidth(candidate, font, field.fontSize) <= field.width ||
          buffer.isEmpty) {
        buffer.write(char);
      } else {
        lines.add(buffer.toString());
        buffer.clear();
        buffer.write(char);
        if (lines.length >= maxLines) {
          return lines;
        }
      }
    }

    if (buffer.isNotEmpty && lines.length < maxLines) {
      lines.add(buffer.toString());
    }

    return lines;
  }

  static List<pw.Widget> _renderFixedCharMultiline(
    CmrFieldLayout field,
    String text,
  ) {
    final maxLines = max(1, (field.height / field.lineHeight).floor());
    final maxChars = _maxCharsForWidth(field);
    final lines = _splitByCharCount(
      text,
      maxChars: maxChars,
      maxLines: maxLines,
    );

    return [
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
        pw.Positioned(
          left: field.x,
          top: field.y + (lineIndex * field.lineHeight),
          child: pw.SizedBox(
            width: field.width,
            height: field.lineHeight,
            child: pw.Text(
              lines[lineIndex],
              style: pw.TextStyle(fontSize: field.fontSize),
            ),
          ),
        ),
    ];
  }

  static int _maxCharsForWidth(CmrFieldLayout field) {
    final sampleWidth = _measureTextWidth('M', _defaultFont, field.fontSize);
    if (sampleWidth <= 0) {
      return 1;
    }
    return max(1, (field.width / sampleWidth).floor());
  }

  static List<String> _splitByCharCount(
    String text, {
    required int maxChars,
    required int maxLines,
  }) {
    if (text.isEmpty) {
      return const [];
    }

    final lines = <String>[];
    final buffer = StringBuffer();
    var count = 0;
    for (final char in text.characters) {
      if (char == '\n') {
        lines.add(buffer.toString());
        buffer.clear();
        count = 0;
        if (lines.length >= maxLines) {
          return lines;
        }
        continue;
      }

      if (count >= maxChars) {
        lines.add(buffer.toString());
        buffer.clear();
        count = 0;
        if (lines.length >= maxLines) {
          return lines;
        }
      }

      buffer.write(char);
      count += 1;
    }

    if (buffer.isNotEmpty && lines.length < maxLines) {
      lines.add(buffer.toString());
    }

    return lines;
  }

  static String _truncateToWidth(
    String text, {
    required CmrFieldLayout field,
    required PdfFont font,
  }) {
    if (text.isEmpty) {
      return text;
    }
    if (_measureTextWidth(text, font, field.fontSize) <= field.width) {
      return text;
    }

    final buffer = StringBuffer();
    for (final char in text.characters) {
      final candidate = '${buffer.toString()}$char';
      if (_measureTextWidth(candidate, font, field.fontSize) <= field.width ||
          buffer.isEmpty) {
        buffer.write(char);
      } else {
        break;
      }
    }
    return buffer.toString();
  }

  static double _measureTextWidth(
    String text,
    PdfFont font,
    double fontSize,
  ) {
    final metrics = font.stringMetrics(text);
    return metrics.width * fontSize;
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
      final fallback = _fallbackPlataforma(pedido);
      grouped[fallback] = [];
    }

    return grouped;
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
      final neto = _numFromKeys(data, const ['NETO', 'Neto', 'neto']) ?? 0;

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

  static Map<String, String> buildCmrValues({
    required CmrPedido pedido,
    required List<String> paletsExpedidos,
    String? remitente,
    String? destinatario,
    String? plataforma,
    String? almacen,
    String? fechaSalida,
    String? almacenLocation,
    String? almacenPoblacion,
    String? transportista,
    String? matricula,
    String? termografos,
    String? observaciones,
    String? paletRetEntr,
    String? paletRetDev,
    String? tipoPalet,
  }) {
    final resolvedFechaSalida = fechaSalida ?? _formatFecha(pedido.fechaSalida);
    final remitenteText = remitente ?? pedido.remitente;
    final destinatarioText = destinatario ?? pedido.cliente;
    final plataformaText = plataforma ?? _fallbackPlataforma(pedido);
    final almacenText = almacen ?? '';
    final almacenLocText = almacenLocation ?? '';
    final almacenLine = [
      almacenText,
      resolvedFechaSalida,
    ].where((value) => value.trim().isNotEmpty).join('        ');
    final casilla4 = [
      almacenLine,
      almacenLocText,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final transportistaText = transportista ?? pedido.transportista;
    final matriculaText = matricula ?? pedido.matricula;
    final transportistaLine = [
      transportistaText,
      matriculaText,
    ].where((value) => value.trim().isNotEmpty).join('\n');

    return {
      '1': remitenteText,
      '2': destinatarioText,
      '3': plataformaText,
      '4': casilla4,
      '5': termografos ?? pedido.termografos,
      '12': paletsExpedidos.isNotEmpty ? paletsExpedidos.length.toString() : '',
      '13': observaciones ?? pedido.observaciones,
      '17': transportistaLine,
      '22A': almacenPoblacion ?? '',
      '22B': resolvedFechaSalida,
      '26A':
          'Palets Retornables Entregados: ${paletRetDev ?? pedido.paletRetDev}',
      '26B':
          'Palets Retornables Devueltos: ${paletRetEntr ?? pedido.paletRetEntr}',
      '27': tipoPalet ?? _resolveTipoPalet(pedido.lineas),
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
