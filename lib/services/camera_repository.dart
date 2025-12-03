import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/camera_model.dart';

class CameraRepository {
  CameraRepository({FirebaseFirestore? firestore})
      : _collection =
            (firestore ?? FirebaseFirestore.instance).collection('Storage');

  final CollectionReference<Map<String, dynamic>> _collection;

  Stream<List<CameraModel>> watchAll() {
    return _collection.orderBy('numero').snapshots().map((snapshot) {
      return snapshot.docs.map(CameraModel.fromDoc).where((camera) {
        return camera.filas > 0 && camera.posicionesMax > 0 && camera.niveles > 0;
      }).toList();
    });
  }

  Stream<CameraModel?> watchByNumero(String numero) {
    final docId = numero;
    return _collection.doc(docId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CameraModel.fromDoc(doc);
    });
  }

  Future<List<CameraModel>> fetchAll() async {
    final snapshot = await _collection.orderBy('numero').get();
    return snapshot.docs.map(CameraModel.fromDoc).toList();
  }

  Future<void> save(CameraModel camera) async {
    final normalizedNumero = camera.displayNumero;
    final now = DateTime.now();
    final docRef = _collection.doc(normalizedNumero);
    final existing = await docRef.get();

    DateTime? existingCreatedAt;
    if (existing.exists) {
      final data = existing.data();
      final rawCreated = data?['createdAt'];
      if (rawCreated is Timestamp) {
        existingCreatedAt = rawCreated.toDate();
      }
    }

    final payload = camera
        .copyWith(
          id: normalizedNumero,
          numero: normalizedNumero,
          createdAt: camera.createdAt ?? existingCreatedAt ?? now,
          updatedAt: now,
        )
        .toMap();

    await docRef.set(payload, SetOptions(merge: true));
  }

  Future<void> delete(String numero) async {
    final normalizedNumero = numero.padLeft(2, '0');
    await _collection.doc(normalizedNumero).delete();
  }
}
