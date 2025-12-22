import 'package:cloud_firestore/cloud_firestore.dart';

class CmrPedidoLine {
  CmrPedidoLine({
    required this.linea,
    required this.plataforma,
    required this.tipoPalet,
    required this.paletRaw,
  });

  final int? linea;
  final String? plataforma;
  final String? tipoPalet;
  final String? paletRaw;

  List<String> get palets {
    if (paletRaw == null || paletRaw!.trim().isEmpty) {
      return const [];
    }
    return paletRaw!
        .split('|')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }
}

class CmrPedido {
  CmrPedido({
    required this.ref,
    required this.id,
    required this.estado,
    required this.idPedidoLora,
    required this.idPedidoCliente,
    required this.cliente,
    required this.comercializador,
    required this.remitente,
    required this.fechaSalida,
    required this.expedidoAt,
    required this.transportista,
    required this.matricula,
    required this.termografos,
    required this.observaciones,
    required this.paletRetEntr,
    required this.paletRetDev,
    required this.lineas,
    required this.raw,
  });

  factory CmrPedido.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawLineas = data['Lineas'];
    final List<CmrPedidoLine> lineas = [];
    if (rawLineas is Iterable) {
      for (final item in rawLineas) {
        if (item is Map) {
          lineas.add(
            CmrPedidoLine(
              linea: _asInt(item['Linea']),
              plataforma: item['Plataforma']?.toString(),
              tipoPalet: item['TipoPalet']?.toString(),
              paletRaw: item['Palet']?.toString(),
            ),
          );
        }
      }
    }

    return CmrPedido(
      ref: snapshot.reference,
      id: snapshot.id,
      estado: data['Estado']?.toString() ?? '',
      idPedidoLora: data['IdPedidoLora']?.toString() ?? '',
      idPedidoCliente: data['IdPedidoCliente']?.toString() ?? '',
      cliente: data['Cliente']?.toString() ?? '',
      comercializador: data['Comercializador']?.toString() ?? '',
      remitente: data['Remitente']?.toString() ?? '',
      fechaSalida: _asDate(data['FechaSalida']),
      expedidoAt: _asDate(data['expedidoAt']),
      transportista: data['Transportista']?.toString() ?? '',
      matricula: data['Matricula']?.toString() ?? '',
      termografos: data['Termografos']?.toString() ?? '',
      observaciones: data['Observaciones']?.toString() ?? '',
      paletRetEntr: data['PaletRetEntr']?.toString() ?? '',
      paletRetDev: data['PaletRetDev']?.toString() ?? '',
      lineas: lineas,
      raw: Map<String, dynamic>.from(data),
    );
  }

  final DocumentReference<Map<String, dynamic>> ref;
  final String id;
  final String estado;
  final String idPedidoLora;
  final String idPedidoCliente;
  final String cliente;
  final String comercializador;
  final String remitente;
  final DateTime? fechaSalida;
  final DateTime? expedidoAt;
  final String transportista;
  final String matricula;
  final String termografos;
  final String observaciones;
  final String paletRetEntr;
  final String paletRetDev;
  final List<CmrPedidoLine> lineas;
  final Map<String, dynamic> raw;
}

class CmrScanResult {
  const CmrScanResult({
    required this.scanned,
    required this.invalid,
  });

  final Set<String> scanned;
  final Set<String> invalid;
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}
