import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'cmr_models.dart';
import 'cmr_pdf_generator.dart';
import 'cmr_pdf_preview_screen.dart';

enum CmrPdfAction { view, print, share }

Future<Uint8List> generarCmrPdf(CmrPedido pedido) {
  return CmrPdfGenerator.generate(
    pedido: pedido,
    firestore: FirebaseFirestore.instance,
  );
}

Future<void> showCmrPdfActions({
  required BuildContext context,
  required CmrPedido pedido,
}) async {
  final action = await showModalBottomSheet<CmrPdfAction>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Ver PDF'),
              onTap: () => Navigator.of(sheetContext).pop(CmrPdfAction.view),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Imprimir'),
              onTap: () => Navigator.of(sheetContext).pop(CmrPdfAction.print),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Compartir'),
              onTap: () => Navigator.of(sheetContext).pop(CmrPdfAction.share),
            ),
          ],
        ),
      );
    },
  );

  if (action == null) return;

  try {
    final data = await generarCmrPdf(pedido);
    if (!context.mounted) return;

    switch (action) {
      case CmrPdfAction.view:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CmrPdfPreviewScreen(
              data: data,
              title: 'CMR ${pedido.idPedidoLora}',
            ),
          ),
        );
        break;
      case CmrPdfAction.print:
        await CmrPdfGenerator.printPdf(data);
        break;
      case CmrPdfAction.share:
        await Printing.sharePdf(
          bytes: data,
          filename: 'CMR_${pedido.idPedidoLora}.pdf',
        );
        break;
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo generar el CMR: $error')),
    );
  }
}
