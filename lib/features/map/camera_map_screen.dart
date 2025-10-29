import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/camera_model.dart';
import '../../providers/camera_providers.dart';
import 'widgets/pallet_tile.dart';

int labelForPosition({
  required bool isLeftSide,
  required int colIndex,
  required int posMax,
  required bool aisleIsCentral,
}) {
  if (aisleIsCentral) {
    return isLeftSide ? (colIndex + 1) : (posMax - colIndex);
  } else {
    return posMax - colIndex;
  }
}

int positionIndexForLookup({
  required bool isLeftSide,
  required int colIndex,
  required int posMax,
  required bool aisleIsCentral,
}) {
  return labelForPosition(
    isLeftSide: isLeftSide,
    colIndex: colIndex,
    posMax: posMax,
    aisleIsCentral: aisleIsCentral,
  );
}

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
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();
  final _ivController = TransformationController();

  Size? _lastViewportSize;
  Size? _lastCanvasSize;
  bool _matrixSet = false;

  static const double cell = 44;
  static const double gap = 8;
  static const double aisleWidth = 24;

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    _ivController.dispose();
    super.dispose();
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return stockAsync.when(
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
                          final colsPorLado = camera.posicionesMax;

                          final canvasSize = _CameraCanvas.computeSize(
                            pasillo: camera.pasillo,
                            filasPorLado: filasPorLado,
                            colsPorLado: colsPorLado,
                            cell: cell,
                            gap: gap,
                            aisleWidth: aisleWidth,
                          );

                          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                          if (_lastViewportSize == null ||
                              _lastViewportSize!.width != viewport.width ||
                              _lastViewportSize!.height != viewport.height) {
                            _matrixSet = false;
                            _lastViewportSize = viewport;
                          }

                          if (_lastCanvasSize == null ||
                              _lastCanvasSize!.width != canvasSize.width ||
                              _lastCanvasSize!.height != canvasSize.height) {
                            _matrixSet = false;
                            _lastCanvasSize = canvasSize;
                          }

                          if (!_matrixSet &&
                              viewport.width > 0 &&
                              viewport.height > 0 &&
                              canvasSize.width > 0 &&
                              canvasSize.height > 0) {
                            final initScale = math.min(
                                  viewport.width / canvasSize.width,
                                  viewport.height / canvasSize.height,
                                ) *
                                0.95;
                            _ivController.value =
                                Matrix4.diagonal3Values(initScale, initScale, 1);
                            _matrixSet = true;
                          }

                          final canvas = _CameraCanvas(
                            camera: camera,
                            occupied: occupied,
                            cell: cell,
                            gap: gap,
                            aisleWidth: aisleWidth,
                            onEntryTap: (entry) => _showSlotDetails(context, entry),
                          );

                          return Stack(
                            children: [
                              Scrollbar(
                                controller: _vCtrl,
                                thumbVisibility: true,
                                child: Scrollbar(
                                  controller: _hCtrl,
                                  thumbVisibility: true,
                                  notificationPredicate: (notif) =>
                                      notif.metrics.axis == Axis.horizontal,
                                  child: SingleChildScrollView(
                                    controller: _vCtrl,
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      controller: _hCtrl,
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: canvasSize.width,
                                        height: canvasSize.height,
                                        child: InteractiveViewer(
                                          constrained: false,
                                          panEnabled: false,
                                          scaleEnabled: true,
                                          minScale: 0.2,
                                          maxScale: 6.0,
                                          boundaryMargin: const EdgeInsets.all(200),
                                          transformationController: _ivController,
                                          child: canvas,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                top: 0,
                                child: SafeArea(
                                  minimum: const EdgeInsets.only(left: 16, top: 8),
                                  child: const _LegendCard(),
                                ),
                              ),
                            ],
                          );
                        },
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
    Widget dot(Color color) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black12),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(const Color(0xFFF2F3F5)),
                const SizedBox(width: 8),
                const Text('Libre'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(const Color(0xFF8BC34A)),
                const SizedBox(width: 8),
                const Text('Ocupado'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraCanvas extends StatelessWidget {
  const _CameraCanvas({
    required this.camera,
    required this.occupied,
    required this.cell,
    required this.gap,
    required this.aisleWidth,
    required this.onEntryTap,
  });

  final CameraModel camera;
  final Map<StorageSlotCoordinate, StockEntry> occupied;
  final double cell;
  final double gap;
  final double aisleWidth;
  final ValueChanged<StockEntry>? onEntryTap;

  static const double rowLabelWidth = 36;
  static const double headerHeight = 20;
  static const double outerPadding = 16;
  static const Color walkwayColor = Color(0xFFD3D6DA);

  static Size computeSize({
    required CameraPasillo pasillo,
    required int filasPorLado,
    required int colsPorLado,
    required double cell,
    required double gap,
    required double aisleWidth,
  }) {
    final blockWidth = colsPorLado * cell + math.max(0, colsPorLado - 1) * gap;
    final blockHeight = filasPorLado * cell + math.max(0, filasPorLado - 1) * gap;
    final vertical = outerPadding * 2 + headerHeight + (filasPorLado > 0 ? gap : 0) + blockHeight;

    final horizontal = pasillo == CameraPasillo.central
        ? outerPadding * 2 +
            rowLabelWidth +
            blockWidth +
            gap +
            aisleWidth +
            gap +
            rowLabelWidth +
            blockWidth
        : outerPadding * 2 +
            aisleWidth +
            gap +
            rowLabelWidth +
            blockWidth;

    return Size(horizontal, vertical);
  }

  bool get _isCentral => camera.pasillo == CameraPasillo.central;

  int get _filasPorLado => camera.filas;

  int get _filasTotales => _isCentral ? _filasPorLado * 2 : _filasPorLado;

  int get _posicionesMax => camera.posicionesMax;

  StockEntry? _entryFor(StorageSide side, int fila, int posicion) {
    final key = StorageSlotCoordinate(side: side, fila: fila, posicion: posicion);
    final found = occupied[key];
    if (found != null) {
      return found;
    }
    for (final entry in occupied.entries) {
      if (entry.key.fila == fila && entry.key.posicion == posicion) {
        return entry.value;
      }
    }
    return null;
  }

  String? _digitsForEntry(StockEntry entry) {
    final digits = RegExp(r'\d+').allMatches(entry.palletCode).map((m) => m.group(0)!).join();
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length <= 10) {
      return digits;
    }
    return digits.substring(digits.length - 10);
  }

  Widget _buildHeaderRow(TextStyle style) {
    final children = <Widget>[];

    Widget header({required bool isLeftSide}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int colIndex = 0; colIndex < _posicionesMax; colIndex++)
            Padding(
              padding: EdgeInsets.only(
                right: colIndex == _posicionesMax - 1 ? 0 : gap,
              ),
              child: SizedBox(
                width: cell,
                child: Text(
                  'P${labelForPosition(
                        isLeftSide: isLeftSide,
                        colIndex: colIndex,
                        posMax: _posicionesMax,
                        aisleIsCentral: _isCentral,
                      )}',
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
            ),
        ],
      );
    }

    if (_isCentral) {
      children
        ..add(const SizedBox(width: rowLabelWidth))
        ..add(header(isLeftSide: true))
        ..add(SizedBox(width: gap))
        ..add(SizedBox(width: aisleWidth))
        ..add(SizedBox(width: gap))
        ..add(const SizedBox(width: rowLabelWidth))
        ..add(header(isLeftSide: false));
    } else {
      children
        ..add(SizedBox(width: aisleWidth))
        ..add(SizedBox(width: gap))
        ..add(const SizedBox(width: rowLabelWidth))
        ..add(header(isLeftSide: false));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }

  Widget _buildRowLabel(String text, {Alignment alignment = Alignment.centerRight}) {
    return SizedBox(
      width: rowLabelWidth,
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPalletRow({
    required StorageSide side,
    required int fila,
    required bool isLeftSide,
  }) {
    final tiles = <Widget>[];
    for (var colIndex = 0; colIndex < _posicionesMax; colIndex++) {
      final logicalPos = positionIndexForLookup(
        isLeftSide: isLeftSide,
        colIndex: colIndex,
        posMax: _posicionesMax,
        aisleIsCentral: _isCentral,
      );
      final entry = _entryFor(side, fila, logicalPos);
      final digits = entry != null ? _digitsForEntry(entry) : null;
      Widget tile = SizedBox(
        width: cell,
        height: cell,
        child: PalletTile(
          ocupado: entry != null,
          p: digits,
        ),
      );
      if (entry != null && onEntryTap != null) {
        tile = GestureDetector(
          onTap: () => onEntryTap!(entry),
          child: tile,
        );
      }
      tiles.add(tile);
      if (colIndex != _posicionesMax - 1) {
        tiles.add(SizedBox(width: gap));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: tiles);
  }

  Widget _buildWalkway(double height) {
    return Container(
      width: aisleWidth,
      height: height,
      decoration: BoxDecoration(
        color: walkwayColor,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_posicionesMax <= 0 || _filasPorLado <= 0) {
      return const SizedBox.shrink();
    }

    final headerStyle = const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600);

    final rows = <Widget>[];
    if (_isCentral) {
      for (var index = 0; index < _filasPorLado; index++) {
        final leftFila = index + 1;
        final rightFila = _filasPorLado + index + 1;
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: index == _filasPorLado - 1 ? 0 : gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildRowLabel('F$leftFila'),
                _buildPalletRow(
                  side: StorageSide.left,
                  fila: leftFila,
                  isLeftSide: true,
                ),
                SizedBox(width: gap),
                _buildWalkway(cell),
                SizedBox(width: gap),
                _buildRowLabel('F$rightFila', alignment: Alignment.centerLeft),
                _buildPalletRow(
                  side: StorageSide.right,
                  fila: rightFila,
                  isLeftSide: false,
                ),
              ],
            ),
          ),
        );
      }
    } else {
      for (var index = 0; index < _filasTotales; index++) {
        final fila = index + 1;
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: index == _filasTotales - 1 ? 0 : gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildWalkway(cell),
                SizedBox(width: gap),
                _buildRowLabel('F$fila'),
                _buildPalletRow(
                  side: StorageSide.right,
                  fila: fila,
                  isLeftSide: false,
                ),
              ],
            ),
          ),
        );
      }
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(outerPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: headerHeight, child: _buildHeaderRow(headerStyle)),
            SizedBox(height: gap),
            ...rows,
          ],
        ),
      ),
    );
  }
}
