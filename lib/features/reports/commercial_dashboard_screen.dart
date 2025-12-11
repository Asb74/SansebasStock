import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/commercial_filters.dart';
import '../../models/commercial_group_row.dart';
import '../../models/commercial_variety_summary.dart';
import '../../models/saved_commercial_view.dart';
import '../../providers/commercial_providers.dart';
import '../../services/commercial_views_repository.dart';
import '../../utils/export_utils.dart';

class CommercialDashboardScreen extends ConsumerStatefulWidget {
  const CommercialDashboardScreen({super.key});

  @override
  ConsumerState<CommercialDashboardScreen> createState() =>
      _CommercialDashboardScreenState();
}

class _CommercialDashboardScreenState
    extends ConsumerState<CommercialDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(commercialFiltersProvider);
    final groupedAsync = ref.watch(commercialGroupedRowsProvider);
    final varietySummaryAsync = ref.watch(commercialVarietySummaryProvider);
    final totalsAsync = ref.watch(commercialTotalsProvider);
    final filterOptions = ref.watch(commercialFilterOptionsProvider);
    final columns = ref.watch(commercialColumnsProvider);
    final savedViewsAsync = ref.watch(savedCommercialViewsProvider);

    final groupedRows = groupedAsync.value ?? <CommercialGroupRow>[];
    final isVarietySummaryView = columns.length == 2 &&
        columns.contains(CommercialColumn.variedad) &&
        columns.contains(CommercialColumn.totalNeto);
    final savedViews = savedViewsAsync.value ?? <SavedCommercialView>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe comercial'),
        actions: [
          IconButton(
            onPressed:
                groupedRows.isEmpty ? null : () => _exportCommercialCsv(context),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
          ),
          IconButton(
            onPressed:
                groupedRows.isEmpty ? null : () => _exportCommercialPdf(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportar PDF',
          ),
          IconButton(
            onPressed: () => _onSaveView(context, filters, columns),
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Guardar vista',
          ),
          PopupMenuButton<_ViewsMenuAction>(
            onSelected: (action) =>
                _onViewsAction(context, action, savedViews),
            itemBuilder: (context) => const <PopupMenuEntry<_ViewsMenuAction>>[
              PopupMenuItem(
                value: _ViewsMenuAction.load,
                child: Text('Cargar vista guardada'),
              ),
              PopupMenuItem(
                value: _ViewsMenuAction.rename,
                child: Text('Renombrar vista'),
              ),
              PopupMenuItem(
                value: _ViewsMenuAction.delete,
                child: Text('Borrar vista'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(filteredCommercialPaletsProvider);
          ref.invalidate(commercialFilterOptionsProvider);
          ref.invalidate(commercialTotalsProvider);
          ref.invalidate(savedCommercialViewsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FiltersSection(
              filters: filters,
              options: filterOptions,
              onFiltersChanged: (updated) {
                ref.read(commercialFiltersProvider.notifier).state = updated;
              },
              onClear: () {
                ref.read(commercialFiltersProvider.notifier).state =
                    const CommercialFilters();
              },
            ),
            const SizedBox(height: 16),
            _KpisSection(totalsAsync: totalsAsync),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _openColumnsDialog(context, ref, columns),
                    icon: const Text('⚙️'),
                    label: const Text('Columnas'),
                  ),
                  FilledButton.icon(
                    onPressed: groupedRows.isEmpty
                        ? null
                        : () => _exportCommercialCsv(context),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Exportar CSV'),
                  ),
                  FilledButton.icon(
                    onPressed: groupedRows.isEmpty
                        ? null
                        : () => _exportCommercialPdf(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Exportar PDF'),
                  ),
                ],
              ),
            ),
            isVarietySummaryView
                ? varietySummaryAsync.when(
                    data: (rows) => _VarietySummaryTable(rows: rows),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Error al cargar: $error'),
                      ),
                    ),
                  )
                : groupedAsync.when(
                    data: (rows) => _GroupedTable(
                      rows: rows,
                      columns: columns,
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Error al cargar: $error'),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _openColumnsDialog(
    BuildContext context,
    WidgetRef ref,
    Set<CommercialColumn> selected,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final current = Set<CommercialColumn>.from(selected);
        return AlertDialog(
          title: const Text('Selecciona columnas'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: CommercialColumn.values.map((column) {
                    return CheckboxListTile(
                      dense: true,
                      value: current.contains(column),
                      title: Text(_columnLabel(column)),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            current.add(column);
                          } else {
                            current.remove(column);
                          }
                        });
                        ref
                            .read(commercialColumnsProvider.notifier)
                            .state = Set.of(current);
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportCommercialCsv(BuildContext context) async {
    final grouped = ref.read(commercialGroupedRowsProvider).value ?? [];
    try {
      final file = await exportCommercialCsv(grouped);
      await Share.shareXFiles([XFile(file.path)], text: 'Informe comercial');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar CSV: $error')),
      );
    }
  }

  Future<void> _exportCommercialPdf(BuildContext context) async {
    final grouped = ref.read(commercialGroupedRowsProvider).value ?? [];
    final filters = ref.read(commercialFiltersProvider);
    try {
      final descripcionFiltros = _describeFilters(filters);
      final file = await exportCommercialPdf(
        grouped,
        title: 'Informe comercial — $descripcionFiltros',
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

  String _describeFilters(CommercialFilters filters) {
    final buffer = <String>[];
    if (filters.cultivos.isNotEmpty) {
      buffer.add('Cultivo ${filters.cultivos.join(', ')}');
    }
    if (filters.variedades.isNotEmpty) {
      buffer.add('Var. ${filters.variedades.join(', ')}');
    }
    if (filters.calibres.isNotEmpty) {
      buffer.add('Cal. ${filters.calibres.join(', ')}');
    }
    if (filters.categorias.isNotEmpty) {
      buffer.add('Cat. ${filters.categorias.join(', ')}');
    }
    if (filters.marcas.isNotEmpty) {
      buffer.add('Marca ${filters.marcas.join(', ')}');
    }
    if (filters.pedidos.isNotEmpty) {
      buffer.add('Pedido ${filters.pedidos.join(', ')}');
    }
    if (filters.vidaRange != null) {
      final formatter = DateFormat('dd/MM/yyyy');
      buffer.add(
        'Vida ${formatter.format(filters.vidaRange!.start)} - ${formatter.format(filters.vidaRange!.end)}',
      );
    }
    if (buffer.isEmpty) return 'Todos';
    return buffer.join(' · ');
  }

  Future<void> _onSaveView(
    BuildContext context,
    CommercialFilters filters,
    Set<CommercialColumn> columns,
  ) async {
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
              hintText: 'Ej. Comercial calibres',
            ),
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

    if (result == null || result.isEmpty) return;

    try {
      await ref
          .read(commercialViewsRepositoryProvider)
          .saveView(result, filters, columns);
      if (!mounted) return;
      ref.invalidate(savedCommercialViewsProvider);
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
    List<SavedCommercialView> views,
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
            final repo = ref.read(commercialViewsRepositoryProvider);
            final filters = await repo.loadFilters(view.id);
            final columns = await repo.loadColumns(view.id);
            if (filters != null) {
              ref.read(commercialFiltersProvider.notifier).state = filters;
            }
            if (columns != null) {
              ref.read(commercialColumnsProvider.notifier).state = columns;
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
                  .read(commercialViewsRepositoryProvider)
                  .renameView(view.id, newName);
              ref.invalidate(savedCommercialViewsProvider);
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
              await ref
                  .read(commercialViewsRepositoryProvider)
                  .deleteView(view.id);
              ref.invalidate(savedCommercialViewsProvider);
            }
          },
        );
        return;
    }
  }

  Future<void> _showViewsSelector(
    BuildContext context,
    List<SavedCommercialView> views, {
    required String title,
    required Future<void> Function(SavedCommercialView view) onSelected,
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
        );
      },
    );
  }
}

enum _ViewsMenuAction { load, rename, delete }

class _FiltersSection extends StatelessWidget {
  const _FiltersSection({
    required this.filters,
    required this.options,
    required this.onFiltersChanged,
    required this.onClear,
  });

  final CommercialFilters filters;
  final CommercialFilterOptions? options;
  final ValueChanged<CommercialFilters> onFiltersChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Limpiar filtros'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MultiSelectFilter(
                  label: 'Cultivo',
                  values: options?.cultivos ?? {},
                  selected: filters.cultivos,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(cultivos: selection)),
                ),
                _MultiSelectFilter(
                  label: 'Variedad',
                  values: options?.variedades ?? {},
                  selected: filters.variedades,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(variedades: selection)),
                ),
                _MultiSelectFilter(
                  label: 'Calibre',
                  values: options?.calibres ?? {},
                  selected: filters.calibres,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(calibres: selection)),
                ),
                _MultiSelectFilter(
                  label: 'Categoría',
                  values: options?.categorias ?? {},
                  selected: filters.categorias,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(categorias: selection)),
                ),
                _MultiSelectFilter(
                  label: 'Marca',
                  values: options?.marcas ?? {},
                  selected: filters.marcas,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(marcas: selection)),
                ),
                _MultiSelectFilter(
                  label: 'Pedido',
                  values: options?.pedidos ?? {},
                  selected: filters.pedidos,
                  onSelected: (selection) =>
                      onFiltersChanged(filters.copyWith(pedidos: selection)),
                ),
                _VidaFilter(
                  currentRange: filters.vidaRange,
                  availableRange: options?.vidaRange,
                  onChanged: (range) =>
                      onFiltersChanged(filters.copyWith(vidaRange: range)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectFilter extends StatelessWidget {
  const _MultiSelectFilter({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Set<String> values;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: values.isEmpty
          ? null
          : () async {
              final selection = await _showMultiSelectDialog(
                context,
                label,
                values,
                selected,
              );
              if (selection != null) {
                onSelected(selection);
              }
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            selected.isEmpty
                ? '(Todos)'
                : '${selected.length} seleccionados',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VidaFilter extends StatelessWidget {
  const _VidaFilter({
    required this.currentRange,
    required this.availableRange,
    required this.onChanged,
  });

  final DateTimeRange? currentRange;
  final DateTimeRange? availableRange;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: availableRange == null
          ? null
          : () async {
              final range = await showDateRangePicker(
                context: context,
                initialDateRange: currentRange ?? availableRange,
                firstDate: availableRange!.start,
                lastDate: availableRange!.end,
              );
              if (range != null) {
                onChanged(range);
              }
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vida', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            currentRange == null
                ? '(Todas)'
                : '${_formatDate(currentRange!.start)} - ${_formatDate(currentRange!.end)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (currentRange != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Quitar rango'),
            ),
        ],
      ),
    );
  }
}

class _KpisSection extends StatelessWidget {
  const _KpisSection({required this.totalsAsync});

  final AsyncValue<CommercialTotals> totalsAsync;

  @override
  Widget build(BuildContext context) {
    return totalsAsync.when(
      data: (totals) {
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _KpiCard(title: 'Palets', value: totals.totalPalets.toString()),
            _KpiCard(title: 'Total NETO', value: '${totals.totalNeto} kg'),
            _KpiCard(title: 'Pedidos', value: totals.numPedidos.toString()),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error al calcular KPIs: $error'),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VarietySummaryTable extends StatelessWidget {
  const _VarietySummaryTable({required this.rows});

  final List<CommercialVarietySummary> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No hay datos para mostrar')),
      );
    }

    final dataRows = rows.map((row) {
      return DataRow(
        cells: [
          DataCell(Text(row.variedad)),
          DataCell(Text('${row.totalNeto} kg')),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Variedad')),
          DataColumn(label: Text('Neto total')),
        ],
        rows: dataRows,
      ),
    );
  }
}

class _GroupedTable extends StatelessWidget {
  const _GroupedTable({required this.rows, required this.columns});

  final List<CommercialGroupRow> rows;
  final Set<CommercialColumn> columns;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No hay datos para mostrar')),
      );
    }

    final dataColumns = columns
        .map((column) => DataColumn(label: Text(_columnLabel(column))))
        .toList();

    final dataRows = rows.map((row) {
      final cells = columns.map((column) {
        return DataCell(Text(_columnValue(row, column)));
      }).toList();
      return DataRow(cells: cells);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: dataColumns, rows: dataRows),
    );
  }
}

