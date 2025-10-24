import 'package:flutter/material.dart';

import 'storage/storage_list_screen.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.warehouse_outlined),
            title: const Text('Cámaras (Storage)'),
            subtitle: const Text('Crear y dimensionar cámaras'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StorageListScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
