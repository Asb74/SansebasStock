import 'package:cloud_firestore/cloud_firestore.dart';

const _sentinel = Object();

class StorageRowConfig {
  StorageRowConfig({
    required this.cameraId,
    required this.rowId,
    required this.fila,
    this.cultivo,
    this.marca,
    this.variedad,
    this.calibre,
    this.categoria,
    this.updatedAt,
  });

  final String cameraId;
  final String rowId; // id del doc en Firestore (p.ej. "1")
  final int fila; // número de fila
  final String? cultivo;
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
      cultivo: data['cultivo'] as String?,
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
      'cultivo': cultivo,
      'marca': marca,
      'variedad': variedad,
      'calibre': calibre,
      'categoria': categoria,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  StorageRowConfig copyWith({
    Object? cultivo = _sentinel,
    Object? marca = _sentinel,
    Object? variedad = _sentinel,
    Object? calibre = _sentinel,
    Object? categoria = _sentinel,
  }) {
    return StorageRowConfig(
      cameraId: cameraId,
      rowId: rowId,
      fila: fila,
      cultivo: cultivo == _sentinel ? this.cultivo : cultivo as String?,
      marca: marca == _sentinel ? this.marca : marca as String?,
      variedad: variedad == _sentinel ? this.variedad : variedad as String?,
      calibre: calibre == _sentinel ? this.calibre : calibre as String?,
      categoria: categoria == _sentinel ? this.categoria : categoria as String?,
      updatedAt: updatedAt,
    );
  }
}
