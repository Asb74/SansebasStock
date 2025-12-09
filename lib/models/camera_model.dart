import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum CameraPasillo { central, lateral }

extension CameraPasilloX on CameraPasillo {
  String get label {
    switch (this) {
      case CameraPasillo.central:
        return 'Central';
      case CameraPasillo.lateral:
        return 'Lateral';
    }
  }

  String get asFirestoreValue => label;

  static CameraPasillo fromString(String? value) {
    if (value == null) {
      return CameraPasillo.central;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'lateral') {
      return CameraPasillo.lateral;
    }
    return CameraPasillo.central;
  }
}

enum CameraTipo { expedicion, recepcion }

extension CameraTipoX on CameraTipo {
  String get label {
    switch (this) {
      case CameraTipo.expedicion:
        return 'Expedición';
      case CameraTipo.recepcion:
        return 'Recepción';
    }
  }

  String get firestoreValue {
    switch (this) {
      case CameraTipo.expedicion:
        return 'expedicion';
      case CameraTipo.recepcion:
        return 'recepcion';
    }
  }

  static CameraTipo fromFirestore(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'recepcion':
        return CameraTipo.recepcion;
      case 'expedicion':
      default:
        return CameraTipo.expedicion;
    }
  }
}

class CameraModel extends Equatable {
  const CameraModel({
    required this.id,
    required this.numero,
    required this.filas,
    required this.niveles,
    required this.pasillo,
    required this.posicionesMax,
    required this.tipo,
    this.createdAt,
    this.updatedAt,
  });

  factory CameraModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final numero = _readNumero(data['numero'] ?? data['CAMARA'] ?? doc.id);
    final filas = _readPositiveInt(data['filas'] ?? data['ESTANTERIAS']);
    final niveles = _readPositiveInt(data['niveles'] ?? data['NIVELES']);
    final posicionesMax =
        _readPositiveInt(data['posicionesMax'] ?? data['HUECOS_POR_ESTANTERIA']);
    final pasillo = CameraPasilloX.fromString(data['pasillo']?.toString());
    final tipo = CameraTipoX.fromFirestore(data['tipo'] as String?);

    DateTime? createdAt;
    final rawCreated = data['createdAt'];
    if (rawCreated is Timestamp) {
      createdAt = rawCreated.toDate();
    }
    DateTime? updatedAt;
    final rawUpdated = data['updatedAt'];
    if (rawUpdated is Timestamp) {
      updatedAt = rawUpdated.toDate();
    }

    return CameraModel(
      id: doc.id,
      numero: numero,
      filas: filas,
      niveles: niveles,
      pasillo: pasillo,
      posicionesMax: posicionesMax,
      tipo: tipo,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  final String id;
  final String numero;
  final int filas;
  final int niveles;
  final CameraPasillo pasillo;
  final int posicionesMax;
  final CameraTipo tipo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayNumero => numero.padLeft(2, '0');

  Map<String, dynamic> toMap() {
    if (filas <= 0 || niveles <= 0 || posicionesMax <= 0) {
      throw ArgumentError('filas, niveles y posicionesMax deben ser mayores que 0.');
    }
    if (numero.length != 2 || int.tryParse(numero) == null) {
      throw ArgumentError('numero debe tener exactamente 2 dígitos.');
    }

    return <String, dynamic>{
      'numero': displayNumero,
      'filas': filas,
      'niveles': niveles,
      'pasillo': pasillo.asFirestoreValue,
      'posicionesMax': posicionesMax,
      'tipo': tipo.firestoreValue,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  CameraModel copyWith({
    String? id,
    String? numero,
    int? filas,
    int? niveles,
    CameraPasillo? pasillo,
    int? posicionesMax,
    CameraTipo? tipo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CameraModel(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      filas: filas ?? this.filas,
      niveles: niveles ?? this.niveles,
      pasillo: pasillo ?? this.pasillo,
      posicionesMax: posicionesMax ?? this.posicionesMax,
      tipo: tipo ?? this.tipo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _readNumero(dynamic value) {
    final raw = value?.toString() ?? '';
    final match = RegExp(r'\d+').firstMatch(raw);
    final digits = match?.group(0) ?? raw;
    if (digits.isEmpty) {
      return '00';
    }
    final normalized = digits.length >= 2
        ? digits.substring(digits.length - 2)
        : digits.padLeft(2, '0');
    return int.tryParse(normalized) == null ? '00' : normalized;
  }

  static int _readPositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : 0;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      return 0;
    }
    return parsed;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        numero,
        filas,
        niveles,
        pasillo,
        posicionesMax,
        tipo,
        createdAt,
        updatedAt,
      ];
}
