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

class ParsedQr {
  ParsedQr({
    required this.p,
    required this.linea,
    required this.cajas,
    required this.neto,
    required this.nivel,
    required this.posicion,
    required this.vida,
    required this.lineas,
    required Map<String, dynamic> data,
    required Map<String, String> rawFields,
  })  : data = UnmodifiableMapView(Map<String, dynamic>.from(data)),
        rawFields = UnmodifiableMapView(Map<String, String>.from(rawFields));

  final int p;
  final int linea;
  final int cajas;
  final int neto;
  final int nivel;
  final int posicion;
  final String vida;
  final int lineas;
  final Map<String, dynamic> data;
  final Map<String, String> rawFields;

  Map<String, dynamic> toData() => Map<String, dynamic>.from(data);
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

ParsedQr parseQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('QR de palet no válido.');
  }

  final pMatch = RegExp(r'P=([0-9]{10})').firstMatch(trimmed);
  if (pMatch == null) {
    throw const FormatException('P no encontrado');
  }
  final int p = int.parse(pMatch.group(1)!);

  final lineaMatch = RegExp(r'\|LINEA=(\d+)(?:\||$)').firstMatch('$trimmed|');
  if (lineaMatch == null) {
    throw const FormatException('LINEA no encontrada');
  }
  final int linea = int.parse(lineaMatch.group(1)!);

  final lineasMatch = RegExp(r'\^#(\d+)').firstMatch(trimmed);
  final int lineas =
      lineasMatch != null ? int.tryParse(lineasMatch.group(1)!.trim()) ?? 0 : 0;

  final normalized = trimmed.replaceAll('^#', '|');
  final tokens = normalized.split('|');

  final Map<String, String> rawFields = <String, String>{};

  for (final token in tokens) {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty || trimmedToken == '#') {
      continue;
    }

    final separatorIndex = trimmedToken.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final key =
        trimmedToken.substring(0, separatorIndex).trim().toUpperCase();
    final value = trimmedToken.substring(separatorIndex + 1).trim();

    if (key.isEmpty || value.isEmpty) {
      continue;
    }

    rawFields[key] = value;
  }

  rawFields['P'] = p.toString();
  rawFields['LINEA'] = linea.toString();

  int _intField(String? value) => int.tryParse(value?.trim() ?? '') ?? 0;
  String _stringField(String? value) => value?.trim() ?? '';

  final int cajas = _intField(rawFields['CAJAS']);
  final int neto = _intField(rawFields['NETO']);
  final int nivel = _intField(rawFields['NIVEL']);
  final int posicion = _intField(rawFields['POSICION']);
  final String vida = _stringField(rawFields['VIDA']);

  final Map<String, dynamic> data = <String, dynamic>{
    'P': p,
    'LINEA': linea,
    'CAJAS': cajas,
    'NETO': neto,
    'NIVEL': nivel,
    'POSICION': posicion,
    'VIDA': vida,
  };

  rawFields.forEach((key, value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return;
    }

    switch (key) {
      case 'P':
      case 'LINEA':
      case 'CAJAS':
      case 'NETO':
      case 'NIVEL':
      case 'POSICION':
        data[key] = _intField(trimmedValue);
        break;
      case 'VIDA':
        data[key] = _stringField(trimmedValue);
        break;
      default:
        data[key] = trimmedValue;
    }
  });

  return ParsedQr(
    p: p,
    linea: linea,
    cajas: cajas,
    neto: neto,
    nivel: nivel,
    posicion: posicion,
    vida: vida,
    lineas: lineas,
    data: data,
    rawFields: rawFields,
  );
}
