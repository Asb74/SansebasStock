import 'package:cloud_firestore/cloud_firestore.dart';

class CameraConfig {
  final String camara;
  final int estanterias;
  final int niveles;
  final DateTime createdAt;
  final DateTime updatedAt;

  CameraConfig({
    required this.camara,
    required this.estanterias,
    required this.niveles,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CameraConfig.fromMap(Map<String, dynamic> data) {
    return CameraConfig(
      camara: data['CAMARA'] as String,
      estanterias: (data['ESTANTERIAS'] as num).toInt(),
      niveles: (data['NIVELES'] as num).toInt(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'CAMARA': camara,
        'ESTANTERIAS': estanterias,
        'NIVELES': niveles,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}
