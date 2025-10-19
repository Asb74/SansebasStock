class PalletQr {
  PalletQr({required this.palletId, required this.extras});

  final String palletId;
  final PalletExtras extras;

  Map<String, dynamic> toJson() => {
        'palletId': palletId,
        'extras': extras.toJson(),
      };
}

class PalletExtras {
  PalletExtras({required this.lineas});

  final List<PalletLine> lineas;

  Map<String, dynamic> toJson() => {
        'lineas': lineas.map((linea) => linea.toJson()).toList(),
      };
}

class PalletLine {
  PalletLine({
    required this.n,
    this.cult,
    this.variedad,
    this.idc,
    this.conf,
    this.cal,
    this.cat,
    this.cajas,
    this.neto,
    this.lin,
  });

  final int? n;
  final String? cult;
  final String? variedad;
  final String? idc;
  final String? conf;
  final String? cal;
  final String? cat;
  final int? cajas;
  final double? neto;
  final int? lin;

  Map<String, dynamic> toJson() => {
        'n': n,
        'CULT': cult,
        'VAR': variedad,
        'IDC': idc,
        'CONF': conf,
        'CAL': cal,
        'CAT': cat,
        'CAJAS': cajas,
        'NETO': neto,
        'LIN': lin,
      };
}

PalletQr parseQr(String rawValue) {
  final content = rawValue.trim();
  if (content.isEmpty) {
    throw const FormatException('Código vacío');
  }

  final segments = content.split('^#');
  if (segments.isEmpty || !segments.first.startsWith('P=')) {
    throw const FormatException('Formato de palet no válido');
  }

  final palletId = segments.first.substring(2).trim();
  if (palletId.isEmpty) {
    throw const FormatException('ID de palet no válido');
  }

  final List<PalletLine> lines = <PalletLine>[];

  for (var i = 1; i < segments.length; i++) {
    final segment = segments[i].trim();
    if (segment.isEmpty) {
      continue;
    }

    final tokens = segment.split('|');
    if (tokens.isEmpty) {
      continue;
    }

    int? lineNumber;
    final Map<String, dynamic> values = <String, dynamic>{};

    for (final token in tokens) {
      final trimmedToken = token.trim();
      if (trimmedToken.isEmpty) {
        continue;
      }

      if (!trimmedToken.contains('=')) {
        lineNumber ??= int.tryParse(trimmedToken);
        continue;
      }

      final keyValue = trimmedToken.split('=');
      if (keyValue.length < 2) {
        continue;
      }

      final key = keyValue.first.trim().toUpperCase();
      final value = keyValue.sublist(1).join('=').trim();
      final normalizedValue = value.toLowerCase() == 'null' ? null : value;

      values[key] = normalizedValue;
    }

    if (values.isEmpty && lineNumber == null) {
      continue;
    }

    final line = PalletLine(
      n: lineNumber ?? _parseInt(values['N']),
      cult: values['CULT'] as String?,
      variedad: values['VAR'] as String?,
      idc: values['IDC'] as String?,
      conf: values['CONF'] as String?,
      cal: values['CAL'] as String?,
      cat: values['CAT'] as String?,
      cajas: _parseInt(values['CAJAS']),
      neto: _parseDouble(values['NETO']),
      lin: _parseInt(values['LIN']),
    );

    lines.add(line);
  }

  if (lines.isEmpty) {
    throw const FormatException('No se encontraron líneas válidas.');
  }

  return PalletQr(
    palletId: palletId,
    extras: PalletExtras(lineas: lines),
  );
}

int? _parseInt(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}

double? _parseDouble(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  return null;
}
