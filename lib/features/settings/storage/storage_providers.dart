import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/camera_storage.dart';
import 'storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

final storageListProvider = FutureProvider<List<CameraStorage>>((ref) async {
  final svc = ref.read(storageServiceProvider);
  return svc.list();
});

final watchCamerasProvider = StreamProvider<List<CameraStorage>>((ref) {
  final svc = ref.read(storageServiceProvider);
  return svc.watchCameras();
});

final cameraByIdProvider = FutureProvider.family<CameraStorage?, String>((ref, camaraId) {
  final svc = ref.read(storageServiceProvider);
  return svc.getCamera(camaraId);
});
