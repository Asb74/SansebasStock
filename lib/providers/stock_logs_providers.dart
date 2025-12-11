import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/palet.dart';
import '../models/stock_log_entry.dart';
import '../services/stock_logs_repository.dart';

final stockLogsRepositoryProvider = Provider<StockLogsRepository>((ref) {
  return StockLogsRepository(FirebaseFirestore.instance);
});

final lastMovementProvider =
    FutureProvider.family<StockLogEntry?, Palet>((ref, palet) async {
  final repo = ref.watch(stockLogsRepositoryProvider);
  return repo.fetchLastMovement(palet);
});

final palletMovementsProvider =
    StreamProvider.family<List<StockLogEntry>, Palet>((ref, palet) {
  final repo = ref.watch(stockLogsRepositoryProvider);
  return repo.watchMovements(palet);
});
