import 'package:flutter/services.dart';

class CmrFieldLayout {
  const CmrFieldLayout({
    required this.casilla,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String casilla;
  final double x;
  final double y;
  final double width;
  final double height;
}

class CmrLayoutMap {
  const CmrLayoutMap(this._fields);

  final Map<String, CmrFieldLayout> _fields;

  CmrFieldLayout? getField(String casilla) => _fields[casilla];
}

class CmrLayoutLoader {
  static const _defaultWidth = 70.0;
  static const _defaultHeight = 14.0;

  static Future<CmrLayoutMap> loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/cmr/Parametroscmr.csv');
    final fields = <String, CmrFieldLayout>{};
    final lines = raw.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(';').map((value) => value.trim()).toList();
      if (parts.isEmpty) continue;

      final casilla = parts[0];
      if (casilla.isEmpty || _isHeaderRow(casilla)) {
        continue;
      }

      final x = _parseDouble(parts, 3);
      final y = _parseDouble(parts, 4);
      if (x == null || y == null) {
        continue;
      }

      final boxRight = _parseDouble(parts, 5);
      final boxBottom = _parseDouble(parts, 6);
      final width = _computeSize(
        start: x,
        end: boxRight,
        fallback: _defaultWidth,
      );
      final height = _computeSize(
        start: y,
        end: boxBottom,
        fallback: _defaultHeight,
      );

      fields[casilla] = CmrFieldLayout(
        casilla: casilla,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    return CmrLayoutMap(fields);
  }

  static bool _isHeaderRow(String value) {
    final lower = value.toLowerCase();
    return lower.contains('casilla') || lower.contains('id');
  }

  static double? _parseDouble(List<String> parts, int index) {
    if (index >= parts.length) return null;
    final raw = parts[index];
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  static double _computeSize({
    required double start,
    required double? end,
    required double fallback,
  }) {
    if (end == null) return fallback;
    final size = end - start;
    if (size <= 0) return fallback;
    return size;
  }
}
