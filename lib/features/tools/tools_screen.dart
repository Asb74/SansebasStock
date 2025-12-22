import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../cmr/cmr_home_screen.dart';

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
        ],
      ),
    );
  }
}
