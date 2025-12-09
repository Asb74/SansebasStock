import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storage_row_config.dart';
import '../services/storage_config_repository.dart';

final storageConfigRepositoryProvider = Provider<StorageConfigRepository>((ref) {
  return StorageConfigRepository(FirebaseFirestore.instance);
});

// Stream de filas configuradas para una cámara concreta
final storageRowsByCameraProvider =
    StreamProvider.family<List<StorageRowConfig>, String>((ref, cameraId) {
  final repo = ref.watch(storageConfigRepositoryProvider);
  return repo.watchRows(cameraId);
});
