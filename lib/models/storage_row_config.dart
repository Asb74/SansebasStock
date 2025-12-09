import 'package:cloud_firestore/cloud_firestore.dart';

class StorageRowConfig {
  StorageRowConfig({
    required this.cameraId,
    required this.rowId,
    required this.fila,
    this.marca,
    this.variedad,
    this.calibre,
    this.categoria,
    this.updatedAt,
  });

  final String cameraId;
  final String rowId; // id del doc en Firestore (p.ej. "1")
  final int fila; // número de fila
  final String? marca;
  final String? variedad;
  final String? calibre;
  final String? categoria;
  final DateTime? updatedAt;

  factory StorageRowConfig.fromDoc(
    String cameraId,
    String rowId,
    Map<String, dynamic> data,
  ) {
    return StorageRowConfig(
      cameraId: cameraId,
      rowId: rowId,
      fila: (data['fila'] as int?) ?? int.parse(rowId),
      marca: data['marca'] as String?,
      variedad: data['variedad'] as String?,
      calibre: data['calibre'] as String?,
      categoria: data['categoria'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'camara': cameraId,
      'fila': fila,
      'marca': marca,
      'variedad': variedad,
      'calibre': calibre,
      'categoria': categoria,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  StorageRowConfig copyWith({
    String? marca,
    String? variedad,
    String? calibre,
    String? categoria,
  }) {
    return StorageRowConfig(
      cameraId: cameraId,
      rowId: rowId,
      fila: fila,
      marca: marca ?? this.marca,
      variedad: variedad ?? this.variedad,
      calibre: calibre ?? this.calibre,
      categoria: categoria ?? this.categoria,
      updatedAt: updatedAt,
    );
  }
}
