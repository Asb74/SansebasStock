import 'package:flutter/services.dart';

class CmrFieldLayout {
  const CmrFieldLayout({
    required this.casilla,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.lineHeight,
    required this.multiline,
  });

  final String casilla;
  final double x;
  final double y;
  final double width;
  final double height;
  final double fontSize;
  final double lineHeight;
  final bool multiline;

  CmrFieldLayout copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return CmrFieldLayout(
      casilla: casilla,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fontSize: fontSize,
      lineHeight: lineHeight,
      multiline: multiline,
    );
  }
}

class CmrLayout {
  const CmrLayout(this._fields);

  final Map<String, CmrFieldLayout> _fields;

  CmrFieldLayout? field(String casilla) => _fields[casilla];

  Iterable<CmrFieldLayout> get fields => _fields.values;
}

class CmrLayoutLoader {
  static const _defaultFontSize = 8.0;
  static const _defaultLineHeight = 9.0;

  static Future<CmrLayout> loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/cmr/Parametroscmr.csv');
    final lines = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) {
      return const CmrLayout({});
    }

    final header = _splitCsvLine(lines.first);
    final columnIndex = _buildColumnIndex(header);
    final fields = <String, CmrFieldLayout>{};

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = _splitCsvLine(line);
      final casilla = _valueForColumn(parts, columnIndex, 'casilla');
      if (casilla.isEmpty) continue;

      final x = _parseDouble(_valueForColumn(parts, columnIndex, 'x_pt'));
      final y = _parseDouble(_valueForColumn(parts, columnIndex, 'y_pt'));
      final width =
          _parseDouble(_valueForColumn(parts, columnIndex, 'width_pt'));
      final height =
          _parseDouble(_valueForColumn(parts, columnIndex, 'height_pt'));
      if (x == null || y == null || width == null || height == null) {
        continue;
      }

      final fontSize = _parseDouble(
            _valueForColumn(parts, columnIndex, 'fontsize'),
          ) ??
          _defaultFontSize;
      final lineHeight = _parseDouble(
            _valueForColumn(parts, columnIndex, 'lineheight'),
          ) ??
          _defaultLineHeight;
      final multiline =
          _parseBool(_valueForColumn(parts, columnIndex, 'multiline'));

      fields[casilla] = CmrFieldLayout(
        casilla: casilla,
        x: x,
        y: y,
        width: width,
        height: height,
        fontSize: fontSize,
        lineHeight: lineHeight,
        multiline: multiline,
      );
    }

    return CmrLayout(fields);
  }

  static List<String> _splitCsvLine(String line) {
    return line.split(';').map((value) => value.trim()).toList();
  }

  static Map<String, int> _buildColumnIndex(List<String> header) {
    final index = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final key = _normalizeHeader(header[i]);
      if (key.isEmpty) continue;
      index[key] = i;
    }
    return index;
  }

  static String _normalizeHeader(String value) {
    final lower = value.toLowerCase();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .replaceAll('ptos', 'pt')
        .replaceAll('puntos', 'pt');
  }

  static String _valueForColumn(
    List<String> parts,
    Map<String, int> index,
    String column,
  ) {
    final normalized = _normalizeHeader(column);
    final colIndex = index[normalized];
    if (colIndex == null || colIndex >= parts.length) return '';
    return parts[colIndex];
  }

  static double? _parseDouble(String raw) {
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  static bool _parseBool(String raw) {
    final value = raw.trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'si' || value == 'sí';
  }
}
