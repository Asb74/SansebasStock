import 'dart:math';

import 'package:flutter/material.dart';

class HuecoOcupado {
  const HuecoOcupado({
    required this.estanteria,
    required this.posicion,
    required this.pallet,
    required this.data,
    required this.documentId,
  });

  final int estanteria;
  final int posicion;
  final String pallet;
  final Map<String, dynamic> data;
  final String documentId;
}

class CameraPlan extends StatefulWidget {
  const CameraPlan({
    super.key,
    required this.estanterias,
    required this.huecosPorEst,
    required this.ocupados,
  });

  final int estanterias;
  final int huecosPorEst;
  final List<HuecoOcupado> ocupados;

  @override
  State<CameraPlan> createState() => _CameraPlanState();
}

class _CameraPlanState extends State<CameraPlan> {
  final TransformationController _transformationController = TransformationController();
  List<_HuecoHit> _hits = const [];

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTap(Offset localPosition) {
    if (_hits.isEmpty) return;
    final scenePoint = _transformationController.toScene(localPosition);
    for (final hit in _hits) {
      if (hit.rect.contains(scenePoint)) {
        _showHuecoDialog(hit.data);
        break;
      }
    }
  }

  void _showHuecoDialog(HuecoOcupado hueco) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final entries = hueco.data.entries
            .where((entry) => entry.key != 'ESTANTERIA' && entry.key != 'POSICION')
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return AlertDialog(
          title: Text(hueco.pallet.isEmpty ? 'Hueco ocupado' : 'Palet ${hueco.pallet}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estantería: E${hueco.estanteria}'),
                Text('Posición: P${hueco.posicion}'),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Text('Sin información adicional')
                else ...entries.map((entry) {
                  final value = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${entry.key}: ${value ?? '-'}'),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final painter = CameraPlanPainter(
      estanterias: max(widget.estanterias, 0),
      huecosPorEst: max(widget.huecosPorEst, 0),
      ocupados: widget.ocupados,
      onHitsCalculated: (hits) => _hits = hits,
    );

    final size = painter.canvasSize;

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 6.0,
      boundaryMargin: const EdgeInsets.all(200),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _handleTap(details.localPosition),
        child: CustomPaint(
          size: size,
          painter: painter,
        ),
      ),
    );
  }
}

class CameraPlanPainter extends CustomPainter {
  CameraPlanPainter({
    required this.estanterias,
    required this.huecosPorEst,
    required this.ocupados,
    this.onHitsCalculated,
  })  : canvasSize = _computeCanvasSize(estanterias, huecosPorEst);

  final int estanterias;
  final int huecosPorEst;
  final List<HuecoOcupado> ocupados;
  final void Function(List<_HuecoHit>)? onHitsCalculated;

  static const double huecoWidth = 28;
  static const double huecoHeight = 36;
  static const double rackPadding = 8;
  static const double estanteriaGap = 16;
  static const double aisleWidth = 80;
  static const double rackLabelHeight = 16;
  static const double padding = 24;

  final Size canvasSize;

  static Size _computeCanvasSize(int estanterias, int huecosPorEst) {
    final leftCount = estanterias ~/ 2;
    final rightCount = estanterias - leftCount;
    final rackWidth = huecoWidth * huecosPorEst + rackPadding * 2;
    final leftWidth = leftCount * rackWidth + max(0, leftCount - 1) * estanteriaGap;
    final rightWidth = rightCount * rackWidth + max(0, rightCount - 1) * estanteriaGap;
    final canvasWidth = padding + leftWidth + aisleWidth + rightWidth + padding;
    final canvasHeight = padding + rackLabelHeight + rackPadding * 2 + huecoHeight + padding;
    return Size(canvasWidth, canvasHeight);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hits = <_HuecoHit>[];

    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final leftCount = estanterias ~/ 2;
    final rightCount = estanterias - leftCount;
    final rackWidth = huecoWidth * huecosPorEst + rackPadding * 2;
    final leftWidth = leftCount * rackWidth + max(0, leftCount - 1) * estanteriaGap;
    final rightWidth = rightCount * rackWidth + max(0, rightCount - 1) * estanteriaGap;

    final rackTop = padding + rackLabelHeight;
    final rackHeight = rackPadding * 2 + huecoHeight;

    final aisleLeft = padding + leftWidth;
    final aisleRect = Rect.fromLTWH(aisleLeft, padding, aisleWidth, size.height - padding * 2);
    final aislePaint = Paint()..color = Colors.grey.shade200;
    canvas.drawRect(aisleRect, aislePaint);

    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.blueGrey.shade200;

    final slotPaint = Paint()..color = Colors.redAccent;

    final ocupadosPorEstanteria = <int, List<HuecoOcupado>>{};
    for (final hueco in ocupados) {
      if (hueco.estanteria <= 0 || hueco.posicion <= 0) continue;
      ocupadosPorEstanteria.putIfAbsent(hueco.estanteria, () => []).add(hueco);
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
    );

    final rackLabelStyle = TextStyle(
      color: Colors.blueGrey.shade700,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    final palletTextStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 10,
    );

    final infoTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 8,
    );

