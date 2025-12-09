import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AssignStorageRowsScreen extends ConsumerWidget {
  const AssignStorageRowsScreen({
    super.key,
    required this.cameraId,
  });

  final String cameraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurar almacenamiento – Cámara $cameraId'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aquí se configurarán las filas de almacenamiento para esta cámara.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
