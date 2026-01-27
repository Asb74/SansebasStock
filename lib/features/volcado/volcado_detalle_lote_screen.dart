import 'package:flutter/material.dart';

class VolcadoDetalleLoteScreen extends StatelessWidget {
  const VolcadoDetalleLoteScreen({super.key, required this.loteId});

  final String loteId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de lote'),
      ),
      body: Center(
        child: Text(loteId),
      ),
    );
  }
}
