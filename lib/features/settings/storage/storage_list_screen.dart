import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_providers.dart';
import 'storage_service.dart';

class StorageListScreen extends ConsumerWidget {
  const StorageListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(storageListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cámaras')),
      body: listAsync.when(
        data: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = items[i];
            return ListTile(
              leading: CircleAvatar(child: Text(c.camara)),
              title: Text('Cámara ${c.camara}'),
              subtitle: Text('Estanterías: ${c.estanterias} · Niveles: ${c.niveles}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showForm(
                      context,
                      ref,
                      camara: c.camara,
                      est: c.estanterias,
                      niv: c.niveles,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Eliminar cámara'),
                          content: Text('¿Eliminar la cámara ${c.camara}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Eliminar'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref.read(storageServiceProvider).delete(c.camara);
                        ref.invalidate(storageListProvider);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cámara'),
      ),
    );
  }

  Future<void> _showForm(
    BuildContext context,
    WidgetRef ref, {
    String? camara,
    int? est,
    int? niv,
  }) async {
    final svc = ref.read(storageServiceProvider);
    final camaraCtrl = TextEditingController(text: camara ?? '');
    final estCtrl = TextEditingController(text: est?.toString() ?? '');
    final nivCtrl = TextEditingController(text: niv?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                camara == null ? 'Nueva cámara' : 'Editar cámara',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: camaraCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de cámara (01,02,...)',
                ),
                keyboardType: TextInputType.number,
                maxLength: 2,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  final n = int.tryParse(v);
                  if (n == null || n <= 0) return 'Valor inválido';
                  return null;
                },
              ),
              TextFormField(
                controller: estCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de estanterías',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Valor inválido';
                  return null;
                },
              ),
              TextFormField(
                controller: nivCtrl,
                decoration: const InputDecoration(labelText: 'Niveles'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final id = camaraCtrl.text.padLeft(2, '0');
                        await svc.upsert(
                          camara: id,
                          estanterias: int.parse(estCtrl.text),
                          niveles: int.parse(nivCtrl.text),
                        );
                        if (context.mounted) Navigator.pop(ctx);
                        ref.invalidate(storageListProvider);
                      },
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
