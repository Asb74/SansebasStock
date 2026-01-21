import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'cmr_models.dart';
import 'cmr_scan_screen.dart';
import 'cmr_utils.dart';

class CmrDetailScreen extends StatefulWidget {
  const CmrDetailScreen({super.key, required this.pedidoRef});

  final DocumentReference<Map<String, dynamic>> pedidoRef;

  @override
  State<CmrDetailScreen> createState() => _CmrDetailScreenState();
}

class _CmrDetailScreenState extends State<CmrDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.pedidoRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('CMR')),
            body: const Center(child: Text('Pedido no encontrado.')),
          );
        }

        final pedidoSnapshot = snapshot.data!;
        final pedido = CmrPedido.fromSnapshot(pedidoSnapshot);
        final firestorePalets = _extractPaletsFromData(
          pedidoSnapshot.data() ?? <String, dynamic>{},
        ).toSet();
        final expected = _buildExpectedPalets(pedido);
        final expectedSet = expected.keys.toSet();
        final scanned = firestorePalets.where(expectedSet.contains).toSet();
        final total = expectedSet.length;
        final scannedCount = scanned.length;

        return Scaffold(
          appBar: AppBar(
            title: Text(pedido.idPedidoLora),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PedidoHeader(pedido: pedido),
              const SizedBox(height: 16),
              _buildCounts(total, scannedCount),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: pedido.estado == 'Expedido'
                    ? null
                    : () async {
                        await Navigator.of(context).push<CmrScanResult>(
                          MaterialPageRoute(
                            builder: (_) => CmrScanScreen(
                              pedido: pedido,
                              expectedPalets: expectedSet.toList(),
                              lineaByPalet: expected,
                              initialScanned: const <String>{},
                              initialInvalid: const <String>{},
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Iniciar escaneo'),
              ),
              if (pedido.estado == 'Expedido')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Este pedido ya fue expedido.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Palets del pedido',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._buildPaletList(expectedSet, scanned),
            ],
          ),
        );
      },
    );
  }

  List<String> _extractPaletsFromData(Map<String, dynamic> data) {
    final raw = data['palets'] ?? data['Palets'];
    if (raw is! Iterable) {
      return const [];
    }
    return raw
        .map((value) => normalizarPalet(value?.toString() ?? ''))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Map<String, int?> _buildExpectedPalets(CmrPedido pedido) {
    final Map<String, int?> map = {};
    for (final line in pedido.lineas) {
      for (final raw in line.palets) {
        final normalized = normalizePaletId(raw);
        if (normalized.isEmpty) continue;
        map.putIfAbsent(normalized, () => line.linea);
      }
    }
    return map;
  }

  Widget _buildCounts(int total, int scanned) {
    return Row(
      children: [
        Expanded(
          child: _CountCard(
            title: 'Escaneados',
            value: '$scanned',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CountCard(
            title: 'Total',
            value: '$total',
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPaletList(
    Set<String> expected,
    Set<String> scanned,
  ) {
    final items = expected.toList()..sort();
    return items.map((palet) {
      final bool isScanned = scanned.contains(palet);
      final color = isScanned ? Colors.green.shade700 : Colors.orange.shade700;
      return Card(
        child: ListTile(
          leading: Icon(
            isScanned ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
          ),
          title: Text(palet),
          subtitle: isScanned ? const Text('Escaneado') : const Text('Pendiente'),
        ),
      );
    }).toList();
  }
}

class _PedidoHeader extends StatelessWidget {
  const _PedidoHeader({required this.pedido});

  final CmrPedido pedido;

  @override
  Widget build(BuildContext context) {
    final salida = pedido.fechaSalida != null
        ? '${pedido.fechaSalida!.day.toString().padLeft(2, '0')}/'
            '${pedido.fechaSalida!.month.toString().padLeft(2, '0')}/'
            '${pedido.fechaSalida!.year}'
        : '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente: ${pedido.cliente.isNotEmpty ? pedido.cliente : '—'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Fecha salida: $salida'),
            Text('Transportista: ${pedido.transportista.isNotEmpty ? pedido.transportista : '—'}'),
            Text('Matrícula: ${pedido.matricula.isNotEmpty ? pedido.matricula : '—'}'),
            Text('Remitente: ${pedido.remitente.isNotEmpty ? pedido.remitente : '—'}'),
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
