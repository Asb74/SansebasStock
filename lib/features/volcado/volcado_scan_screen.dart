import 'package:flutter/material.dart';

class VolcadoScanScreen extends StatelessWidget {
  const VolcadoScanScreen({super.key, required this.loteId});

  final String loteId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear palet'),
      ),
      body: const Center(
        child: Text('Escaneo pendiente'),
      ),
    );
  }
}
