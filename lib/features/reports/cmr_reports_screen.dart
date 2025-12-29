import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../cmr/cmr_models.dart';
import '../cmr/cmr_pdf_actions.dart';

class CmrReportsScreen extends StatelessWidget {
  const CmrReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 15));
    final pedidosQuery = FirebaseFirestore.instance
        .collection('Pedidos')
        .where('Estado', isEqualTo: 'Expedido')
        .where(
          'expedidoAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
        )
        .orderBy('expedidoAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CMR expedidos'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: pedidosQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar los CMR.'),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final pedidos = docs.map(CmrPedido.fromSnapshot).toList();

          if (pedidos.isEmpty) {
            return const Center(
              child: Text('No hay CMR recientes.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pedidos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final pedido = pedidos[index];
              final expedidoAt = pedido.expedidoAt;
              final fecha = _formatFecha(expedidoAt);
              final cliente =
                  pedido.cliente.isNotEmpty ? pedido.cliente : 'Cliente sin nombre';

              return Card(
                child: ListTile(
                  title: Text(pedido.idPedidoLora),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(cliente),
                      Text('Expedido: $fecha'),
                    ],
                  ),
                  trailing: FilledButton(
                    onPressed: () => _showCmrActions(context, pedido),
                    child: const Text('Imprimir CMR'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatFecha(DateTime? fecha) {
    if (fecha == null) {
      return '—';
    }
    return DateFormat('dd/MM/yyyy').format(fecha);
  }

  Future<void> _showCmrActions(BuildContext context, CmrPedido pedido) {
    return showCmrPdfActions(context: context, pedido: pedido);
  }
}
