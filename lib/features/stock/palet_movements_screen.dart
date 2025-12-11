import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/stock_logs_providers.dart';

class PaletMovementsScreen extends ConsumerWidget {
  const PaletMovementsScreen({super.key, required this.palletId});

  final String palletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(palletMovementsProvider(palletId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Movimientos $palletId'),
      ),
      body: movementsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text('Sin movimientos registrados.'));
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(log.timestamp);
              final userLabel = log.userName ?? log.userEmail ?? 'Usuario desconocido';
              final fromText = log.from ?? '';
              final toText = log.to ?? '';
              return ListTile(
                title: Text('${log.campo}: "$fromText" → "$toText"'),
                subtitle: Text('$formattedDate · $userLabel'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error al cargar movimientos: $error'),
          ),
        ),
      ),
    );
  }
}
