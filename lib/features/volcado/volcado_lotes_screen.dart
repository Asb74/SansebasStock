import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'volcado_detalle_lote_screen.dart';
import 'volcado_lotes_cerrados_screen.dart';

class VolcadoLotesScreen extends StatelessWidget {
  const VolcadoLotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Volcado'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Lotes cerrados',
            splashRadius: 22,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const VolcadoLotesCerradosScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Lotes')
            .where('estado', whereIn: const ['ABIERTO', 'EN_CURSO'])
            .orderBy('fechaCreacion', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar los lotes.'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No hay lotes disponibles.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>?;
              final idPartida = data?['idPartida']?.toString() ?? 'Sin partida';
              final estado = data?['estado']?.toString() ?? 'Sin estado';
              final timestamp = data?['fechaCreacion'];
              final fecha = timestamp is Timestamp ? timestamp.toDate() : null;
              final formattedDate = fecha != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(fecha)
                  : 'Sin fecha';
              final isEnCurso = estado == 'EN_CURSO';
              final Color? cardColor = isEnCurso
                  ? theme.colorScheme.primaryContainer.withOpacity(0.35)
                  : null;

              return Padding(
                padding: EdgeInsets.only(bottom: index == docs.length - 1 ? 0 : 12),
                child: Card(
                  color: cardColor,
                  child: ListTile(
                    title: Text(idPartida),
                    subtitle: Text('$estado · $formattedDate'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VolcadoDetalleLoteScreen(
                            loteId: doc.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