    void drawRack({
      required int estanteriaIndex,
      required double x,
      required bool isLeft,
    }) {
      final estanteriaNumber = estanteriaIndex + 1;
      final rackRect = Rect.fromLTWH(x, rackTop, rackWidth, rackHeight);
      canvas.drawRect(rackRect, framePaint);

      // Draw label
      final label = 'E$estanteriaNumber';
      textPainter.text = TextSpan(text: label, style: rackLabelStyle);
      textPainter.layout(minWidth: 0, maxWidth: rackWidth);
      final labelOffset = Offset(
        rackRect.left + (rackRect.width - textPainter.width) / 2,
        padding + (rackLabelHeight - textPainter.height) / 2,
      );
      textPainter.paint(canvas, labelOffset);

      final huecos = ocupadosPorEstanteria[estanteriaNumber] ?? const [];
      for (final hueco in huecos) {
        double slotLeft;
        if (isLeft) {
          slotLeft = rackRect.left + rackPadding + (hueco.posicion - 1) * huecoWidth;
        } else {
          slotLeft = rackRect.left + rackPadding + (huecosPorEst - hueco.posicion) * huecoWidth;
        }
        final slotRect = Rect.fromLTWH(slotLeft, rackRect.top + rackPadding, huecoWidth, huecoHeight);
        canvas.drawRect(slotRect, slotPaint);

        hits.add(_HuecoHit(rect: slotRect, data: hueco));

        // Pallet label
        if (hueco.pallet.isNotEmpty) {
          textPainter.text = TextSpan(text: hueco.pallet, style: palletTextStyle);
          textPainter.layout(minWidth: 0, maxWidth: huecoWidth);
          final palletOffset = Offset(
            slotRect.left + (slotRect.width - textPainter.width) / 2,
            slotRect.top + 4,
          );
          textPainter.paint(canvas, palletOffset);
        }

        final infoLabel = 'E${hueco.estanteria}·P${hueco.posicion}';
        textPainter.text = TextSpan(text: infoLabel, style: infoTextStyle);
        textPainter.layout(minWidth: 0, maxWidth: huecoWidth);
        final infoOffset = Offset(
          slotRect.left + (slotRect.width - textPainter.width) / 2,
          slotRect.bottom - textPainter.height - 4,
        );
        textPainter.paint(canvas, infoOffset);
      }
    }

    for (var i = 0; i < leftCount; i++) {
      final x = padding + i * (rackWidth + estanteriaGap);
      drawRack(estanteriaIndex: i, x: x, isLeft: true);
    }

    final rightStartX = padding + leftWidth + aisleWidth;
    for (var j = 0; j < rightCount; j++) {
      final x = rightStartX + j * (rackWidth + estanteriaGap);
      final estanteriaIndex = leftCount + j;
      drawRack(estanteriaIndex: estanteriaIndex, x: x, isLeft: false);
    }

    onHitsCalculated?.call(List<_HuecoHit>.unmodifiable(hits));
  }

  @override
  bool shouldRepaint(covariant CameraPlanPainter oldDelegate) {
    return estanterias != oldDelegate.estanterias ||
        huecosPorEst != oldDelegate.huecosPorEst ||
        ocupados != oldDelegate.ocupados;
  }
}

class _HuecoHit {
  const _HuecoHit({required this.rect, required this.data});

  final Rect rect;
  final HuecoOcupado data;
}
