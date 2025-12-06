import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/camera_model.dart';
import '../../providers/camera_providers.dart';
import '../../providers/palets_providers.dart';
import 'camera_map_screen.dart';

class MapCamerasScreen extends ConsumerWidget {
  const MapCamerasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camerasAsync = ref.watch(camerasStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa de cámaras')),
      body: camerasAsync.when(
        data: (cameras) {
          if (cameras.isEmpty) {
            return const Center(
              child: Text(
                'Configura cámaras desde Ajustes para ver el mapa.',
              ),
            );
          }

          return ListView.separated(
            itemCount: cameras.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final camera = cameras[index];
              final totalEstanterias =
                  camera.pasillo == CameraPasillo.central
                      ? camera.filas * 2
                      : camera.filas;

              final subtitle =
                  'Estanterías: $totalEstanterias · '
                  'Niveles: ${camera.niveles} · '
                  'Posiciones: ${camera.posicionesMax} · '
                  'Pasillo: ${camera.pasillo.label}';

              return ListTile(
                leading: CircleAvatar(
                  child: Text(camera.displayNumero),
                ),
                title: Text('Cámara ${camera.displayNumero}'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ref.read(mapaCamaraSeleccionadaProvider.notifier).state =
                      camera.displayNumero;
                  ref.read(mapaNivelSeleccionadoProvider.notifier).state = 1;
                  // ANTES:
                  // context.push(
                  //   '/map/${camera.displayNumero}',
                  //   extra: camera,
                  // );

                  // AHORA: navegación clásica con Navigator
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CameraMapScreen.fromCamera(camera),
                    ),
                  );
                },
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
