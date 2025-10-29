import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/camera_model.dart';
import '../../providers/camera_providers.dart';

class CamerasListScreen extends ConsumerWidget {
  const CamerasListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camerasAsync = ref.watch(camerasStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cámaras')),
      body: camerasAsync.when(
        data: (cameras) {
          if (cameras.isEmpty) {
            return const Center(
              child: Text('Sin cámaras configuradas. Crea una nueva para empezar.'),
            );
          }
          return ListView.separated(
            itemCount: cameras.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final camera = cameras[index];
              final totalEstanterias = camera.pasillo == CameraPasillo.central
                  ? camera.filas * 2
                  : camera.filas;
              final subtitle =
                  'Estanterías: $totalEstanterias · Niveles: ${camera.niveles} · Posiciones: ${camera.posicionesMax} · Pasillo: ${camera.pasillo.label}';
              return ListTile(
                leading: CircleAvatar(child: Text(camera.displayNumero)),
                title: Text('Cámara ${camera.displayNumero}'),
                subtitle: Text(subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar',
                      onPressed: () => _showCameraDialog(context, ref, camera: camera),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Eliminar',
                      onPressed: () => _confirmDelete(context, ref, camera),
                    ),
                  ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCameraDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cámara'),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CameraModel camera) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cámara'),
        content: Text('¿Eliminar la cámara ${camera.displayNumero}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cameraRepositoryProvider).delete(camera.numero);
    }
  }

  Future<void> _showCameraDialog(BuildContext context, WidgetRef ref, {CameraModel? camera}) async {
    final numeroController = TextEditingController(text: camera?.displayNumero ?? '');
    final filasController =
        TextEditingController(text: camera != null ? camera.filas.toString() : '');
    final nivelesController =
        TextEditingController(text: camera != null ? camera.niveles.toString() : '');
    final posicionesController = TextEditingController(
      text: camera != null ? camera.posicionesMax.toString() : '',
    );
    CameraPasillo pasillo = camera?.pasillo ?? CameraPasillo.central;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          clipBehavior: Clip.antiAlias,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          title: Text(camera == null ? 'Nueva cámara' : 'Editar cámara'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: numeroController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número',
                      helperText: 'Usa dos dígitos (01, 02, ...)',
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.length != 2) {
                        return 'Introduce un número de dos dígitos';
                      }
                      if (int.tryParse(raw) == null || int.parse(raw) <= 0) {
                        return 'El número debe ser mayor que 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: filasController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de estanterías por lado',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      final parsed = int.tryParse(raw);
                      if (parsed == null || parsed <= 0) {
                        return 'Introduce un número válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nivelesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Niveles',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      final parsed = int.tryParse(value?.trim() ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Introduce un número válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: posicionesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Posiciones máximas por fila',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      final parsed = int.tryParse(value?.trim() ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Introduce un número válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<CameraPasillo>(
                    value: pasillo,
                    decoration: const InputDecoration(labelText: 'Pasillo'),
                    items: CameraPasillo.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        pasillo = value;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                final numero = numeroController.text.padLeft(2, '0');
                final filas = int.parse(filasController.text);
                final niveles = int.parse(nivelesController.text);
                final posiciones = int.parse(posicionesController.text);
                final repository = ref.read(cameraRepositoryProvider);

                final model = CameraModel(
                  id: numero,
                  numero: numero,
                  filas: filas,
                  niveles: niveles,
                  pasillo: pasillo,
                  posicionesMax: posiciones,
                  createdAt: camera?.createdAt,
                  updatedAt: camera?.updatedAt,
                );

                await repository.save(model);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(camera == null ? 'Crear' : 'Guardar'),
            ),
          ],
        );
      },
    );

    numeroController.dispose();
    filasController.dispose();
    nivelesController.dispose();
    posicionesController.dispose();
  }
}
