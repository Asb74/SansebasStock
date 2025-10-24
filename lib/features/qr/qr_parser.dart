import 'dart:collection';

class Ubicacion {
  const Ubicacion({
    required this.camara,
    required this.estanteria,
    required this.nivel,
  });

  final String camara;
  final String estanteria;
  final String nivel;

  String get etiqueta => 'C$camara-E$estanteria-N$nivel';
}

class PaletQr {
  PaletQr({
    required this.paletId,
    required this.lineas,
    required Map<String, String> campos,
  }) : campos = UnmodifiableMapView<String, String>(
            Map<String, String>.from(campos),
          );

  final String paletId;
  final int lineas;
  final Map<String, String> campos;

  String get docId {
    final linea = campos['LINEA'];
    if (linea == null || linea.isEmpty) {
      throw StateError('Campo LINEA ausente para calcular docId.');
    }
    return '$linea$paletId';
  }
}

Ubicacion parseUbicacionQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('QR de ubicación no válido.');
  }

  String? camara;
  String? estanteria;
  String? nivel;

  final segments = trimmed.split('|');
  for (final segment in segments) {
    final token = segment.trim();
    if (token.isEmpty || token == '#') {
      continue;
    }

    final separatorIndex = token.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final key = token.substring(0, separatorIndex).trim().toUpperCase();
    final value = token.substring(separatorIndex + 1).trim();

    switch (key) {
      case 'CAMARA':
        camara = value;
        break;
      case 'ESTANTERIA':
        estanteria = value;
        break;
      case 'NIVEL':
        nivel = value;
        break;
    }
  }

  if (camara == null || estanteria == null || nivel == null) {
    throw const FormatException('QR de ubicación no válido.');
  }

  return Ubicacion(camara: camara!, estanteria: estanteria!, nivel: nivel!);
}

PaletQr parsePaletQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('QR de palet no válido (cabecera).');
  }

  final headerRegExp = RegExp(r'^P=([^^]+)\^#(\d+)(.*)$');
  final match = headerRegExp.firstMatch(trimmed);
  if (match == null) {
    throw const FormatException('QR de palet no válido (cabecera).');
  }

  final paletId = match.group(1)!.trim();
  final lineasStr = match.group(2)!.trim();
  final lineas = int.tryParse(lineasStr);
  if (paletId.isEmpty || lineas == null) {
    throw const FormatException('QR de palet no válido (cabecera).');
  }

  final body = (match.group(3) ?? '').replaceAll('^#', '|');
  final campos = <String, String>{};

  final tokens = body.split('|');
  for (final token in tokens) {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      continue;
    }

    final separatorIndex = trimmedToken.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final rawKey =
        trimmedToken.substring(0, separatorIndex).trim().toUpperCase();
    final key = _normalizePaletKey(rawKey);
    final value = trimmedToken.substring(separatorIndex + 1).trim();

    if (key.isEmpty) {
      continue;
    }

    campos[key] = value;
  }

  if (!campos.containsKey('LINEA') || campos['LINEA']!.isEmpty) {
    throw const FormatException('QR de palet no válido (falta LINEA).');
  }

  return PaletQr(paletId: paletId, lineas: lineas, campos: campos);
}

String _normalizePaletKey(String key) {
  switch (key) {
    case 'LIN':
      return 'LINEA';
    case 'CAL':
      return 'CALIBRE';
    case 'CAT':
      return 'CATEGORIA';
    default:
      return key;
  }
}

// Devuelve solo los dígitos de una cadena (ej: "2026001331^#1" -> "2026001331").
String onlyDigits(String? v) {
  if (v == null) return '';
  final it = RegExp(r'\d+').allMatches(v);
  return it.map((m) => m.group(0)!).join();
}
