import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/commercial_filters.dart';
import '../../models/palet.dart';
import '../../providers/commercial_providers.dart';

class CommercialDashboardScreen extends ConsumerWidget {
  const CommercialDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(commercialFiltersProvider);
    final paletsAsync = ref.watch(filteredCommercialPaletsProvider);
    final totalsAsync = ref.watch(commercialTotalsProvider);
    final filterOptions = ref.watch(commercialFilterOptionsProvider);
    final columns = ref.watch(commercialColumnsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe comercial'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(filteredCommercialPaletsProvider);
          ref.invalidate(commercialFilterOptionsProvider);
          ref.invalidate(commercialTotalsProvider);
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
              child: TextButton.icon(
                onPressed: () => _openColumnsDialog(context, ref, columns),
                icon: const Text('⚙️'),
                label: const Text('Columnas'),
              ),
            ),
            paletsAsync.when(
              data: (palets) => _PaletsTable(
                palets: palets,
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
}

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

class _PaletsTable extends StatelessWidget {
  const _PaletsTable({required this.palets, required this.columns});

  final List<Palet> palets;
  final Set<CommercialColumn> columns;

  @override
  Widget build(BuildContext context) {
    if (palets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No hay datos para mostrar')),
      );
    }

    final dataColumns = columns
        .map((column) => DataColumn(label: Text(_columnLabel(column))))
        .toList();

    final dataRows = palets.map((palet) {
      final cells = columns.map((column) {
        return DataCell(Text(_columnValue(palet, column)));
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
    case CommercialColumn.linea:
      return 'Línea';
    case CommercialColumn.confeccion:
      return 'IdConfección';
    case CommercialColumn.codigo:
      return 'Código';
  }
}

String _columnValue(Palet palet, CommercialColumn column) {
  switch (column) {
    case CommercialColumn.camara:
      return palet.camara;
    case CommercialColumn.estanteria:
      return palet.estanteria;
    case CommercialColumn.nivel:
      return palet.nivel.toString();
    case CommercialColumn.posicion:
      return palet.posicion.toString();
    case CommercialColumn.cultivo:
      return palet.cultivo;
    case CommercialColumn.variedad:
      return palet.variedad;
    case CommercialColumn.calibre:
      return palet.calibre;
    case CommercialColumn.marca:
      return palet.marca;
    case CommercialColumn.categoria:
      return palet.categoria ?? '';
    case CommercialColumn.pedido:
      return palet.pedido ?? '';
    case CommercialColumn.vida:
      return palet.vida ?? '';
    case CommercialColumn.neto:
      return '${palet.neto} kg';
    case CommercialColumn.linea:
      return palet.linea.toString();
    case CommercialColumn.confeccion:
      return palet.confeccion ?? '';
    case CommercialColumn.codigo:
      return palet.codigo;
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
