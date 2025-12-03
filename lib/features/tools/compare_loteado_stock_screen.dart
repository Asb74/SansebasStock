import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compare_loteado_stock_provider.dart';

class CompareLoteadoStockScreen extends ConsumerWidget {
  const CompareLoteadoStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisonAsync = ref.watch(compareLoteadoStockProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparar Loteado vs Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(compareLoteadoStockProvider);
            },
          ),
        ],
      ),
      body: comparisonAsync.when(
        data: (diff) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(compareLoteadoStockProvider);
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
                _DiffSection(
                  title: 'En Loteado pero NO en Stock (Hueco=Ocupado)',
                  docs: diff.docsEnLoteadoNoStock,
                  emptyText: 'No hay diferencias en este grupo.',
                ),
                const SizedBox(height: 12),
                _DiffSection(
                  title: 'En Stock (Ocupado) pero NO en Loteado',
                  docs: diff.docsEnStockNoLoteado,
                  emptyText: 'No hay diferencias en este grupo.',
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
}

class _DiffSection extends StatelessWidget {
  const _DiffSection({
    required this.title,
    required this.docs,
    required this.emptyText,
  });

  final String title;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title),
        children: [
          if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyText),
            )
          else
            ...docs.map(
              (doc) => ListTile(
                title: Text(doc.id),
                subtitle: Text(_buildSubtitle(doc.data())),
              ),
            ),
        ],
      ),
    );
  }

  String _buildSubtitle(Map<String, dynamic> data) {
    final parts = <String>[];
    void addIfPresent(String key) {
      final value = data[key];
      if (value == null) return;
      final text = value.toString();
      if (text.isEmpty) return;
      parts.add('$key: $text');
    }

    addIfPresent('idpalet');
    addIfPresent('lote');
    addIfPresent('Hueco');
    addIfPresent('CAMARA');
    addIfPresent('ESTANTERIA');
    addIfPresent('POSICION');

    if (parts.isEmpty) return 'Sin datos adicionales';
    return parts.join(' · ');
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
