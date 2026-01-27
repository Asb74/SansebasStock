import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'volcado_scan_screen.dart';

class VolcadoDetalleLoteScreen extends StatelessWidget {
  const VolcadoDetalleLoteScreen({super.key, required this.loteId});

  final String loteId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de lote'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream:
            FirebaseFirestore.instance.collection('Lotes').doc(loteId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudo cargar el lote.'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final palets = data?['palets'] as Map<String, dynamic>?;

          if (palets == null || palets.isEmpty) {
            return const Center(
              child: Text('No hay palets añadidos'),
            );
          }

          final entries = palets.entries.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final paletId = entry.key;
              final paletData = entry.value as Map<String, dynamic>?;
              final neto = paletData?['neto']?.toString() ?? '-';
              final cajas = paletData?['cajas']?.toString() ?? '-';
              final pedido = paletData?['pedido']?.toString() ?? '-';
              final calibre = paletData?['calibre']?.toString() ?? '-';
              final tipo = paletData?['tipo']?.toString() ?? '-';
              final pp = paletData?['P_P']?.toString() ?? '-';

              return Card(
                child: ListTile(
                  title: Text('Palet: $paletId'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Neto: $neto'),
                      Text('Cajas: $cajas'),
                      Text('Pedido: $pedido'),
                      Text('Calibre: $calibre'),
                      Text('Tipo: $tipo'),
                      Text('P_P: $pp'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VolcadoScanScreen(loteId: loteId),
            ),
          );
        },
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}
