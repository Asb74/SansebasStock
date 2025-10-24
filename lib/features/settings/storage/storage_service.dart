import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/camera_config.dart';

class StorageService {
  final _col = FirebaseFirestore.instance.collection('Storage');

  Future<List<CameraConfig>> list() async {
    final snap = await _col.orderBy(FieldPath.documentId).get();
    return snap.docs.map((d) => CameraConfig.fromMap(d.data())).toList();
  }

  Future<void> upsert({
    required String camara,
    required int estanterias,
    required int niveles,
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
      'updatedAt': Timestamp.fromDate(now),
      if (!doc.exists) 'createdAt': Timestamp.fromDate(now),
    };
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> delete(String camara) async {
    await _col.doc(camara.padLeft(2, '0')).delete();
  }
}
