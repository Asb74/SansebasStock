import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        ],
      ),
    );
  }
}