Future<Set<String>?> _showMultiSelectDialog(
  BuildContext context,
  String title,
  Set<String> values,
  Set<String> selected,
) {
  return showDialog<Set<String>>(
    context: context,
    builder: (context) {
      final current = Set<String>.from(selected);
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 320,
              child: ListView(
                shrinkWrap: true,
                children: values.map((value) {
                  final isSelected = current.contains(value);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(value),
                    value: isSelected,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          current.add(value);
                        } else {
                          current.remove(value);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(current),
            child: const Text('Aplicar'),
          ),
        ],
      );
    },
  );
}

String _columnLabel(CommercialColumn column) {
  switch (column) {
    case CommercialColumn.camara:
      return 'Cámara';
    case CommercialColumn.estanteria:
      return 'Estantería';
    case CommercialColumn.nivel:
      return 'Nivel';
    case CommercialColumn.posicion:
      return 'Posición';
    case CommercialColumn.cultivo:
      return 'Cultivo';
    case CommercialColumn.variedad:
      return 'Variedad';
    case CommercialColumn.calibre:
      return 'Calibre';
    case CommercialColumn.marca:
      return 'Marca';
    case CommercialColumn.categoria:
      return 'Categoría';
    case CommercialColumn.pedido:
      return 'Pedido';
    case CommercialColumn.vida:
      return 'Vida';
    case CommercialColumn.neto:
      return 'Neto';
    case CommercialColumn.paletsCount:
      return 'Palets';
    case CommercialColumn.totalNeto:
      return 'Neto total';
    case CommercialColumn.linea:
      return 'Línea';
    case CommercialColumn.confeccion:
      return 'IdConfección';
    case CommercialColumn.codigo:
      return 'Código';
  }
}

String _columnValue(CommercialGroupRow row, CommercialColumn column) {
  switch (column) {
    case CommercialColumn.camara:
      return '';
    case CommercialColumn.estanteria:
      return '';
    case CommercialColumn.nivel:
      return '';
    case CommercialColumn.posicion:
      return '';
    case CommercialColumn.cultivo:
      return row.cultivo ?? '';
    case CommercialColumn.variedad:
      return row.variedad ?? '';
    case CommercialColumn.calibre:
      return row.calibre ?? '';
    case CommercialColumn.marca:
      return row.marca ?? '';
    case CommercialColumn.categoria:
      return row.categoria ?? '';
    case CommercialColumn.pedido:
      return row.pedido ?? '';
    case CommercialColumn.vida:
      return '';
    case CommercialColumn.neto:
      return '';
    case CommercialColumn.paletsCount:
      return row.countPalets.toString();
    case CommercialColumn.totalNeto:
      return '${row.totalNeto} kg';
    case CommercialColumn.linea:
      return '';
    case CommercialColumn.confeccion:
      return '';
    case CommercialColumn.codigo:
      return '';
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
