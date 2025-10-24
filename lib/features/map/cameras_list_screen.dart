import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sansebas_stock/features/settings/storage/models/camera_storage.dart';
import 'package:sansebas_stock/features/settings/storage/storage_providers.dart';

class CamerasListScreen extends ConsumerWidget {
  const CamerasListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camerasAsync = ref.watch(watchCamerasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cámaras')), 
      body: camerasAsync.when(
        data: (items) => _CamerasListView(cameras: items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudieron cargar las cámaras.\\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CamerasListView extends StatelessWidget {
  const _CamerasListView({required this.cameras});

  final List<CameraStorage> cameras;

  @override
  Widget build(BuildContext context) {
    if (cameras.isEmpty) {
      return const Center(child: Text('Sin cámaras configuradas.'));
    }

    return ListView.separated(
      itemCount: cameras.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final camera = cameras[index];
        return ListTile(
          leading: CircleAvatar(child: Text(camera.camara)),
          title: Text('Cámara ${camera.camara}'),
          subtitle: Text('Estanterías: ${camera.estanterias} · Niveles: ${camera.niveles}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/map/${camera.camara}'),
        );
      },
    );
  }
}
