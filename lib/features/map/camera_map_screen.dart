import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sansebas_stock/features/ops/ops_providers.dart';
import 'package:sansebas_stock/services/stock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class PalletDragData {
  final StockEntry entry;
  final StorageSlotCoordinate coord;

  PalletDragData({
    required this.entry,
    required this.coord,
  });
}

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

class _CameraMapScreenState extends ConsumerState<CameraMapScreen>
    with SingleTickerProviderStateMixin {
  static const double _minZoom = 0.5;
  static const double _maxZoom = 6.0;

  static final Map<String, Matrix4> _matrixCache = {};

  final TransformationController _ivController = TransformationController();
  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  Animation<Matrix4>? _matrixAnimation;
  final GlobalKey<_DraggableLegendState> _legendKey =
      GlobalKey<_DraggableLegendState>();

  String? _activeCameraKey;
  Size? _viewportSize;
  Size? _canvasSize;
  Matrix4? _fitMatrix;
  bool _matrixInitialized = false;
  TapDownDetails? _doubleTapDetails;

  static const double cell = 44;
  static const double gap = 8;
  static const double aisleWidth = 24;

  @override
  void initState() {
    super.initState();
    _animCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _legendKey.currentState?.setFaded(false);
        _storeMatrix();
      }
    });
  }

  @override
  void dispose() {
    _storeMatrix();
    _matrixAnimation?.removeListener(_handleAnimationTick);
    _animCtrl.dispose();
    _ivController.dispose();
    super.dispose();
  }

  void _storeMatrix() {
    final cameraKey = _activeCameraKey;
    if (cameraKey == null) {
      return;
    }
    _matrixCache[cameraKey] = Matrix4.copy(_ivController.value);
  }

  void _handleAnimationTick() {
    final animation = _matrixAnimation;
    if (animation != null) {
      _ivController.value = animation.value;
    }
  }

  void _animateTo(Matrix4 target) {
    _matrixAnimation?.removeListener(_handleAnimationTick);
    _matrixAnimation = Matrix4Tween(
      begin: _ivController.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _matrixAnimation!.addListener(_handleAnimationTick);
    _legendKey.currentState?.setFaded(true);
    _animCtrl
      ..stop()
      ..reset()
      ..forward();
  }

  void _zoomBy(double factor, Size viewport) {
    if (viewport.isEmpty) {
      return;
    }
    final current = _ivController.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minZoom, _maxZoom);
    _zoomToPoint(
      Offset(viewport.width / 2, viewport.height / 2),
      viewport,
      target,
    );
  }

  void _zoomToPoint(Offset focalPoint, Size viewport, double targetScale) {
    if (viewport.isEmpty) {
      return;
    }
    final clampedScale = targetScale.clamp(_minZoom, _maxZoom);
    final scenePoint = _ivController.toScene(focalPoint);
    final matrix = Matrix4.identity()
      ..scale(clampedScale)
      ..translate(
        -scenePoint.dx + viewport.width / clampedScale / 2,
        -scenePoint.dy + viewport.height / clampedScale / 2,
      );
    _animateTo(matrix);
  }

  Matrix4 _buildFitMatrix(Size viewport, Size content) {
    if (viewport.isEmpty || content.width <= 0 || content.height <= 0) {
      return Matrix4.identity();
    }
    final fitScale = math.min(
      viewport.width / content.width,
      viewport.height / content.height,
    );
    final baseScale = fitScale.isFinite ? fitScale * 0.95 : 1.0;
    final scale = baseScale.clamp(_minZoom, _maxZoom);
    final matrix = Matrix4.identity()
      ..scale(scale)
      ..translate(
        (viewport.width / scale - content.width) / 2,
        (viewport.height / scale - content.height) / 2,
      );
    return matrix;
  }

  void _fitToScreen() {
    final matrix = _fitMatrix;
    if (matrix != null) {
      _animateTo(Matrix4.copy(matrix));
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap(Size viewport) {
    final details = _doubleTapDetails;
    if (details == null || viewport.isEmpty) {
      return;
    }
    final currentScale = _ivController.value.getMaxScaleOnAxis();
    if (currentScale < 2.0) {
      final targetScale = (currentScale * 2).clamp(_minZoom, _maxZoom);
      _zoomToPoint(details.localPosition, viewport, targetScale);
    } else {
      _fitToScreen();
    }
    _doubleTapDetails = null;
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    if (_animCtrl.isAnimating) {
      _animCtrl.stop();
      _matrixAnimation?.removeListener(_handleAnimationTick);
      _matrixAnimation = null;
      _storeMatrix();
    }
    _legendKey.currentState?.setFaded(true);
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    _legendKey.currentState?.setFaded(false);
    _storeMatrix();
  }

  Future<String?> _resolveUsuario() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return null;

    final userDoc = await FirebaseFirestore.instance
        .collection('UsuariosAutorizados')
        .doc(uid)
        .get();

    final userName = userDoc.data()?['Nombre']?.toString();
    if (userName != null && userName.isNotEmpty) {
      return userName;
    }

    final displayName = user?.displayName;
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      return email;
    }

    return uid;
  }

  Future<void> _handleDrop(
    BuildContext context,
    WidgetRef ref, {
    required CameraModel camera,
    required int nivel,
    required PalletDragData from,
    required StorageSlotCoordinate to,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final usuario = await _resolveUsuario();
    if (usuario == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo identificar al usuario actual.')),
      );
      return;
    }

    final StockService stockService = ref.read(stockServiceProvider);
    final provider = stockByCameraLevelProvider(
      CameraLevelKey(numero: camera.displayNumero, nivel: nivel, pasillo: camera.pasillo),
    );

    final entry = from.entry;
    final nivelValue = entry.data['NIVEL'];
    final estanteriaValue = entry.data['ESTANTERIA'];

    final stockDocId = entry.id;
    final idPalet = entry.id.length > 1 ? entry.id.substring(1) : entry.id;
    final fromCamara = (entry.data['CAMARA'] ?? camera.displayNumero).toString();
    final fromEstanteria = estanteriaValue?.toString() ?? from.coord.fila.toString();
    final fromPosicion = entry.posicion;
    final fromNivel = nivelValue is int
        ? nivelValue
        : int.tryParse(nivelValue?.toString() ?? '') ?? nivel;

    final toCamara = fromCamara;
    final toEstanteria = _estanteriaFromCoordinate(to);
    final toPosicion = _posicionFromCoordinate(to);
    final toNivel = nivel;

    try {
      await stockService.movePalet(
        stockDocId: stockDocId,
        idPalet: idPalet,
        fromCamara: fromCamara,
        fromEstanteria: fromEstanteria,
        fromPosicion: fromPosicion,
        fromNivel: fromNivel,
        toCamara: toCamara,
        toEstanteria: toEstanteria,
        toPosicion: toPosicion,
        toNivel: toNivel,
        usuario: usuario,
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text('Palet movido a F$toEstanteria · P$toPosicion · Nivel $toNivel'),
        ),
      );

      ref.invalidate(provider);
    } catch (e) {
      ref.invalidate(provider);
      final message = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  String _estanteriaFromCoordinate(StorageSlotCoordinate coordinate) {
    return coordinate.fila.toString();
  }

  int _posicionFromCoordinate(StorageSlotCoordinate coordinate) {
    return coordinate.posicion;
  }

  Future<void> cambiarEstadoPalet({
    required DocumentSnapshot doc,
    required bool marcarLibre,
  }) async {
    if (!doc.exists) return;

    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final currentValue = (data['HUECO'] ?? '').toString();
    final targetValue = marcarLibre ? 'Libre' : 'Ocupado';
    final currentNormalized = currentValue.toLowerCase();
    final targetNormalized = targetValue.toLowerCase();

    if (currentNormalized == targetNormalized) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('UsuariosAutorizados')
        .doc(uid)
        .get();

    final userName = userDoc.data()?['Nombre'];
    final userEmail = user?.email;

    final batch = FirebaseFirestore.instance.batch();

    batch.update(doc.reference, {'HUECO': targetValue});

    batch.set(
      FirebaseFirestore.instance.collection('StockLogs').doc(),
      {
        'palletId': doc.id,
        'campo': 'HUECO',
        'from': currentNormalized == 'ocupado'
            ? 'Ocupado'
            : (currentNormalized == 'libre' ? 'Libre' : currentValue),
        'to': targetValue,
        'userId': uid,
        'userEmail': userEmail,
        'userName': userName,
        'timestamp': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
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
                      builder: (context) {
                        final currentHueco = (data['HUECO'] ?? '').toString();
                        final isOcupado = currentHueco.toLowerCase() == 'ocupado';
                        final nextState = isOcupado ? 'Libre' : 'Ocupado';
                        final docRef = FirebaseFirestore.instance
                            .collection('Stock')
                            .doc(entry.id);

                        Future<void> handleUpdate() async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Confirmar'),
                              content: Text('¿Deseas marcar este palet como $nextState?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                  child: const Text('Confirmar'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;

                          final snapshot = await docRef.get();
                          await cambiarEstadoPalet(
                            doc: snapshot,
                            marcarLibre: isOcupado,
                          );

                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }

                        return AlertDialog(
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
                            ElevatedButton.icon(
                              onPressed: handleUpdate,
                              icon: Icon(
                                  isOcupado ? Icons.inventory_2_outlined : Icons.check_circle_outline),
                              label: Text('Marcar como $nextState'),
                            ),
                          ],
                        );
                      },
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
                          if (_activeCameraKey != cameraNumero) {
                            _activeCameraKey = cameraNumero;
                            _matrixInitialized = false;
                          }

                          if (_viewportSize != viewport ||
                              _canvasSize != canvasSize) {
                            _viewportSize = viewport;
                            _canvasSize = canvasSize;
                            _fitMatrix = _buildFitMatrix(viewport, canvasSize);
                            _matrixInitialized = false;
                          }

                          if (!_matrixInitialized && _fitMatrix != null) {
                            final cached = _matrixCache[_activeCameraKey!];
                            if (cached != null) {
                              _ivController.value = Matrix4.copy(cached);
                            } else {
                              _ivController.value = Matrix4.copy(_fitMatrix!);
                            }
                            _matrixInitialized = true;
                          }

                          final canvas = _CameraCanvas(
                            ref: ref,
                            camera: camera,
                            occupied: occupied,
                            nivel: nivelActual,
                            cell: cell,
                            gap: gap,
                            aisleWidth: aisleWidth,
                            onEntryTap: (entry) => _showSlotDetails(context, entry),
                            onDrop: (context, ref, {required from, required to}) =>
                                _handleDrop(
                              context,
                              ref,
                              camera: camera,
                              nivel: nivelActual,
                              from: from,
                              to: to,
                            ),
                          );

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  onDoubleTapDown: _handleDoubleTapDown,
                                  onDoubleTap: () => _handleDoubleTap(viewport),
                                  child: InteractiveViewer(
                                    constrained: false,
                                    panEnabled: true,
                                    scaleEnabled: true,
                                    minScale: _minZoom,
                                    maxScale: _maxZoom,
                                    boundaryMargin: const EdgeInsets.all(200),
                                    clipBehavior: Clip.none,
                                    transformationController: _ivController,
                                    onInteractionStart: _handleInteractionStart,
                                    onInteractionEnd: _handleInteractionEnd,
                                    child: SizedBox(
                                      width: canvasSize.width,
                                      height: canvasSize.height,
                                      child: canvas,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 20,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _ZoomButton(
                                      icon: Icons.add,
                                      onTap: () => _zoomBy(1.2, viewport),
                                    ),
                                    const SizedBox(height: 8),
                                    _ZoomButton(
                                      icon: Icons.remove,
                                      onTap: () => _zoomBy(1 / 1.2, viewport),
                                    ),
                                    const SizedBox(height: 8),
                                    _ZoomButton(
                                      icon: Icons.crop_square,
                                      onTap: _fitToScreen,
                                    ),
                                  ],
                                ),
                              ),
                              Positioned.fill(
                                child: DraggableLegend(key: _legendKey),
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

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class DraggableLegend extends StatefulWidget {
  const DraggableLegend({super.key});

  @override
  State<DraggableLegend> createState() => _DraggableLegendState();
}

class _DraggableLegendState extends State<DraggableLegend> {
  Offset pos = const Offset(16, 120);
  bool visible = true;
  bool faded = false;

  static const Size _legendSize = Size(180, 120);

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('legend_dx') ?? pos.dx;
    final dy = prefs.getDouble('legend_dy') ?? pos.dy;
    if (!mounted) return;
    setState(() {
      pos = Offset(dx, dy);
    });
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('legend_dx', pos.dx);
    await prefs.setDouble('legend_dy', pos.dy);
  }

  void _toggleVisibility() {
    setState(() {
      visible = !visible;
      faded = false;
    });
  }

  void setFaded(bool value) {
    if (!visible || faded == value) {
      return;
    }
    setState(() {
      faded = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minX = 8.0;
        const minY = 8.0;
        final maxX = math.max(minX, constraints.maxWidth - _legendSize.width - 8);
        final maxY = math.max(minY, constraints.maxHeight - _legendSize.height - 8);
        final adjustedPos = Offset(
          pos.dx.clamp(minX, maxX),
          pos.dy.clamp(minY, maxY),
        );
        if (adjustedPos != pos) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              pos = adjustedPos;
            });
            _savePosition();
          });
        }

        void clampAndSet(Offset next) {
          setState(() {
            pos = Offset(
              next.dx.clamp(minX, maxX),
              next.dy.clamp(minY, maxY),
            );
          });
        }

        final legendCard = Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).cardColor,
          child: ConstrainedBox(
            constraints: BoxConstraints.tight(_legendSize),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(color: const Color(0xFFF2F3F5)),
                      const SizedBox(width: 8),
                      const Text('Libre'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(color: const Color(0xFF8BC34A)),
                      const SizedBox(width: 8),
                      const Text('Ocupado'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: _toggleVisibility,
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Stack(
          children: [
            if (visible)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                left: adjustedPos.dx,
                top: adjustedPos.dy,
                child: GestureDetector(
                  onPanUpdate: (details) => clampAndSet(pos + details.delta),
                  onPanEnd: (_) => _savePosition(),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: faded ? 0.6 : 1.0,
                    child: legendCard,
                  ),
                ),
              ),
            if (!visible)
              Positioned(
                left: 16,
                bottom: 32,
                child: ElevatedButton.icon(
                  onPressed: _toggleVisibility,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Mostrar leyenda'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
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
}

class _CameraCanvas extends StatelessWidget {
  const _CameraCanvas({
    required this.ref,
    required this.camera,
    required this.occupied,
    required this.nivel,
    required this.cell,
    required this.gap,
    required this.aisleWidth,
    required this.onEntryTap,
    required this.onDrop,
  });

  final WidgetRef ref;
  final CameraModel camera;
  final Map<StorageSlotCoordinate, StockEntry> occupied;
  final int nivel;
  final double cell;
  final double gap;
  final double aisleWidth;
  final ValueChanged<StockEntry>? onEntryTap;
  final Future<void> Function(
    BuildContext context,
    WidgetRef ref, {
    required PalletDragData from,
    required StorageSlotCoordinate to,
  }) onDrop;

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

  Widget _buildPalletCell(
    BuildContext context,
    WidgetRef ref,
    StorageSlotCoordinate coord,
    StockEntry? entry,
  ) {
    final ocupado = entry != null;
    final digits = entry != null ? _digitsForEntry(entry) : null;

    Widget baseTile = PalletTile(
      ocupado: ocupado,
      p: digits,
    );

    if (ocupado && onEntryTap != null) {
      baseTile = GestureDetector(
        onTap: () => onEntryTap!(entry!),
        child: baseTile,
      );
    }

    return DragTarget<PalletDragData>(
      builder: (context, candidate, rejected) {
        final content = ocupado
            ? LongPressDraggable<PalletDragData>(
                data: PalletDragData(entry: entry!, coord: coord),
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: cell,
                    height: cell,
                    child: baseTile,
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: baseTile,
                ),
                child: baseTile,
              )
            : baseTile;

        final isActive = candidate.isNotEmpty && !ocupado;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: cell,
          height: cell,
          decoration: isActive
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blueAccent, width: 3),
                )
              : null,
          child: content,
        );
      },
      onWillAccept: (data) {
        if (data == null) return false;
        if (data.coord == coord) return false;
        return !ocupado;
      },
      onAccept: (data) async {
        await onDrop(context, ref, from: data, to: coord);
      },
    );
  }

  Widget _buildPalletRow({
    required BuildContext context,
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
      final coordinate = StorageSlotCoordinate(
        side: side,
        fila: fila,
        posicion: logicalPos,
      );

      tiles.add(_buildPalletCell(context, ref, coordinate, entry));
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
                  context: context,
                  side: StorageSide.left,
                  fila: leftFila,
                  isLeftSide: true,
                ),
                SizedBox(width: gap),
                _buildWalkway(cell),
                SizedBox(width: gap),
                _buildRowLabel('F$rightFila', alignment: Alignment.centerLeft),
                _buildPalletRow(
                  context: context,
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
                  context: context,
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
