import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'volcado_detalle_lote_screen.dart';

class VolcadoLotesCerradosScreen extends StatelessWidget {
  const VolcadoLotesCerradosScreen({super.key});

  String _formatFecha(dynamic fechaCierre) {
    if (fechaCierre is! Timestamp) {
      return 'Sin fecha de cierre';
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(fechaCierre.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lotes cerrados'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Lotes')
            .where('estado', isEqualTo: 'CERRADO')
            .orderBy('fechaCierre', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar los lotes cerrados.'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No hay lotes cerrados.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final idPartidaRaw = data['idPartida']?.toString().trim();
              final idPartida =
                  (idPartidaRaw?.isNotEmpty ?? false) ? idPartidaRaw! : doc.id;

              final campanaRaw = data['campana']?.toString().trim();
              final campana =
                  (campanaRaw?.isNotEmpty ?? false) ? campanaRaw! : '-';

              final cultivo2Raw = data['cultivo2']?.toString().trim();
              final cultivo2 =
                  (cultivo2Raw?.isNotEmpty ?? false) ? cultivo2Raw! : '-';

              final fechaCierre = _formatFecha(data['fechaCierre']);

              return Card(
                child: ListTile(
                  title: Text(idPartida),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Campaña: $campana'),
                      Text('Producto: $cultivo2'),
                      Text('Fecha cierre: $fechaCierre'),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VolcadoDetalleLoteScreen(loteId: doc.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
