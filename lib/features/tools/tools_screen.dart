import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../cmr/cmr_home_screen.dart';
import '../volcado/volcado_lotes_screen.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Herramientas'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Comparar Loteado vs Stock'),
              subtitle: const Text(
                'Detecta discrepancias entre Loteado y Stock (Hueco=Ocupado)',
              ),
              leading: const Icon(Icons.compare_arrows_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed('tools-compare'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Agrupar Boxes'),
              subtitle: const Text(
                'Agrupa varios QR de box sobre un mismo palet físico',
              ),
              leading: const Icon(Icons.inventory_2_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed('tools-agrupar-boxes'),
            ),
          ),
          const Divider(height: 28),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              title: Text(
                'Desagrupar Boxes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                'Elimina un grupo y borra su stock de referencia',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              onTap: () => context.pushNamed('tools-desagrupar-boxes'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Asignar lugar de almacenamiento'),
              subtitle: const Text(
                'Configura qué productos se almacenan en cada fila de las cámaras de recepción',
              ),
              leading: const Icon(Icons.warehouse_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed('tools-assign-storage'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('CMR'),
              subtitle: const Text('Expedir pedidos y generar CMR'),
              leading: const Icon(Icons.local_shipping_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CmrHomeScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Volcado'),
              subtitle: const Text('Asignar palets a un lote'),
              leading: const Icon(Icons.move_to_inbox_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VolcadoLotesScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
