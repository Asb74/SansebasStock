import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/palet.dart';
import '../../models/palet_filters.dart';
import '../../providers/palets_providers.dart';
import '../../providers/views_providers.dart';
import '../../utils/export_utils.dart';

class StockFilterPage extends ConsumerStatefulWidget {
  const StockFilterPage({super.key});

  @override
  ConsumerState<StockFilterPage> createState() => _StockFilterPageState();
}

class _StockFilterPageState extends ConsumerState<StockFilterPage> {
  late final TextEditingController _netoMinController;
  late final TextEditingController _netoMaxController;
  ProviderSubscription<PaletFilters>? _filtersSubscription;

  @override
  void initState() {
    super.initState();
    _netoMinController = TextEditingController();
    _netoMaxController = TextEditingController();
    _filtersSubscription = ref.listenManual<PaletFilters>(
      paletFiltersProvider,
      (previous, next) {
        final minText = next.netoMin?.toString() ?? '';
        final maxText = next.netoMax?.toString() ?? '';
        if (_netoMinController.text != minText) {
          _netoMinController.text = minText;
        }
        if (_netoMaxController.text != maxText) {
          _netoMaxController.text = maxText;
        }
      },
    );
  }

  @override
  void dispose() {
    _filtersSubscription?.close();
    _netoMinController.dispose();
    _netoMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(paletFiltersProvider);
    final paletsAsync = ref.watch(paletsStreamProvider);
    final totalsAsync = ref.watch(paletsTotalsProvider);
    final groupedAsync = ref.watch(paletsGroupByUbicacionProvider);
    final storageAsync = ref.watch(storageByCamaraProvider);
    final filterOptionsAsync = ref.watch(paletFilterOptionsProvider);
    final savedViewsAsync = ref.watch(savedPaletViewsProvider);

    final palets = paletsAsync.value ?? <Palet>[];
    final grouped = groupedAsync.value ?? <String, List<Palet>>{};
    final savedViews = savedViewsAsync.value ?? <SavedPaletView>[];
    final storageInfo = storageAsync.value ?? <String, StorageCapacityInfo>{};
    final totals = totalsAsync.valueOrNull;

    final capacityInfo = _buildCapacityInfo(
      filters: filters,
      storage: storageInfo,
      palets: palets,
    );

    final filterOptions = filterOptionsAsync.whenOrNull(data: (data) => data);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe de stock'),
        actions: [
          IconButton(
            onPressed: palets.isEmpty ? null : () => _exportCsv(palets),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
          ),
          IconButton(
            onPressed: palets.isEmpty
                ? null
                : () => _exportPdf(palets, grouped: grouped, filters: filters),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportar PDF',
          ),
          IconButton(
            onPressed: () => _onSaveView(context, filters),
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Guardar vista',
          ),
          PopupMenuButton<_ViewsMenuAction>(
            onSelected: (action) => _onViewsAction(
              context,
              action,
              savedViews,
            ),
            itemBuilder: (context) => <PopupMenuEntry<_ViewsMenuAction>>[
              const PopupMenuItem(
                value: _ViewsMenuAction.load,
                child: Text('Cargar vista guardada'),
              ),
              const PopupMenuItem(
                value: _ViewsMenuAction.rename,
                child: Text('Renombrar vista'),
              ),
              const PopupMenuItem(
                value: _ViewsMenuAction.delete,
                child: Text('Borrar vista'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(savedPaletViewsProvider);
          ref.invalidate(paletFilterOptionsProvider);
          ref.invalidate(storageByCamaraProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FiltersCard(
                      filters: filters,
                      options: filterOptions,
                      netoMinController: _netoMinController,
                      netoMaxController: _netoMaxController,
                      onClear: () {
                        ref.read(paletFiltersProvider.notifier).state =
                            const PaletFilters();
                      },
                      onFiltersChange: (update) {
                        ref.read(paletFiltersProvider.notifier).state = update;
                      },
                    ),
                    const SizedBox(height: 12),
                    _TotalsSummary(
                      totalsAsync: totalsAsync,
                    ),
                    if (capacityInfo != null) ...[
                      const SizedBox(height: 12),
                      _CapacityInfoWidget(info: capacityInfo),
                    ],
                    const SizedBox(height: 12),
                    paletsAsync.when(
                      data: (data) => _ResultsHeader(count: data.length),
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (error, stackTrace) => _ErrorMessage(
                        error: error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            groupedAsync.when(
              data: (data) {
                if (data.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('No se encontraron palets con los filtros.'),
                    ),
                  );
                }
                final entries = data.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = entries[index];
                      final palets = entry.value;
                      final groupTotal = palets.fold<int>(
                        0,
                        (acc, item) => acc + item.neto,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Card(
                          elevation: 1,
                          child: ExpansionTile(
                            title: Text(entry.key),
                            subtitle: Text(
                              'Palets: ${palets.length} — Neto grupo: $groupTotal kg',
                            ),
                            children: palets.map((palet) {
                              return ListTile(
                                title: Text(
                                  '${palet.codigo} · ${palet.cultivo} ${palet.variedad}',
                                ),
                                subtitle: Text(
                                  'Calibre: ${palet.calibre} · Marca: ${palet.marca}\nNivel: ${palet.nivel} · Línea: ${palet.linea} · Posición: ${palet.posicion}',
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(palet.hueco),
                                    Text('${palet.neto} kg'),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                    childCount: entries.length,
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: _ErrorMessage(error: error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  CapacityInfo? _buildCapacityInfo({
    required PaletFilters filters,
    required Map<String, StorageCapacityInfo> storage,
    required List<Palet> palets,
  }) {
    final camara = filters.camara;
    if (camara == null || camara.isEmpty) {
      return null;
    }
    final info = storage[camara];
    if (info == null) {
      return null;
    }

    final paletsCamara = palets.where((palet) => palet.camara == camara);
    final ocupadosCamara =
        paletsCamara.where((palet) => palet.estaOcupado).length;
    final capacidadCamara = info.capacidadTotal;
    final libresCamara = (capacidadCamara - ocupadosCamara)
        .clamp(0, capacidadCamara)
        .toInt();

    int? capacidadEstanteria;
    int? ocupadosEstanteria;
    int? libresEstanteria;

    if (filters.estanteria != null && filters.estanteria!.isNotEmpty) {
      final estanteria = filters.estanteria!;
      final paletsEstanteria = paletsCamara
          .where((palet) => palet.estanteria == estanteria)
          .toList();
      ocupadosEstanteria =
          paletsEstanteria.where((palet) => palet.estaOcupado).length;
      capacidadEstanteria = info.capacidadPorEstanteria.round();
      libresEstanteria = (capacidadEstanteria - ocupadosEstanteria)
          .clamp(0, capacidadEstanteria)
          .toInt();
    }

    return CapacityInfo(
      camara: camara,
      capacidadCamara: capacidadCamara,
      ocupadosCamara: ocupadosCamara,
      libresCamara: libresCamara,
      capacidadEstanteria: capacidadEstanteria,
      ocupadosEstanteria: ocupadosEstanteria,
      libresEstanteria: libresEstanteria,
    );
  }

  Future<void> _exportCsv(List<Palet> palets) async {
    try {
      final file = await exportCsv(palets);
      await Share.shareXFiles([XFile(file.path)], text: 'Informe de stock');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar CSV: $error')),
      );
    }
  }

  Future<void> _exportPdf(
    List<Palet> palets, {
    required Map<String, List<Palet>> grouped,
    required PaletFilters filters,
  }) async {
    try {
      final totalesPorGrupo = grouped.map(
        (key, value) => MapEntry(
          key,
          value.fold<int>(0, (acc, palet) => acc + palet.neto),
        ),
      );
      final descripcionFiltros = _describeFilters(filters);
      final file = await exportPdf(
        palets,
        title: 'Informe de stock — $descripcionFiltros',
        totalesPorGrupo: totalesPorGrupo,
      );
      final bytes = await file.readAsBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename: file.uri.pathSegments.last,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar PDF: $error')),
      );
    }
  }

  String _describeFilters(PaletFilters filters) {
    final buffer = <String>[];
    if (filters.camara != null) buffer.add('Cámara ${filters.camara}');
    if (filters.estanteria != null) {
      buffer.add('Est. ${filters.estanteria}');
    }
    if (filters.hueco != null) buffer.add('Hueco ${filters.hueco}');
    if (filters.cultivo != null) buffer.add('Cultivo ${filters.cultivo}');
    if (filters.variedad != null) buffer.add('Var. ${filters.variedad}');
    if (filters.calibre != null) buffer.add('Cal. ${filters.calibre}');
    if (filters.marca != null) buffer.add('Marca ${filters.marca}');
    if (filters.netoMin != null) buffer.add('Neto ≥ ${filters.netoMin}');
    if (filters.netoMax != null) buffer.add('Neto ≤ ${filters.netoMax}');
    if (buffer.isEmpty) return 'Todos';
    return buffer.join(' · ');
  }

  Future<void> _onSaveView(BuildContext context, PaletFilters filters) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Guardar vista'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nombre de la vista',
              hintText: 'Ej. Ocupados cámara 01',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) {
      return;
    }

    try {
      await ref.read(paletViewsRepositoryProvider).saveView(result, filters);
      if (!mounted) return;
      ref.invalidate(savedPaletViewsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vista "$result" guardada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la vista: $error')),
      );
    }
  }

  Future<void> _onViewsAction(
    BuildContext context,
    _ViewsMenuAction action,
    List<SavedPaletView> views,
  ) async {
    if (views.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay vistas guardadas.')),
      );
      return;
    }

    switch (action) {
      case _ViewsMenuAction.load:
        await _showViewsSelector(
          context,
          views,
          title: 'Cargar vista',
          onSelected: (view) async {
            final filters = await ref
                .read(paletViewsRepositoryProvider)
                .loadView(view.id);
            if (filters != null) {
              ref.read(paletFiltersProvider.notifier).state = filters;
            }
          },
        );
        return;
      case _ViewsMenuAction.rename:
        await _showViewsSelector(
          context,
          views,
          title: 'Renombrar vista',
          onSelected: (view) async {
            final controller = TextEditingController(text: view.name);
            final newName = await showDialog<String>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('Renombrar vista'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Nuevo nombre'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isEmpty) return;
                        Navigator.pop(context, controller.text.trim());
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                );
              },
            );
            if (newName != null && newName.isNotEmpty) {
              await ref
                  .read(paletViewsRepositoryProvider)
                  .renameView(view.id, newName);
              ref.invalidate(savedPaletViewsProvider);
            }
          },
        );
        return;
      case _ViewsMenuAction.delete:
        await _showViewsSelector(
          context,
          views,
          title: 'Borrar vista',
          onSelected: (view) async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('Borrar vista'),
                  content: Text('¿Borrar "${view.name}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Borrar'),
                    ),
                  ],
                );
              },
            );
            if (confirm == true) {
              await ref.read(paletViewsRepositoryProvider).deleteView(view.id);
              ref.invalidate(savedPaletViewsProvider);
            }
          },
        );
        return;
    }
  }

  Future<void> _showViewsSelector(
    BuildContext context,
    List<SavedPaletView> views, {
    required String title,
    required FutureOr<void> Function(SavedPaletView view) onSelected,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: views.length,
              itemBuilder: (context, index) {
                final view = views[index];
                final subtitle = view.updatedAt != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(view.updatedAt!)
                    : null;
                return ListTile(
                  title: Text(view.name),
                  subtitle: subtitle != null ? Text(subtitle) : null,
                  trailing: Text(_describeFilters(view.filters)),
                  onTap: () async {
                    Navigator.pop(context);
                    await onSelected(view);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({
    required this.filters,
    required this.options,
    required this.netoMinController,
    required this.netoMaxController,
    required this.onClear,
    required this.onFiltersChange,
  });

  final PaletFilters filters;
  final PaletFilterOptions? options;
  final TextEditingController netoMinController;
  final TextEditingController netoMaxController;
  final VoidCallback onClear;
  final ValueChanged<PaletFilters> onFiltersChange;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filtros',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpiar filtros'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: _buildDropdown(
                    label: 'Cámara',
                    value: filters.camara,
                    options: options?.camaras ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(
                        filters.copyWith(
                          camara: value,
                          resetEstanteria: value == null || value.isEmpty,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _buildDropdown(
                    label: 'Estantería',
                    value: filters.estanteria,
                    options: options?.estanterias ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(estanteria: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _buildDropdown(
                    label: 'Hueco',
                    value: filters.hueco,
                    options: const ['Libre', 'Ocupado'],
                    allowNull: true,
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(hueco: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: _buildDropdown(
                    label: 'Cultivo',
                    value: filters.cultivo,
                    options: options?.cultivos ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(cultivo: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: _buildDropdown(
                    label: 'Variedad',
                    value: filters.variedad,
                    options: options?.variedades ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(variedad: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _buildDropdown(
                    label: 'Calibre',
                    value: filters.calibre,
                    options: options?.calibres ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(calibre: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: _buildDropdown(
                    label: 'Marca',
                    value: filters.marca,
                    options: options?.marcas ?? const <String>[],
                    onChanged: (value) {
                      onFiltersChange(filters.copyWith(marca: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: netoMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Neto ≥',
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      onFiltersChange(
                        filters.copyWith(
                          netoMin: parsed,
                          resetNetoMin: value.isEmpty,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: netoMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Neto ≤',
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      onFiltersChange(
                        filters.copyWith(
                          netoMax: parsed,
                          resetNetoMax: value.isEmpty,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    bool allowNull = false,
  }) {
    final items = <DropdownMenuItem<String?>>[];
    if (allowNull) {
      items.add(const DropdownMenuItem<String?>(
        value: null,
        child: Text('Todos'),
      ));
    }
    items.addAll(options.map((option) {
      return DropdownMenuItem<String?>(
        value: option,
        child: Text(option),
      );
    }));
    return DropdownButtonFormField<String?>(
      value: value,
      items: items,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }
}

class _TotalsSummary extends StatelessWidget {
  const _TotalsSummary({required this.totalsAsync});

  final AsyncValue<PaletsTotals> totalsAsync;

  @override
  Widget build(BuildContext context) {
    return totalsAsync.when(
      data: (totals) {
        final formatted = NumberFormat('#,##0', 'es_ES');
        return Row(
          children: [
            Chip(
              label: Text('Palets: ${formatted.format(totals.totalPalets)}'),
            ),
            const SizedBox(width: 12),
            Chip(
              label: Text('Total NETO: ${formatted.format(totals.totalNeto)} kg'),
            ),
          ],
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stackTrace) => Text('Error en totales: $error'),
    );
  }
}

class _CapacityInfoWidget extends StatelessWidget {
  const _CapacityInfoWidget({required this.info});

  final CapacityInfo info;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capacidad estimada cámara ${info.camara}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Total: ${info.capacidadCamara} — Ocupados: ${info.ocupadosCamara} — Libres: ${info.libresCamara}',
            ),
            if (info.capacidadEstanteria != null) ...[
              const SizedBox(height: 8),
              Text(
                'Estantería seleccionada: Capacidad ${info.capacidadEstanteria} — Ocupados: ${info.ocupadosEstanteria} — Libres: ${info.libresEstanteria}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CapacityInfo {
  CapacityInfo({
    required this.camara,
    required this.capacidadCamara,
    required this.ocupadosCamara,
    required this.libresCamara,
    this.capacidadEstanteria,
    this.ocupadosEstanteria,
    this.libresEstanteria,
  });

  final String camara;
  final int capacidadCamara;
  final int ocupadosCamara;
  final int libresCamara;
  final int? capacidadEstanteria;
  final int? ocupadosEstanteria;
  final int? libresEstanteria;
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Resultados: $count palets encontrados',
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});

  final Object error;

  String _formatMessage(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'No tienes permisos para leer estos datos. Comprueba tu usuario o las reglas.';
    }
    return 'Error: $error';
  }

  @override
  Widget build(BuildContext context) {
    final message = _formatMessage(error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ocurrió un error al cargar los datos.',
          style: TextStyle(color: Colors.red),
        ),
        const SizedBox(height: 8),
        Text(message),
      ],
    );
  }
}

enum _ViewsMenuAction { load, rename, delete }
