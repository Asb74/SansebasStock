import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/camera_config.dart';
import 'storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

final storageListProvider = FutureProvider<List<CameraConfig>>((ref) async {
  final svc = ref.read(storageServiceProvider);
  return svc.list();
});
