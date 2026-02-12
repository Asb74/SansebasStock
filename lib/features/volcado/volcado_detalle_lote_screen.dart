import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'volcado_scan_screen.dart';

class VolcadoDetalleLoteScreen extends StatelessWidget {
  const VolcadoDetalleLoteScreen({super.key, required this.loteId});

  final String loteId;

  String buildStockDocId(String paletId) => '1$paletId';

  String _formatearFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/"
        "${fecha.month.toString().padLeft(2, '0')}/"
        "${fecha.year} "
        "${fecha.hour.toString().padLeft(2, '0')}:"
        "${fecha.minute.toString().padLeft(2, '0')}";
  }

  Widget _datoLote(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTarjetaInfoLote({
    required BuildContext context,
    required Map<String, dynamic> loteData,
  }) {
    final campana = loteData['campana']?.toString() ?? '-';
    final cultivo = loteData['cultivo']?.toString() ?? '-';
    final empresa = loteData['empresa']?.toString() ?? '-';
    final estado = loteData['estado']?.toString() ?? '-';
    final fechaCreacion = loteData['fechaCreacion'];
    final fechaCierre = loteData['fechaCierre'];
    final fechaCreacionStr = fechaCreacion is Timestamp
        ? _formatearFecha(fechaCreacion.toDate())
        : '-';
    final fechaCierreStr = fechaCierre is Timestamp
        ? _formatearFecha(fechaCierre.toDate())
        : '-';
    final abierto = estado == 'ABIERTO';
    final paletsRaw = loteData['palets'];
    final palets =
        paletsRaw is Map ? Map<String, dynamic>.from(paletsRaw) : <String, dynamic>{};
    final totalPalets = palets.length;
    final totalNeto = palets.values.fold<num>(0, (acumulado, paletData) {
      if (paletData is! Map) return acumulado;
      final neto = paletData['neto'];
      if (neto is num) {
        return acumulado + neto;
      }
      if (neto is String) {
        return acumulado + (num.tryParse(neto) ?? 0);
      }
      return acumulado;
    });
    final totalNetoStr = '${totalNeto.toStringAsFixed(0)} kg';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loteId,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _datoLote('Campaña', campana),
            _datoLote('Cultivo', cultivo),
            _datoLote('Empresa', empresa),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Estado',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Chip(
                    label: Text(estado),
                    backgroundColor:
                        abierto ? Colors.green.shade100 : Colors.grey.shade300,
                    labelStyle: TextStyle(
                      color: abierto ? Colors.green.shade900 : Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _datoLote('Fecha creación', fechaCreacionStr),
            _datoLote('Fecha cierre', fechaCierreStr),
            _datoLote('Total palets', totalPalets.toString()),
            _datoLote('Total neto', totalNetoStr),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loteRef = FirebaseFirestore.instance.collection('Lotes').doc(loteId);

    return StreamBuilder<DocumentSnapshot>(
      stream: loteRef.snapshots(),
      builder: (context, snapshot) {
        Widget body;
        Map<String, dynamic>? palets;
        String? estado;
        var canEdit = false;
        var canReopen = false;

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
          canReopen = estado == 'CERRADO';

          Widget listaPalets;
          if (palets == null || palets.isEmpty) {
            listaPalets = const Center(
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

            listaPalets = ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                    'idLote': '',
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

          body = Column(
            children: [
              _buildTarjetaInfoLote(
                context: context,
                loteData: data ?? <String, dynamic>{},
              ),
              Expanded(child: listaPalets),
            ],
          );
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

                      await loteRef.update({
                        'estado': 'CERRADO',
                        'fechaCierre': FieldValue.serverTimestamp(),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Finalizar lote'),
                  ),
                )
              : canReopen
                  ? SafeArea(
                      minimum: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        onPressed: () async {
                          await loteRef.update({
                            'estado': 'EN_CURSO',
                            'reabierto': true,
                            'fechaReapertura': FieldValue.serverTimestamp(),
                          });
                        },
                        child: const Text(
                          'Reabrir lote',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                  : null,
          floatingActionButton: canEdit
              ? FloatingActionButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VolcadoScanScreen(loteId: loteId),
                      ),
                    );
                  },
                  child: const Icon(Icons.qr_code_scanner),
                )
              : null,
        );
      },
    );
  }
}
