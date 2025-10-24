import 'package:cloud_firestore/cloud_firestore.dart';

class CameraStorage {
  const CameraStorage({
    required this.camara,
    required this.estanterias,
    required this.niveles,
    required this.huecosPorEstanteria,
    this.createdAt,
    this.updatedAt,
  });

  final String camara;
  final int estanterias;
  final int niveles;
  final int huecosPorEstanteria;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CameraStorage.fromMap(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    return CameraStorage(
      camara: data['CAMARA'] as String,
      estanterias: (data['ESTANTERIAS'] as num?)?.toInt() ?? 0,
      niveles: (data['NIVELES'] as num?)?.toInt() ?? 0,
      huecosPorEstanteria: (data['HUECOS_POR_ESTANTERIA'] as num?)?.toInt() ?? 1,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'CAMARA': camara,
        'ESTANTERIAS': estanterias,
        'NIVELES': niveles,
        'HUECOS_POR_ESTANTERIA': huecosPorEstanteria,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
