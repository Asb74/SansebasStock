import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_log_entry.dart';

class StockLogsRepository {
  StockLogsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('StockLogs');

  Future<StockLogEntry?> fetchLastMovement(String palletId) async {
    final snap = await _col
        .where('palletId', isEqualTo: palletId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return StockLogEntry.fromDoc(snap.docs.first);
  }

  Stream<List<StockLogEntry>> watchMovements(String palletId) {
    return _col
        .where('palletId', isEqualTo: palletId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => StockLogEntry.fromDoc(doc))
              .toList(growable: false),
        );
  }
}
