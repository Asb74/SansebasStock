import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/storage_row_config.dart';

class StorageConfigRepository {
  StorageConfigRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _rowsCol(String cameraId) {
    return _firestore.collection('StorageConfig').doc(cameraId).collection('rows');
  }

  Stream<List<StorageRowConfig>> watchRows(String cameraId) {
    return _rowsCol(cameraId).snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) => StorageRowConfig.fromDoc(
              cameraId,
              doc.id,
              doc.data(),
            ),
          )
          .toList();
    });
  }

  Future<void> saveRow(StorageRowConfig row) async {
    await _rowsCol(row.cameraId)
        .doc(row.rowId)
        .set(row.toMap(), SetOptions(merge: true));
  }

  Stream<Set<int>> watchOccupiedRows(String cameraId) {
    return _firestore
        .collection('Stock')
        .where('CAMARA', isEqualTo: cameraId)
        .where('HUECO', isEqualTo: 'Ocupado')
        .snapshots()
        .map((snapshot) {
      final result = <int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final estanteria = int.tryParse(data['ESTANTERIA']?.toString() ?? '');
        if (estanteria != null) {
          result.add(estanteria);
        }
      }
      return result;
    });
  }
}
