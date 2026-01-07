import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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

class CmrPdfPayload {
  const CmrPdfPayload({
    required this.data,
    required this.file,
    required this.filename,
  });

  final Uint8List data;
  final File file;
  final String filename;
}

Future<CmrPdfPayload> buildCmrPdfPayload(CmrPedido pedido) async {
  final data = await generarCmrPdf(pedido);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'CMR_${pedido.idPedidoLora}_$timestamp.pdf';
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(data);
  return CmrPdfPayload(data: data, file: file, filename: filename);
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
    final payload = await buildCmrPdfPayload(pedido);
    if (!context.mounted) return;

    switch (action) {
      case CmrPdfAction.view:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CmrPdfPreviewScreen(
              data: payload.data,
              title: 'CMR ${pedido.idPedidoLora}',
            ),
          ),
        );
        break;
      case CmrPdfAction.print:
        await CmrPdfGenerator.printPdf(payload.data);
        break;
      case CmrPdfAction.share:
        await Share.shareXFiles(
          [XFile(payload.file.path, mimeType: 'application/pdf')],
          subject: 'CMR ${pedido.idPedidoLora}',
          text: 'CMR ${pedido.idPedidoLora}',
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
