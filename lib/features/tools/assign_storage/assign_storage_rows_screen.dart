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

                      final row = existing ??
                          StorageRowConfig(
                            cameraId: camera.numero,
                            rowId: fila.toString(),
                            fila: fila,
                          );

                      final cultivoSeleccionado = row.cultivo;
                      final variedadesOptions = cultivoSeleccionado == null
                          ? maestros.variedades
                          : maestros.variedadesPorCultivo[cultivoSeleccionado] ?? const [];
                      final calibresOptions = cultivoSeleccionado == null
                          ? maestros.calibres
                          : maestros.calibresPorCultivo[cultivoSeleccionado] ?? const [];
                      final categoriasOptions = cultivoSeleccionado == null
                          ? maestros.categorias
                          : maestros.categoriasPorCultivo[cultivoSeleccionado] ?? const [];

                      final selectedVariedad =
                          variedadesOptions.contains(row.variedad) ? row.variedad : null;
                      final selectedCalibre =
                          calibresOptions.contains(row.calibre) ? row.calibre : null;
                      final selectedCategoria =
                          categoriasOptions.contains(row.categoria) ? row.categoria : null;

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
                                      onChanged: (value) async {
                                        if (value == null) return;

                                        final variedadesValidas =
                                            maestros.variedadesPorCultivo[value] ?? [];
                                        final calibresValidos =
                                            maestros.calibresPorCultivo[value] ?? [];
                                        final categoriasValidas =
                                            maestros.categoriasPorCultivo[value] ?? [];

                                        final nuevaVariedad =
                                            variedadesValidas.contains(row.variedad)
                                                ? row.variedad
                                                : null;
                                        final nuevoCalibre = calibresValidas.contains(row.calibre)
                                            ? row.calibre
                                            : null;
                                        final nuevaCategoria =
                                            categoriasValidas.contains(row.categoria)
                                                ? row.categoria
                                                : null;

                                        final updated = row.copyWith(
                                          cultivo: value,
                                          variedad: nuevaVariedad,
                                          calibre: nuevoCalibre,
                                          categoria: nuevaCategoria,
                                        );

                                        await _saveRow(ref, updated);
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Marca',
                                      value: row.marca,
                                      options: maestros.marcas,
                                      enabled: !isOccupied,
                                      onChanged: (value) async {
                                        final updated = row.copyWith(marca: value);
                                        await _saveRow(ref, updated);
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Variedad',
                                      value: selectedVariedad,
                                      options: variedadesOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) async {
                                        final updated = row.copyWith(variedad: value);
                                        await _saveRow(ref, updated);
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Calibre',
                                      value: selectedCalibre,
                                      options: calibresOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) async {
                                        final updated = row.copyWith(calibre: value);
                                        await _saveRow(ref, updated);
                                      },
                                    ),
                                    _buildDropdown(
                                      label: 'Categoría',
                                      value: selectedCategoria,
                                      options: categoriasOptions,
                                      enabled: !isOccupied,
                                      onChanged: (value) async {
                                        final updated = row.copyWith(categoria: value);
                                        await _saveRow(ref, updated);
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

  Future<void> _saveRow(
    WidgetRef ref,
    StorageRowConfig row,
  ) async {
    final repo = ref.read(storageConfigRepositoryProvider);

    await repo.saveRow(row);
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
