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
                      final filasPorLado = camera.filas;
                      final posMax = camera.posicionesMax;

                      const cell = CameraPainter.cell;
                      const gap = CameraPainter.gap;
                      const headerH = CameraPainter.headerH;
                      const rowLabelW = CameraPainter.rowLabelW;
                      const aisleW = CameraPainter.aisleW;
                      const outerPad = CameraPainter.outerPad;

                      final colsLado = posMax;
                      final gridWidth = (colsLado * cell) + ((colsLado - 1) * gap);
                      final anchoBloque = rowLabelW + gridWidth;
                      final altoCuadricula = (filasPorLado * cell) + ((filasPorLado - 1) * gap);
                      final altoTotal = headerH + altoCuadricula;

                      final double canvasWidth;
                      if (camera.pasillo == CameraPasillo.central) {
                        canvasWidth =
                            outerPad + anchoBloque + gap + aisleW + gap + anchoBloque + outerPad;
                      } else {
                        canvasWidth = outerPad + aisleW + gap + anchoBloque + outerPad;
                      }
                      final canvasHeight = outerPad + altoTotal + outerPad;

                      final canvasSize = Size(canvasWidth, canvasHeight);

                      return Stack(
                        children: [
                          InteractiveViewer(
                            transformationController: _controller,
                            minScale: 0.6,
                            maxScale: 3.0,
                            boundaryMargin: const EdgeInsets.all(200),
                            child: SizedBox(
                              width: canvasSize.width,
                              height: canvasSize.height,
                              child: ValueListenableBuilder<Matrix4>(
                                valueListenable: _controller,
                                builder: (context, matrix, _) {
                                  final painter = CameraPainter(
                                    camera: camera,
                                    occupied: occupied,
                                    scale: matrix.getMaxScaleOnAxis(),
                                    canvasSize: canvasSize,
                                    onLayout: (hits) => _hits = hits,
                                  );
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) =>
                                        _handleTap(context, details.localPosition),
                                    child: CustomPaint(
                                      size: canvasSize,
                                      painter: painter,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: _LegendCard(),
                          ),
                        ],
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

class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.blueGrey.shade200;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade700,
        );

    Widget buildRow({required Color color, required String label}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: borderColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: textStyle),
          ],
        ),
      );
    }

    return Card(
      color: Colors.white.withOpacity(0.92),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildRow(color: Colors.grey.shade300, label: 'Libre'),
            buildRow(color: const Color(0xFF8BC34A), label: 'Ocupado'),
          ],
        ),
      ),
    );
  }
}

class CameraPainter extends CustomPainter {
  CameraPainter({
    required this.camera,
    required this.occupied,
    required this.scale,
    required this.canvasSize,
    this.onLayout,
  });

  final CameraModel camera;
  final Map<StorageSlotCoordinate, StockEntry> occupied;
  final double scale;
  final Size canvasSize;
  final void Function(List<_SlotHit>)? onLayout;

  static const double cell = 46;
  static const double gap = 8;
  static const double headerH = 20;
  static const double rowLabelW = 22;
  static const double aisleW = 54;
  static const double outerPad = 24;

  int get _filasPorLado => camera.filas;
  int get _filasTotales =>
      camera.pasillo == CameraPasillo.central ? _filasPorLado * 2 : _filasPorLado;
  int get _posMax => camera.posicionesMax;

  double get _gridWidth => (_posMax * cell) + ((_posMax - 1) * gap);
  double get _altoCuadricula => (_filasPorLado * cell) + ((_filasPorLado - 1) * gap);
  double get _altoTotal => headerH + _altoCuadricula;

  double get _xStartLeftBlock => outerPad + rowLabelW;
  double get _xStartRightBlock {
    if (camera.pasillo == CameraPasillo.central) {
      return outerPad + (rowLabelW + _gridWidth) + gap + aisleW + gap;
    }
    return outerPad + aisleW + gap;
  }

  double get _walkwayLeft {
    if (camera.pasillo == CameraPasillo.central) {
      return outerPad + (rowLabelW + _gridWidth) + gap;
    }
    return outerPad;
  }

  bool _isRightBlockForFila(int fila) {
    if (camera.pasillo == CameraPasillo.central) {
      return fila > _filasPorLado;
    }
    return true;
  }

