import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/camera_storage.dart';

class StorageService {
  StorageService() : _col = FirebaseFirestore.instance.collection('Storage');

  final CollectionReference<Map<String, dynamic>> _col;

  Future<List<CameraStorage>> list() async {
    final snap = await _col.orderBy(FieldPath.documentId).get();
    return snap.docs.map((d) => CameraStorage.fromMap(d.data())).toList();
  }

  Stream<List<CameraStorage>> watchCameras() {
    return _col.orderBy('CAMARA').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => CameraStorage.fromMap(doc.data())).toList();
    });
  }

  Future<CameraStorage?> getCamera(String camaraId) async {
    final id = camaraId.padLeft(2, '0');
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return CameraStorage.fromMap(doc.data()!);
  }

  Future<void> upsert({
    required String camara,
    required int estanterias,
    required int niveles,
    int? huecosPorEstanteria,
  }) async {
    final id = camara.padLeft(2, '0');
    final now = DateTime.now();
    final ref = _col.doc(id);
    final doc = await ref.get();

    if (estanterias <= 0 || niveles <= 0) {
      throw Exception('Valores inválidos. ESTANTERIAS y NIVELES deben ser > 0.');
    }

    final data = <String, dynamic>{
      'CAMARA': id,
      'ESTANTERIAS': estanterias,
      'NIVELES': niveles,
      'HUECOS_POR_ESTANTERIA': huecosPorEstanteria ??
          (doc.data()?['HUECOS_POR_ESTANTERIA'] as num?)?.toInt() ??
          1,
      'updatedAt': Timestamp.fromDate(now),
      if (!doc.exists) 'createdAt': Timestamp.fromDate(now),
    };
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> delete(String camara) async {
    await _col.doc(camara.padLeft(2, '0')).delete();
  }
}
