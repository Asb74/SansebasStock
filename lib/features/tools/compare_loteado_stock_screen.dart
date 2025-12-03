import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:sansebas_stock/features/ops/qr_scan_screen.dart';

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
  String? _selectedMarca;
  late final TextEditingController _searchController;

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS); // ignore: dead_code_on_web

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

  Future<void> _scanQr() async {
    if (!_isMobile) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(returnScanResult: true),
      ),
    );

    if (result != null && mounted) {
      _searchController.text = result;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final comparisonAsync = ref.watch(compareLoteadoStockProvider);
    final lastSyncAsync = ref.watch(lastLoteadoSyncProvider);
    final numberFormat = NumberFormat.decimalPattern('es_ES');

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
          final marcaOptions = ['Todas', ...diff.marcaOptions];
          final searchText = _searchController.text;

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
                          label: 'Neto Loteado',
                          value: '${numberFormat.format(diff.totalNetoLoteado)} kg',
                        ),
                        _SummaryRow(
                          label: 'Total Stock (Hueco=Ocupado)',
                          value: diff.totalStockOcupado.toString(),
                        ),
                        _SummaryRow(
                          label: 'Neto Stock (Hueco=Ocupado)',
                          value:
                              '${numberFormat.format(diff.totalNetoStockOcupado)} kg',
                        ),
                        _SummaryRow(
                          label: 'Caso 1 – En Loteado y NO en Stock',
                          value: diff.case1LoteadoSinStock.length.toString(),
                        ),
                        _SummaryRow(
                          label: 'Caso 2 – En Loteado + Stock Libre',
                          value: diff.case2LoteadoMasLibre.length.toString(),
                        ),
                        _SummaryRow(
                          label: 'Caso 3 – En Stock (Ocupado) sin Loteado',
                          value: diff.case3StockOcupadoSinLoteado.length
                              .toString(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FiltersRow(
                  variedadOptions: variedadOptions,
                  camaraOptions: camaraOptions,
                  marcaOptions: marcaOptions,
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  selectedMarca: _selectedMarca,
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
                  onMarcaChanged: (value) {
                    setState(() {
                      _selectedMarca = value == 'Todas' ? null : value;
                    });
                  },
                  onSearchChanged: (value) {
                    setState(() {});
                  },
                  onQrTap: _isMobile ? _scanQr : null,
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  baseTitle: 'Caso 1 – En Loteado y NO en Stock',
                  items: diff.case1LoteadoSinStock,
                  emptyText: 'No hay palets en esta casuística.',
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  selectedMarca: _selectedMarca,
                  searchText: searchText,
                  numberFormat: numberFormat,
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  baseTitle: 'Caso 2 – En Loteado y en Stock con Hueco=Libre',
                  items: diff.case2LoteadoMasLibre,
                  emptyText: 'No hay palets en esta casuística.',
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  selectedMarca: _selectedMarca,
                  searchText: searchText,
                  numberFormat: numberFormat,
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  baseTitle:
                      'Caso 3 – En Stock (Hueco=Ocupado) y NO en Loteado',
                  items: diff.case3StockOcupadoSinLoteado,
                  emptyText: 'No hay palets en esta casuística.',
                  selectedVariedad: _selectedVariedad,
                  selectedCamara: _selectedCamara,
                  selectedMarca: _selectedMarca,
                  searchText: searchText,
                  numberFormat: numberFormat,
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
    CompareLoteadoStockResult diff,
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

  Future<void> _exportCsv(CompareLoteadoStockResult diff) async {
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

  Future<void> _exportPdf(
    CompareLoteadoStockResult diff,
    DateTime? lastSync,
  ) async {
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
      'caso,origen,palletNumber,docId,variedad,confeccion,camara,estanteria,nivel,hueco',
    );

    String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';

    for (final r in rows) {
      buffer.writeln([
        esc(r.caseNumber.toString()),
        esc(r.origen),
        esc(r.palletNumber),
        esc(r.docId),
        esc(r.variedad),
        esc(r.confeccion),
        esc(r.camara),
        esc(r.estanteria),
        esc(r.nivel),
        esc(r.hueco),
      ].join(','));
    }
    return buffer.toString();
  }

  Future<Uint8List> _buildPdfBytes(
    CompareLoteadoStockResult diff,
    DateTime? lastSync,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    final summaryHeaders = ['Métrica', 'Valor'];
    final rowsByCase = <int, List<DiffRow>>{
      1: diff.diffRows.where((r) => r.caseNumber == 1).toList(),
      2: diff.diffRows.where((r) => r.caseNumber == 2).toList(),
      3: diff.diffRows.where((r) => r.caseNumber == 3).toList(),
    };
    final caseTitles = {
      1: 'Caso 1 – En Loteado y NO están en Stock',
      2: 'Caso 2 – En Loteado y en Stock con Hueco=Libre',
      3: 'Caso 3 – En Stock (Hueco=Ocupado) y NO están en Loteado',
    };

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
                [caseTitles[1]!, rowsByCase[1]!.length.toString()],
                [caseTitles[2]!, rowsByCase[2]!.length.toString()],
                [caseTitles[3]!, rowsByCase[3]!.length.toString()],
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

          for (final entry in rowsByCase.entries) {
            final title = caseTitles[entry.key] ?? 'Caso ${entry.key}';
            final rows = entry.value;

            content.add(
              pw.Text(
                '$title (${rows.length})',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            content.add(pw.SizedBox(height: 6));
            if (rows.isEmpty) {
              content.add(pw.Text('Sin palets en este caso.'));
            } else {
              content.add(
                pw.Table.fromTextArray(
                  headers: const [
                    'Caso',
                    'Origen',
                    'Pallet',
                    'docId',
                    'Variedad',
                    'Confección',
                    'Cámara',
                    'Estantería',
                    'Nivel',
                    'Hueco',
                  ],
                  data: rows.map((r) {
                    return [
                      r.caseNumber.toString(),
                      r.origen,
                      r.palletNumber,
                      r.docId,
                      r.variedad ?? '',
                      r.confeccion ?? '',
                      r.camara ?? '',
                      r.estanteria ?? '',
                      r.nivel ?? '',
                      r.hueco ?? '',
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(35),
                    1: const pw.FixedColumnWidth(65),
                    2: const pw.FixedColumnWidth(80),
                    3: const pw.FlexColumnWidth(),
                    4: const pw.FixedColumnWidth(70),
                    5: const pw.FixedColumnWidth(70),
                    6: const pw.FixedColumnWidth(55),
                    7: const pw.FixedColumnWidth(70),
                    8: const pw.FixedColumnWidth(50),
                    9: const pw.FixedColumnWidth(55),
                  },
                ),
              );
            }
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
    required this.baseTitle,
    required this.items,
    required this.emptyText,
    required this.selectedVariedad,
    required this.selectedCamara,
    required this.selectedMarca,
    required this.searchText,
    required this.numberFormat,
  });

  final String baseTitle;
  final List<PaletDiffItem> items;
  final String emptyText;
  final String? selectedVariedad;
  final String? selectedCamara;
  final String? selectedMarca;
  final String searchText;
  final NumberFormat numberFormat;

  @override
  Widget build(BuildContext context) {
    final query = searchText.trim();
    final filtered = items.where((item) {
      if (selectedVariedad != null &&
          (item.variedad ?? 'Sin variedad') != selectedVariedad) {
        return false;
      }
      final cam = item.camara ?? item.stockCamara ?? 'Sin cámara';
      if (selectedCamara != null && cam != selectedCamara) {
        return false;
      }
      if (selectedMarca != null && (item.marca ?? '') != selectedMarca) {
        return false;
      }
      if (query.isNotEmpty && !item.palletNumber.contains(query)) {
        return false;
      }
      return true;
    }).toList();

    final sumNeto =
        filtered.fold<num>(0, (previousValue, element) => previousValue + element.neto);

    final grouped = agruparPorCampos(filtered).values.toList()
      ..sort((a, b) => b.items.length.compareTo(a.items.length));

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          '$baseTitle (Palets: ${filtered.length} · Neto: ${numberFormat.format(sumNeto)} kg)',
        ),
        trailing: CircleAvatar(
          radius: 14,
          child: Text(filtered.length.toString()),
        ),
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
                        title: Text(item.palletNumber),
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

    add('Origen', item.origen);
    add('docId', item.docId);
    add('Variedad', item.variedad);
    add('Confección', item.confeccion);
    add('Cámara (Loteado)', item.camara);
    add('Cámara (Stock)', item.stockCamara);
    add('Estantería', item.estanteria ?? item.stockEstanteria);
    add('Nivel', item.nivel ?? item.stockNivel);
    add('Hueco', item.hueco);

    if (parts.isEmpty) return 'Sin datos adicionales';
    return parts.join(' · ');
  }
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.variedadOptions,
    required this.camaraOptions,
    required this.marcaOptions,
    required this.selectedVariedad,
    required this.selectedCamara,
    required this.selectedMarca,
    required this.searchController,
    required this.onVariedadChanged,
    required this.onCamaraChanged,
    required this.onMarcaChanged,
    required this.onSearchChanged,
    this.onQrTap,
  });

  final List<String> variedadOptions;
  final List<String> camaraOptions;
  final List<String> marcaOptions;
  final String? selectedVariedad;
  final String? selectedCamara;
  final String? selectedMarca;
  final TextEditingController searchController;
  final ValueChanged<String?> onVariedadChanged;
  final ValueChanged<String?> onCamaraChanged;
  final ValueChanged<String?> onMarcaChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onQrTap;

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
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: selectedMarca ?? 'Todas',
                    decoration: const InputDecoration(
                      labelText: 'Marca',
                      border: OutlineInputBorder(),
                    ),
                    items: marcaOptions
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m),
                          ),
                        )
                        .toList(),
                    onChanged: onMarcaChanged,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar idpalet',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: onQrTap != null
                          ? IconButton(
                              tooltip: 'Leer QR',
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: onQrTap,
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: onSearchChanged,
                    textInputAction: TextInputAction.search,
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
