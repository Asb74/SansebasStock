import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stock_log_entry.dart';
import '../services/stock_logs_repository.dart';

final stockLogsRepositoryProvider = Provider<StockLogsRepository>((ref) {
  return StockLogsRepository(FirebaseFirestore.instance);
});

final lastMovementProvider =
    FutureProvider.family<StockLogEntry?, String>((ref, palletId) async {
  final repo = ref.watch(stockLogsRepositoryProvider);
  return repo.fetchLastMovement(palletId);
});

final palletMovementsProvider =
    StreamProvider.family<List<StockLogEntry>, String>((ref, palletId) {
  final repo = ref.watch(stockLogsRepositoryProvider);
  return repo.watchMovements(palletId);
});
