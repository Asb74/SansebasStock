import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'compare_loteado_stock_provider.dart';

class CompareLoteadoStockScreen extends ConsumerStatefulWidget {
  const CompareLoteadoStockScreen({super.key});

  @override
  ConsumerState<CompareLoteadoStockScreen> createState() =>
      _CompareLoteadoStockScreenState();
}

class _CompareLoteadoStockScreenState
    extends ConsumerState<CompareLoteadoStockScreen> {
  String? _selectedVariedad;
  String? _selectedCamara;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparisonAsync = ref.watch(compareLoteadoStockProvider);
    final lastSyncAsync = ref.watch(lastLoteadoSyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparar Loteado vs Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(compareLoteadoStockProvider);
              ref.invalidate(lastLoteadoSyncProvider);
            },
          ),
          comparisonAsync.when(
            data: (diff) => PopupMenuButton<_ExportAction>(
              onSelected: (action) => _onExportAction(action, diff, lastSyncAsync),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ExportAction.csv,
                  child: Text('Exportar CSV'),
                ),
                PopupMenuItem(
                  value: _ExportAction.pdf,
                  child: Text('Exportar PDF'),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: comparisonAsync.when(
        data: (diff) {
          final variedadOptions = ['Todas', ...diff.variedadOptions];
          final camaraOptions = ['Todas', ...diff.camaraOptions];

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(compareLoteadoStockProvider);
              ref.invalidate(lastLoteadoSyncProvider);
              await ref.read(compareLoteadoStockProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        _LastSyncText(asyncValue: lastSyncAsync),
                        const SizedBox(height: 12),
                        _SummaryRow(
                          label: 'Total Loteado',
                          value: diff.totalLoteado.toString(),
                        ),
                        _SummaryRow(
                          label: 'Total Stock (Hueco=Ocupado)',
                          value: diff.totalStockOcupado.toString(),
                        ),
                        _SummaryRow(
                          label: 'En Loteado pero no en Stock',
                          value: diff.docsEnLoteadoNoStock.length.toString(),
                        ),
                        _SummaryRow(
                          label: 'En Stock (Ocupado) pero no en Loteado',
                          value: diff.docsEnStockNoLoteado.length.toString(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FiltersRow(
                  variedadOptions: variedadOptions,
                  camaraOptions: camaraOptions,
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  searchController: _searchController,
                  onVariedadChanged: (value) {
                    setState(() {
                      _selectedVariedad = value == 'Todas' ? null : value;
                    });
                  },
                  onCamaraChanged: (value) {
                    setState(() {
                      _selectedCamara = value == 'Todas' ? null : value;
                    });
                  },
                  onSearchChanged: (value) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  title: 'En Loteado pero NO en Stock (Hueco=Ocupado)',
                  items: diff.enLoteadoNoStockItems,
                  emptyText: 'No hay diferencias en este grupo.',
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  searchText: _searchController.text,
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  title: 'En Stock (Ocupado) pero NO en Loteado',
                  items: diff.enStockNoLoteadoItems,
                  emptyText: 'No hay diferencias en este grupo.',
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  searchText: _searchController.text,
                ),
              ],
            ),
          );
        },
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error obteniendo datos: $error'),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _onExportAction(
    _ExportAction action,
    LoteadoStockDiff diff,
    AsyncValue<DateTime?> lastSyncAsync,
  ) async {
    try {
      if (diff.diffRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay discrepancias para exportar.')),
          );
        }
        return;
      }

      final lastSyncDate = lastSyncAsync.valueOrNull;

      if (action == _ExportAction.csv) {
        await _exportCsv(diff);
      } else {
        await _exportPdf(diff, lastSyncDate);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _ExportAction.csv
                  ? 'CSV generado correctamente.'
                  : 'PDF generado correctamente.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  Future<void> _exportCsv(LoteadoStockDiff diff) async {
    final csvContent = _buildCsv(diff.diffRows);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${Directory.systemTemp.path}/diferencias_$timestamp.csv');
    await file.writeAsString(csvContent, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Diferencias Loteado vs Stock',
      text: 'Diferencias Loteado vs Stock',
    );
  }

  Future<void> _exportPdf(LoteadoStockDiff diff, DateTime? lastSync) async {
    final bytes = await _buildPdfBytes(diff, lastSync);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${Directory.systemTemp.path}/diferencias_$timestamp.pdf');
    await file.writeAsBytes(bytes);

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'diferencias_$timestamp.pdf',
    );
  }

  String _buildCsv(List<DiffRow> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
      'origen,docId,idpalet,variedad,confeccion,camara,estanteria,nivel',
    );

    String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';

    for (final r in rows) {
      buffer.writeln([
        esc(r.origen),
        esc(r.docId),
        esc(r.idpalet),
        esc(r.variedad),
        esc(r.confeccion),
        esc(r.camara),
        esc(r.estanteria),
        esc(r.nivel),
      ].join(','));
    }
    return buffer.toString();
  }

  Future<Uint8List> _buildPdfBytes(
    LoteadoStockDiff diff,
    DateTime? lastSync,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    final summaryHeaders = ['Métrica', 'Valor'];
    final groups = agruparPorCampos([
      ...diff.enLoteadoNoStockItems,
      ...diff.enStockNoLoteadoItems,
    ]).values.toList()
      ..sort((a, b) => b.items.length.compareTo(a.items.length));

    doc.addPage(
      pw.MultiPage(
        build: (context) {
          final content = <pw.Widget>[
            pw.Text(
              'Comparar Loteado vs Stock',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Generado: ${formatter.format(now)}'),
            pw.Text(
              lastSync != null
                  ? 'Última actualización Loteado: ${formatter.format(lastSync)}'
                  : 'Última actualización Loteado: desconocida',
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: summaryHeaders,
              data: [
                ['Total Loteado', diff.totalLoteado.toString()],
                ['Total Stock (Ocupado)', diff.totalStockOcupado.toString()],
                [
                  'En Loteado pero no en Stock',
                  diff.docsEnLoteadoNoStock.length.toString(),
                ],
                [
                  'En Stock pero no en Loteado',
                  diff.docsEnStockNoLoteado.length.toString(),
                ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 16),
          ];

          for (final group in groups) {
            content.add(
              pw.Text(
                group.key,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            content.add(pw.SizedBox(height: 6));
            content.add(
              pw.Table.fromTextArray(
                headers: const [
                  'Origen',
                  'docId',
                  'idpalet',
                  'Variedad',
                  'Confección',
                  'Cámara',
                  'Estantería',
                  'Nivel',
                ],
                data: group.items.map((item) {
                  return [
                    item.origen,
                    item.docId,
                    item.idpalet ?? '',
                    item.variedad ?? '',
                    item.confeccion ?? '',
                    item.camara ?? '',
                    item.estanteria ?? '',
                    item.nivel ?? '',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                columnWidths: {
                  0: const pw.FixedColumnWidth(55),
                  1: const pw.FlexColumnWidth(),
                  2: const pw.FixedColumnWidth(80),
                  3: const pw.FixedColumnWidth(70),
                  4: const pw.FixedColumnWidth(80),
                  5: const pw.FixedColumnWidth(55),
                  6: const pw.FixedColumnWidth(70),
                  7: const pw.FixedColumnWidth(50),
                },
              ),
            );
            content.add(pw.SizedBox(height: 12));
          }

          return content;
        },
      ),
    );

    return doc.save();
  }
}

class _DiffSection extends StatelessWidget {
  const _DiffSection({
    required this.title,
    required this.items,
    required this.emptyText,
    required this.selectedVariedad,
    required this.selectedCamara,
    required this.searchText,
  });

  final String title;
  final List<PaletDiffItem> items;
  final String emptyText;
  final String? selectedVariedad;
  final String? selectedCamara;
  final String searchText;

  @override
  Widget build(BuildContext context) {
    final search = searchText.trim().toLowerCase();
    final filtered = items.where((item) {
      if (selectedVariedad != null &&
          (item.variedad ?? 'Sin variedad') != selectedVariedad) {
        return false;
      }
      if (selectedCamara != null &&
          (item.camara ?? 'Sin cámara') != selectedCamara) {
        return false;
      }
      if (search.isNotEmpty &&
          !(item.idpalet?.toLowerCase().contains(search) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    final grouped = agruparPorCampos(filtered).values.toList()
      ..sort((a, b) => b.items.length.compareTo(a.items.length));

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title),
        children: [
          if (grouped.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyText),
            )
          else
            ...grouped.map(
              (group) => ExpansionTile(
                title: Text(group.key),
                trailing: CircleAvatar(
                  radius: 14,
                  child: Text(group.items.length.toString()),
                ),
                children: group.items
                    .map(
                      (item) => ListTile(
                        title: Text(item.idpalet ?? 'Sin idpalet'),
                        subtitle: Text(_buildSubtitle(item)),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _buildSubtitle(PaletDiffItem item) {
    final parts = <String>[];
    void add(String label, String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return;
      parts.add('$label: $text');
    }

    add('docId', item.docId);
    add('Variedad', item.variedad);
    add('Confección', item.confeccion);
    add('Cámara', item.camara);
    add('Estantería', item.estanteria);
    add('Nivel', item.nivel);

    if (parts.isEmpty) return 'Sin datos adicionales';
    return parts.join(' · ');
  }
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.variedadOptions,
    required this.camaraOptions,
    required this.selectedVariedad,
    required this.selectedCamara,
    required this.searchController,
    required this.onVariedadChanged,
    required this.onCamaraChanged,
    required this.onSearchChanged,
  });

  final List<String> variedadOptions;
  final List<String> camaraOptions;
  final String? selectedVariedad;
  final String? selectedCamara;
  final TextEditingController searchController;
  final ValueChanged<String?> onVariedadChanged;
  final ValueChanged<String?> onCamaraChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: selectedVariedad ?? 'Todas',
                    decoration: const InputDecoration(
                      labelText: 'Variedad',
                      border: OutlineInputBorder(),
                    ),
                    items: variedadOptions
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v),
                          ),
                        )
                        .toList(),
                    onChanged: onVariedadChanged,
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: selectedCamara ?? 'Todas',
                    decoration: const InputDecoration(
                      labelText: 'Cámara',
                      border: OutlineInputBorder(),
                    ),
                    items: camaraOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: onCamaraChanged,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar idpalet',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LastSyncText extends StatelessWidget {
  const _LastSyncText({required this.asyncValue});

  final AsyncValue<DateTime?> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (date) => Text(
        date != null
            ? 'Última actualización Loteado: ${DateFormat("dd/MM/yyyy HH:mm").format(date)}'
            : 'Última actualización Loteado: desconocida',
      ),
      loading: () => const Text('Última actualización Loteado: cargando...'),
      error: (_, __) => const Text('Última actualización Loteado: error'),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

enum _ExportAction { csv, pdf }
