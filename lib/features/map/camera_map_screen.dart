import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/camera_model.dart';
import '../../providers/camera_providers.dart';

final selectedLevelProvider =
    StateProvider.autoDispose.family<int, String>((ref, numero) => 1);

class CameraMapScreen extends ConsumerStatefulWidget {
  const CameraMapScreen({
    super.key,
    required this.numero,
    this.initialCamera,
  });

  factory CameraMapScreen.fromCamera(CameraModel camera) {
    return CameraMapScreen(numero: camera.displayNumero, initialCamera: camera);
  }

  final String numero;
  final CameraModel? initialCamera;

  @override
  ConsumerState<CameraMapScreen> createState() => _CameraMapScreenState();
}

class _CameraMapScreenState extends ConsumerState<CameraMapScreen> {
  late final TransformationController _controller;
  List<_SlotHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(BuildContext context, Offset localPosition) {
    if (_hits.isEmpty) return;
    final scenePoint = _controller.toScene(localPosition);
    for (final hit in _hits) {
      if (hit.rect.contains(scenePoint)) {
        _showSlotDetails(context, hit.entry);
        break;
      }
    }
  }

  void _showSlotDetails(BuildContext context, StockEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final data = entry.data;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Palet ${entry.palletCode}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Fila: F${entry.fila}'),
              Text('Posición: P${entry.posicion}'),
              if (entry.neto != null) Text('Neto: ${entry.neto}'),
              if (entry.cajas != null) Text('Cajas: ${entry.cajas}'),
              const SizedBox(height: 16),
              Text('ID: ${entry.id}'),
              const SizedBox(height: 8),
              if (data.isNotEmpty)
                TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Detalle del documento'),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: data.entries
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('${e.key}: ${e.value}'),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cerrar'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Ver todos los campos'),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraAsync = ref.watch(cameraByNumeroProvider(widget.numero));
    return cameraAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, __) => Scaffold(
        appBar: AppBar(title: Text('Cámara ${widget.numero}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No se pudo cargar la cámara.\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (cameraFromStream) {
        final camera = cameraFromStream ?? widget.initialCamera;
        if (camera == null) {
          return Scaffold(
            appBar: AppBar(title: Text('Cámara ${widget.numero}')),
            body: const Center(child: Text('La cámara no existe.')),
          );
        }

        final cameraNumero = camera.displayNumero;
        final nivelController = ref.watch(selectedLevelProvider(cameraNumero));
        final nivelActual =
            nivelController.clamp(1, math.max(camera.niveles, 1)).toInt();
        if (nivelActual != nivelController) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(selectedLevelProvider(cameraNumero).notifier).state = nivelActual;
            }
          });
        }

        final stockAsync = ref.watch(
          stockByCameraLevelProvider(
            CameraLevelKey(numero: cameraNumero, nivel: nivelActual, pasillo: camera.pasillo),
          ),
        );

        return Scaffold(
          appBar: AppBar(title: Text('Cámara ${cameraNumero}')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nivel', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(camera.niveles, (index) {
                    final nivel = index + 1;
                    final selected = nivelActual == nivel;
                    return ChoiceChip(
                      label: Text('Nivel $nivel'),
                      selected: selected,
                      onSelected: (_) {
                        if (!selected) {
                          ref.read(selectedLevelProvider(cameraNumero).notifier).state = nivel;
                        }
                      },
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: stockAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, __) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar el stock.\n$error',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    data: (occupied) {
                      return InteractiveViewer(
                        transformationController: _controller,
                        minScale: 0.6,
                        maxScale: 3.0,
                        boundaryMargin: const EdgeInsets.all(200),
                        child: ValueListenableBuilder<Matrix4>(
                          valueListenable: _controller,
                          builder: (context, matrix, _) {
                            final painter = StorageMapPainter(
                              camera: camera,
                              occupied: occupied,
                              scale: matrix.getMaxScaleOnAxis(),
                              onLayout: (hits) => _hits = hits,
                            );
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) => _handleTap(context, details.localPosition),
                              child: CustomPaint(
                                size: painter.size,
                                painter: painter,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class StorageMapPainter extends CustomPainter {
  StorageMapPainter({
    required this.camera,
    required this.occupied,
    required this.scale,
    this.onLayout,
  }) : size = _computeSize(camera);

  final CameraModel camera;
  final Map<StorageSlotCoordinate, StockEntry> occupied;
  final double scale;
  final void Function(List<_SlotHit>)? onLayout;
  final Size size;

  static const double slotSize = 46;
  static const double slotSpacing = 8;
  static const double walkwayWidth = 54;
  static const double horizontalMargin = 32;
  static const double verticalMargin = 40;
  static const double topLabelHeight = 32;
  static const double rowLabelWidth = 44;

  static Size _computeSize(CameraModel camera) {
    final blockWidth = camera.posicionesMax * slotSize +
        math.max(0, camera.posicionesMax - 1) * slotSpacing;
    final blockHeight = camera.filas * slotSize +
        math.max(0, camera.filas - 1) * slotSpacing;

    if (camera.pasillo == CameraPasillo.central) {
      final width = horizontalMargin * 2 +
          blockWidth * 2 +
          walkwayWidth +
          rowLabelWidth * 2;
      final height = verticalMargin * 2 + topLabelHeight + blockHeight;
      return Size(width, height);
    } else {
      final width = horizontalMargin * 2 + walkwayWidth + rowLabelWidth + blockWidth;
      final height = verticalMargin * 2 + topLabelHeight + blockHeight;
      return Size(width, height);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hits = <_SlotHit>[];
    final paintBackground = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, paintBackground);

    final blockWidth = camera.posicionesMax * slotSize +
        math.max(0, camera.posicionesMax - 1) * slotSpacing;
    final blockHeight = camera.filas * slotSize +
        math.max(0, camera.filas - 1) * slotSpacing;

    final top = verticalMargin + topLabelHeight;

    final slotPaint = Paint()..color = const Color(0xFF8BC34A);
    final slotBorder = Paint()
      ..color = Colors.blueGrey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final emptyPaint = Paint()..color = Colors.grey.shade200;
    final walkwayPaint = Paint()..color = Colors.grey.shade300;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    final double fontScale = scale.clamp(0.75, 1.8);
    final pLabelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 12 * fontScale,
      color: Colors.blueGrey.shade700,
    );
    final fLabelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 11 * fontScale,
      color: Colors.blueGrey.shade600,
    );
    final palletStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12 * fontScale,
      color: Colors.white,
    );
    final metaStyle = TextStyle(
      fontSize: 10 * fontScale,
      color: Colors.white,
    );

    void drawColumnLabels({required double startX, required StorageSide side}) {
      for (var index = 0; index < camera.posicionesMax; index++) {
        final position = index + 1;
        final x = side == StorageSide.right
            ? startX + index * (slotSize + slotSpacing)
            : startX + (camera.posicionesMax - index - 1) * (slotSize + slotSpacing);
        final rect = Rect.fromLTWH(x, verticalMargin, slotSize, topLabelHeight - 8);
        textPainter.text = TextSpan(text: 'P$position', style: pLabelStyle);
        textPainter.layout(minWidth: 0, maxWidth: rect.width);
        final offset = Offset(
          rect.left + (rect.width - textPainter.width) / 2,
          rect.top + (rect.height - textPainter.height) / 2,
        );
        textPainter.paint(canvas, offset);
      }
    }

    void drawRowLabels({
      required double startX,
    }) {
      for (var row = 0; row < camera.filas; row++) {
        final filaNumero = row + 1;
        final label = 'F$filaNumero';
        final y = top + row * (slotSize + slotSpacing) + slotSize / 2;
        textPainter.text = TextSpan(text: label, style: fLabelStyle);
        textPainter.layout();
        final dx = startX + (rowLabelWidth - textPainter.width) / 2;
        final dy = y - textPainter.height / 2;
        textPainter.paint(canvas, Offset(dx, dy));
      }
    }

    void drawBlock({
      required Offset origin,
      required StorageSide side,
      required Rect rowLabelArea,
    }) {
      drawColumnLabels(startX: origin.dx, side: side);
      drawRowLabels(startX: rowLabelArea.left);

      for (var row = 0; row < camera.filas; row++) {
        final filaNumero = row + 1;
        final y = top + row * (slotSize + slotSpacing);

        for (var col = 0; col < camera.posicionesMax; col++) {
          final posicion = col + 1;
          final slotX = side == StorageSide.right
              ? origin.dx + col * (slotSize + slotSpacing)
              : origin.dx + (camera.posicionesMax - col - 1) * (slotSize + slotSpacing);
          final rect = Rect.fromLTWH(slotX, y, slotSize, slotSize);
          final key = StorageSlotCoordinate(side: side, fila: filaNumero, posicion: posicion);
          final entry = occupied[key];
          canvas.drawRect(rect, entry != null ? slotPaint : emptyPaint);
          canvas.drawRect(rect, slotBorder);

          if (entry != null) {
            hits.add(_SlotHit(rect: rect, entry: entry));
            textPainter.text = TextSpan(text: entry.palletCode, style: palletStyle);
            textPainter.layout(minWidth: 0, maxWidth: rect.width - 4);
            final textOffset = Offset(
              rect.left + (rect.width - textPainter.width) / 2,
              rect.top + 4,
            );
            textPainter.paint(canvas, textOffset);

            final metaLabel = 'F${entry.fila}·P${entry.posicion}';
            textPainter.text = TextSpan(text: metaLabel, style: metaStyle);
            textPainter.layout(minWidth: 0, maxWidth: rect.width - 4);
            final metaOffset = Offset(
              rect.left + (rect.width - textPainter.width) / 2,
              rect.bottom - textPainter.height - 4,
            );
            textPainter.paint(canvas, metaOffset);
          }
        }
      }
    }

    if (camera.pasillo == CameraPasillo.central) {
      final leftBlockOrigin = Offset(horizontalMargin, verticalMargin);
      final leftRowLabelArea = Rect.fromLTWH(
        horizontalMargin + blockWidth,
        top,
        rowLabelWidth,
        blockHeight,
      );
      final walkwayLeft = leftRowLabelArea.right;
      final walkwayRect = Rect.fromLTWH(walkwayLeft, verticalMargin, walkwayWidth, topLabelHeight + blockHeight);
      canvas.drawRect(walkwayRect, walkwayPaint);

      final rightRowLabelArea = Rect.fromLTWH(
        walkwayRect.right,
        top,
        rowLabelWidth,
        blockHeight,
      );
      final rightBlockOrigin = Offset(rightRowLabelArea.right, verticalMargin);

      drawBlock(origin: leftBlockOrigin, side: StorageSide.left, rowLabelArea: leftRowLabelArea);
      drawBlock(origin: rightBlockOrigin, side: StorageSide.right, rowLabelArea: rightRowLabelArea);
    } else {
      final walkwayRect = Rect.fromLTWH(horizontalMargin, verticalMargin, walkwayWidth,
          topLabelHeight + blockHeight);
      canvas.drawRect(walkwayRect, walkwayPaint);

      final rowLabelArea = Rect.fromLTWH(
        walkwayRect.right,
        top,
        rowLabelWidth,
        blockHeight,
      );
      final blockOrigin = Offset(rowLabelArea.right, verticalMargin);

      drawBlock(origin: blockOrigin, side: StorageSide.right, rowLabelArea: rowLabelArea);
    }

    _drawLegend(canvas, size, textPainter, fontScale);
    onLayout?.call(List<_SlotHit>.unmodifiable(hits));
  }

  void _drawLegend(Canvas canvas, Size size, TextPainter textPainter, double fontScale) {
    final legendSize = const Size(160, 56);
    final legendRect = Rect.fromLTWH(
      size.width - horizontalMargin - legendSize.width,
      verticalMargin / 2,
      legendSize.width,
      legendSize.height,
    );
    final paint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(legendRect, const Radius.circular(12)),
      paint,
    );
    final border = Paint()
      ..color = Colors.blueGrey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(legendRect, const Radius.circular(12)),
      border,
    );

    final boxSize = 16.0;
    final freePaint = Paint()..color = Colors.grey.shade300;
    final occupiedPaint = Paint()..color = const Color(0xFF8BC34A);

    final textStyle = TextStyle(
      fontSize: 12 * fontScale,
      color: Colors.blueGrey.shade700,
    );

    final freeRect = Rect.fromLTWH(legendRect.left + 16, legendRect.top + 12, boxSize, boxSize);
    canvas.drawRect(freeRect, freePaint);
    canvas.drawRect(freeRect, border);
    textPainter.text = TextSpan(text: 'Libre', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(freeRect.right + 8, freeRect.top + (boxSize - textPainter.height) / 2),
    );

    final occupiedRect = Rect.fromLTWH(
      legendRect.left + 16,
      freeRect.bottom + 12,
      boxSize,
      boxSize,
    );
    canvas.drawRect(occupiedRect, occupiedPaint);
    canvas.drawRect(occupiedRect, border);
    textPainter.text = TextSpan(text: 'Ocupado', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(occupiedRect.right + 8, occupiedRect.top + (boxSize - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant StorageMapPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.occupied != occupied ||
        oldDelegate.scale != scale;
  }
}

class _SlotHit {
  const _SlotHit({required this.rect, required this.entry});

  final Rect rect;
  final StockEntry entry;
}