  Offset _topLeftForCell({
    required bool isRightBlock,
    required int fila,
    required int pos,
  }) {
    final int colIndex = pos - 1;

    final double x;
    if (isRightBlock) {
      x = _xStartRightBlock + (_posMax - pos) * (cell + gap);
    } else {
      x = _xStartLeftBlock + colIndex * (cell + gap);
    }

    final int filaIndexEnBloque;
    if (camera.pasillo == CameraPasillo.central && isRightBlock) {
      filaIndexEnBloque = (fila - _filasPorLado) - 1;
    } else {
      filaIndexEnBloque = fila - 1;
    }

    final double y = outerPad + headerH + filaIndexEnBloque * (cell + gap);
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hits = <_SlotHit>[];
    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final entriesByCoordinate = <String, StockEntry>{};
    for (final entry in occupied.values) {
      entriesByCoordinate['${entry.fila}-${entry.posicion}'] = entry;
    }

    final emptyPaint = Paint()..color = Colors.grey.shade200;
    final occupiedPaint = Paint()..color = const Color(0xFF8BC34A);
    final borderPaint = Paint()
      ..color = Colors.blueGrey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final walkwayPaint = Paint()..color = Colors.grey.shade300;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    final double labelScale = scale.clamp(0.75, 1.8);
    final columnLabelStyle = TextStyle(
      fontSize: 12 * labelScale,
      fontWeight: FontWeight.w600,
      color: Colors.blueGrey.shade700,
    );
    final rowLabelStyle = TextStyle(
      fontSize: 11 * labelScale,
      fontWeight: FontWeight.w600,
      color: Colors.blueGrey.shade600,
    );

    final double palletFontSize = math.min(cell * 0.35, 12) * scale.clamp(0.9, 1.4);
    final palletStyle = TextStyle(
      fontSize: palletFontSize,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );

    // Walkway
    final walkwayRect = Rect.fromLTWH(
      _walkwayLeft,
      outerPad,
      aisleW,
      _altoTotal,
    );
    canvas.drawRect(walkwayRect, walkwayPaint);

    void drawColumnHeaders({required bool isRightBlock}) {
      for (var pos = 1; pos <= _posMax; pos++) {
        final double x;
        if (isRightBlock) {
          x = _xStartRightBlock + (_posMax - pos) * (cell + gap);
        } else {
          x = _xStartLeftBlock + (pos - 1) * (cell + gap);
        }
        final rect = Rect.fromLTWH(x, outerPad, cell, headerH);
        textPainter.text = TextSpan(text: 'P$pos', style: columnLabelStyle);
        textPainter.layout(minWidth: 0, maxWidth: rect.width);
        final offset = Offset(
          rect.left + (rect.width - textPainter.width) / 2,
          rect.top + (rect.height - textPainter.height) / 2,
        );
        textPainter.paint(canvas, offset);
      }
    }

    if (camera.pasillo == CameraPasillo.central) {
      drawColumnHeaders(isRightBlock: false);
      drawColumnHeaders(isRightBlock: true);
    } else {
      drawColumnHeaders(isRightBlock: true);
    }

    for (var fila = 1; fila <= _filasTotales; fila++) {
      final bool isRightBlock = _isRightBlockForFila(fila);
      final offset = _topLeftForCell(isRightBlock: isRightBlock, fila: fila, pos: 1);
      final double centerY = offset.dy + cell / 2;

      textPainter.text = TextSpan(text: 'F$fila', style: rowLabelStyle);
      textPainter.layout();

      if (!isRightBlock) {
        final double dx = outerPad + (rowLabelW - textPainter.width) / 2;
        final double dy = centerY - textPainter.height / 2;
        textPainter.paint(canvas, Offset(dx, dy));
      }

      final double rightLabelStart = _xStartRightBlock + _gridWidth;
      if (isRightBlock) {
        final double dx = rightLabelStart + (rowLabelW - textPainter.width) / 2;
        final double dy = centerY - textPainter.height / 2;
        textPainter.paint(canvas, Offset(dx, dy));
      }

      for (var pos = 1; pos <= _posMax; pos++) {
        final topLeft = _topLeftForCell(isRightBlock: isRightBlock, fila: fila, pos: pos);
        final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, cell, cell);
        final key = '${fila}-$pos';
        final entry = entriesByCoordinate[key];
        canvas.drawRect(rect, entry != null ? occupiedPaint : emptyPaint);
        canvas.drawRect(rect, borderPaint);

        if (entry != null) {
          hits.add(_SlotHit(rect: rect, entry: entry));
          textPainter.text = TextSpan(text: entry.palletCode, style: palletStyle);
          textPainter.layout(minWidth: 0, maxWidth: rect.width - 4);
          final dx = rect.left + (rect.width - textPainter.width) / 2;
          final dy = rect.top + (rect.height - textPainter.height) / 2;
          textPainter.paint(canvas, Offset(dx, dy));
        }
      }
    }

    onLayout?.call(List<_SlotHit>.unmodifiable(hits));
  }

  @override
  bool shouldRepaint(covariant CameraPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.occupied != occupied ||
        oldDelegate.scale != scale ||
        oldDelegate.canvasSize != canvasSize;
  }
}

class _SlotHit {
  const _SlotHit({required this.rect, required this.entry});

  final Rect rect;
  final StockEntry entry;
}
