import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'volcado_scan_screen.dart';

class VolcadoDetalleLoteScreen extends StatelessWidget {
  const VolcadoDetalleLoteScreen({super.key, required this.loteId});

  final String loteId;

  String buildStockDocId(String paletId) => '1$paletId';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('Lotes').doc(loteId).snapshots(),
      builder: (context, snapshot) {
        Widget body;
        Map<String, dynamic>? palets;
        String? estado;
        var canEdit = false;

        if (snapshot.hasError) {
          body = const Center(
            child: Text('No se pudo cargar el lote.'),
          );
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          body = const Center(
            child: CircularProgressIndicator(),
          );
        } else {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          palets = data?['palets'] as Map<String, dynamic>?;
          estado = data?['estado']?.toString();
          canEdit = estado == 'ABIERTO' || estado == 'EN_CURSO';

          if (palets == null || palets.isEmpty) {
            body = const Center(
              child: Text('No hay palets añadidos'),
            );
          } else {
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

            body = ListView.separated(
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
                            const Text(
                              'P/P:',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 8),
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
                    trailing: IconButton(
                      tooltip: canEdit
                          ? 'Eliminar palet'
                          : 'No se puede eliminar un palet con el lote cerrado',
                      onPressed: canEdit
                          ? () async {
                              final shouldDelete = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Eliminar palet'),
                                  content: Text(
                                    '¿Quieres eliminar el palet $paletId del lote?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              );

                              if (shouldDelete != true) {
                                return;
                              }

                              final loteRef = FirebaseFirestore.instance
                                  .collection('Lotes')
                                  .doc(loteId);
                              final stockDocId = buildStockDocId(paletId);
                              final stockRef = FirebaseFirestore.instance
                                  .collection('Stock')
                                  .doc(stockDocId);
                              final paletKey = paletId.replaceAll('.', '_');
                              try {
                                await FirebaseFirestore.instance
                                    .runTransaction((transaction) async {
                                  transaction.update(loteRef, {
                                    'palets.$paletKey': FieldValue.delete(),
                                  });
                                  transaction.update(stockRef, {
                                    'HUECO': 'Ocupado',
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });
                                });
                              } catch (_) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo eliminar el palet.',
                                    ),
                                  ),
                                );
                              }
                            }
                          : null,
                      icon: Icon(
                        Icons.delete_outline,
                        color: canEdit
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                );
              },
            );
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalle de lote'),
          ),
          body: body,
          bottomNavigationBar: canEdit
              ? SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () async {
                      final paletsMap = palets ?? <String, dynamic>{};
                      final hasPending = paletsMap.values.any((palet) {
                        final paletData = palet as Map<String, dynamic>?;
                        final pp = paletData?['p_p'];
                        return pp == null || pp == 'F';
                      });

                      if (hasPending) {
                        await showDialog<void>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              content: const Text(
                                'Existen palets pendientes de marcar P/P',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Aceptar'),
                                ),
                              ],
                            );
                          },
                        );
                        return;
                      }

                      await FirebaseFirestore.instance
                          .collection('Lotes')
                          .doc(loteId)
                          .update({
                        'estado': 'CERRADO',
                        'fechaCierre': FieldValue.serverTimestamp(),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Finalizar lote'),
                  ),
                )
              : null,
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
      },
    );
  }
}
