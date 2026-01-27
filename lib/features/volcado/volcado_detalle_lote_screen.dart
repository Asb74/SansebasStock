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

          final entries = palets.entries.toList()
            ..sort((a, b) {
              final aData = a.value as Map<String, dynamic>?;
              final bData = b.value as Map<String, dynamic>?;
              final aFecha = aData?['fechaAlta'];
              final bFecha = bData?['fechaAlta'];
              if (aFecha is Timestamp && bFecha is Timestamp) {
                return bFecha.compareTo(aFecha);
              }
              return a.key.compareTo(b.key);
            });

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
              final pp = paletData?['p_p']?.toString();
              final isPending = pp == null || pp == 'F';
              final isSelected = [pp == 'S', pp == 'N'];

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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ToggleButtons(
                            isSelected: isSelected,
                            onPressed: (index) async {
                              final value = index == 0 ? 'S' : 'N';
                              final paletKey = paletId.replaceAll('.', '_');
                              try {
                                await FirebaseFirestore.instance
                                    .collection('Lotes')
                                    .doc(loteId)
                                    .update({'palets.$paletKey.p_p': value});
                              } catch (_) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo guardar P/P. Revisa conexión.',
                                    ),
                                  ),
                                );
                              }
                            },
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('S'),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('N'),
                              ),
                            ],
                          ),
                          if (isPending) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: const Text('Pendiente'),
                              backgroundColor: Colors.grey.shade200,
                              labelStyle: const TextStyle(color: Colors.grey),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
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
