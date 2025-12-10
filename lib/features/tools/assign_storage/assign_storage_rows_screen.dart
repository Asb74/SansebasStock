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
    final occupiedAsync = ref.watch(occupiedRowsByCameraProvider(camera.numero));

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
              return occupiedAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error cargando filas ocupadas: $e')),
                data: (occupiedRows) {
                  final byFila = {for (final r in rows) r.fila: r};

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: totalEstanterias,
                    itemBuilder: (context, index) {
                      final fila = index + 1;
                      final existing = byFila[fila];
                      final isOccupied = occupiedRows.contains(fila);

                      final cultivoSeleccionado = existing?.cultivo;
                      final variedadesOptions = cultivoSeleccionado == null
                          ? maestros.variedades
                          : maestros.variedadesPorCultivo[cultivoSeleccionado] ?? const [];
                      final calibresOptions = cultivoSeleccionado == null
                          ? maestros.calibres
                          : maestros.calibresPorCultivo[cultivoSeleccionado] ?? const [];
                      final categoriasOptions = cultivoSeleccionado == null
                          ? maestros.categorias
                          : maestros.categoriasPorCultivo[cultivoSeleccionado] ?? const [];

                      return Card(
                        color: isOccupied ? Colors.red.shade50 : Colors.green.shade50,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 90,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fila $fila',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (isOccupied)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Fila ocupada (no editable)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    _buildDropdown(
                                      label: 'Cultivo',
                                      value: cultivoSeleccionado,
                                      options: maestros.cultivos,
                                      enabled: !isOccupied,
                                      onChanged: (value) {
                                        _saveRow(
                                          ref,
                                          fila,
                                          existing,
                                          camera.numero,
                                          cultivo: value,
                                          variedad: null,
                                          calibre: null,
                                          categoria: null,
                                        );
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Marca',
                                      value: existing?.marca,
                                      options: maestros.marcas,
                                      enabled: !isOccupied,
                                      onChanged: (value) {
                                        _saveRow(
                                          ref,
                                          fila,
                                          existing,
                                          camera.numero,
                                          marca: value,
                                        );
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Variedad',
                                      value: existing?.variedad,
                                      options: variedadesOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) {
                                        _saveRow(
                                          ref,
                                          fila,
                                          existing,
                                          camera.numero,
                                          variedad: value,
                                        );
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Calibre',
                                      value: existing?.calibre,
                                      options: calibresOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) {
                                        _saveRow(
                                          ref,
                                          fila,
                                          existing,
                                          camera.numero,
                                          calibre: value,
                                        );
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Categoría',
                                      value: existing?.categoria,
                                      options: categoriasOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) {
                                        _saveRow(
                                          ref,
                                          fila,
                                          existing,
                                          camera.numero,
                                          categoria: value,
                                        );
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
    bool enabled = true,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        value: value != null && options.contains(value) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('(Sin valor)'),
          ),
          ...options.map((e) => DropdownMenuItem(
                value: e,
                child: Text(e),
              )),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  void _saveRow(
    WidgetRef ref,
    int fila,
    StorageRowConfig? existing,
    String cameraId, {
    String? cultivo,
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
      cultivo: cultivo,
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
