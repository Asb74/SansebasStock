import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/camera_model.dart';
import '../../../models/storage_row_config.dart';
import '../../../providers/camera_providers.dart';
import '../../../providers/maestros_options_providers.dart';
import '../../../providers/storage_config_providers.dart';

class AssignStorageRowsScreen extends ConsumerWidget {
  const AssignStorageRowsScreen({
    super.key,
    required this.camera,
  });

  final CameraModel camera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(storageRowsByCameraProvider(camera.numero));
    final maestrosAsync = ref.watch(maestrosOptionsProvider);

    final totalEstanterias =
        camera.pasillo == CameraPasillo.central ? camera.filas * 2 : camera.filas;

    return Scaffold(
      appBar: AppBar(
        title: Text('Configurar almacenamiento — Cámara ${camera.displayNumero}'),
      ),
      body: maestrosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error cargando maestros: $e')),
        data: (maestros) {
          return rowsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error cargando configuración: $e')),
            data: (rows) {
              final byFila = {for (final r in rows) r.fila: r};

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: totalEstanterias,
                itemBuilder: (context, index) {
                  final fila = index + 1;
                  final existing = byFila[fila];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Fila $fila',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _buildDropdown(
                                  label: 'Marca',
                                  value: existing?.marca,
                                  options: maestros.marcas,
                                  onChanged: (value) {
                                    _saveRow(ref, fila, existing, camera.numero, marca: value);
                                  },
                                ),
                                _buildDropdown(
                                  label: 'Variedad',
                                  value: existing?.variedad,
                                  options: maestros.variedades,
                                  onChanged: (value) {
                                    _saveRow(ref, fila, existing, camera.numero, variedad: value);
                                  },
                                ),
                                _buildDropdown(
                                  label: 'Calibre',
                                  value: existing?.calibre,
                                  options: maestros.calibres,
                                  onChanged: (value) {
                                    _saveRow(ref, fila, existing, camera.numero, calibre: value);
                                  },
                                ),
                                _buildDropdown(
                                  label: 'Categoría',
                                  value: existing?.categoria,
                                  options: maestros.categorias,
                                  onChanged: (value) {
                                    _saveRow(ref, fila, existing, camera.numero, categoria: value);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        value: value != null && options.contains(value) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: options
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  void _saveRow(
    WidgetRef ref,
    int fila,
    StorageRowConfig? existing,
    String cameraId, {
    String? marca,
    String? variedad,
    String? calibre,
    String? categoria,
  }) {
    final repo = ref.read(storageConfigRepositoryProvider);

    final rowId = fila.toString();
    final base = existing ??
        StorageRowConfig(
          cameraId: cameraId,
          rowId: rowId,
          fila: fila,
        );

    final updated = base.copyWith(
      marca: marca,
      variedad: variedad,
      calibre: calibre,
      categoria: categoria,
    );

    repo.saveRow(updated);
  }
}

class AssignStorageRowsLoader extends ConsumerWidget {
  const AssignStorageRowsLoader({
    super.key,
    required this.cameraId,
  });

  final String cameraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraAsync = ref.watch(cameraByNumeroProvider(cameraId));

    return cameraAsync.when(
      data: (camera) {
        if (camera == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Configurar almacenamiento'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No se encontró la cámara $cameraId'),
              ),
            ),
          );
        }
        return AssignStorageRowsScreen(camera: camera);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Configurar almacenamiento'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error cargando cámara: $e'),
          ),
        ),
      ),
    );
  }
}
