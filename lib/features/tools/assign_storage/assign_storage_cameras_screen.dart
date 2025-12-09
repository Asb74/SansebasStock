import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/camera_model.dart';
import '../../../providers/camera_providers.dart';

class AssignStorageCamerasScreen extends ConsumerWidget {
  const AssignStorageCamerasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camerasAsync = ref.watch(camerasStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignar almacenamiento'),
      ),
      body: camerasAsync.when(
        data: (cameras) {
          final receptionCameras =
              cameras.where((camera) => camera.tipo == CameraTipo.recepcion).toList();

          if (receptionCameras.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No hay cámaras de Recepción configuradas. Añade o edita una cámara para marcarla como Recepción.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: receptionCameras.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final camera = receptionCameras[index];
              final totalEstanterias = camera.pasillo == CameraPasillo.central
                  ? camera.filas * 2
                  : camera.filas;
              final subtitle =
                  'Estanterías: $totalEstanterias · Niveles: ${camera.niveles}';
              return ListTile(
                leading: CircleAvatar(child: Text(camera.displayNumero)),
                title: Text('Cámara ${camera.displayNumero}'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(
                  'tools-assign-storage-camera',
                  pathParameters: {'cameraId': camera.numero},
                  extra: camera,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudieron cargar las cámaras.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
