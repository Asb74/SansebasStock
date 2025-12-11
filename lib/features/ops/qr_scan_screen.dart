import 'dart:io' show Platform; // DESKTOP-GUARD
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sansebas_stock/features/ops/ops_providers.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart' as qr;
import 'package:sansebas_stock/models/camera_model.dart';
import 'package:sansebas_stock/models/palet.dart';
import 'package:sansebas_stock/providers/camera_providers.dart';
import 'package:sansebas_stock/providers/palets_providers.dart';
import 'package:sansebas_stock/providers/storage_config_providers.dart';
import 'package:sansebas_stock/services/palet_location_service.dart';
import 'package:sansebas_stock/services/stock_service.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key, this.returnScanResult = false});

  final bool returnScanResult;

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

final bool _isDesktop =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS; // DESKTOP-GUARD
final bool _isMobile =
    Platform.isAndroid || Platform.isIOS; // DESKTOP-GUARD

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  MobileScannerController? _controller;
  ImagePicker? _imagePicker;
  bool _busy = false;
  bool _analyzingFromGallery = false;
  TorchState _torchState = TorchState.off;
  DateTime? _lastDetection;
  final PaletLocationService _locationService = PaletLocationService();

  static const Duration _detectionCooldown = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _controller = MobileScannerController();
      _imagePicker = ImagePicker();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Navegación de salida *siempre* con Navigator.pop
  void _navigateBack() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _navigateBackWithResult(String? result) {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _scanFromGallery() async {
    if (_busy || _analyzingFromGallery) {
      return;
    }

    final picker = _imagePicker;
    final controller = _controller;
    if (picker == null || controller == null) {
      return;
    }

    try {
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _analyzingFromGallery = true;
      });

      await controller.analyzeImage(file.path);
    } on Exception {
      if (!mounted) {
        return;
      }
      _showError('No se pudo procesar la imagen seleccionada.');
    } finally {
      if (mounted) {
        setState(() {
          _analyzingFromGallery = false;
        });
      }
    }
  }

  Future<void> _closeScanner() async {
    try {
      await _controller?.stop();
    } catch (_) {}

    _navigateBack();
  }

  Future<void> _handle(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (widget.returnScanResult && _esQrPalet(trimmed)) {
      try {
        final parsed = qr.parseQr(trimmed);
        _navigateBackWithResult(parsed.p.toString().padLeft(10, '0'));
      } on FormatException catch (e) {
        _showError(e.message);
      }
      return;
    }

    setState(() {
      _busy = true;
      _analyzingFromGallery = false;
    });

    try {
      if (_esQrUbicacion(trimmed)) {
        await _onScanUbicacion(trimmed);
      } else if (_esQrPalet(trimmed)) {
        await _onScanPalet(trimmed);
      } else {
        _showError('QR no reconocido.');
        return;
      }

      _lastDetection = DateTime.now();
    } on FirebaseException {
      _showError('No se pudo completar la operación.');
    } on Exception catch (e) {
      if (e.toString().contains(ubicacionRequeridaMessage)) {
        _showError(ubicacionRequeridaMessage);
      } else {
        _showError('No se pudo completar la operación.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _onScanUbicacion(String raw) async {
    final Ubicacion? ubicacion = _parseUbicacion(raw);
    if (ubicacion == null) {
      _showError('Ubicación inválida');
      return;
    }

    ref.read(ubicacionPendienteProvider.notifier).state = ubicacion;
    _showSuccess('Ubicación lista: ${ubicacion.toString()}');
  }

  Future<void> _onScanPalet(String raw) async {
    qr.ParsedQr parsed;
    try {
      parsed = qr.parseQr(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    final stockService = ref.read(stockServiceProvider);
    final ubicacionPendiente = ref.read(ubicacionPendienteProvider);

    final paletId = '${parsed.linea}${parsed.p}';
    final paletsBase = ref.read(paletsBaseStreamProvider).value;
    final currentPalet = paletsBase?.firstWhereOrNull((p) => p.id == paletId);
    final requiresLocation = currentPalet == null || !currentPalet.estaOcupado;
    final descriptor = _buildPaletDescriptor(parsed, currentPalet);

    StockLocation? ubicacion;
    if (ubicacionPendiente != null) {
      ubicacion = StockLocation(
        camara: ubicacionPendiente.camara.padLeft(2, '0'),
        estanteria: ubicacionPendiente.estanteria.padLeft(2, '0'),
        nivel: ubicacionPendiente.nivel,
      );
    } else if (requiresLocation) {
      final autoLocation = await _tryFindAutoLocation(descriptor);
      if (autoLocation != null) {
        final confirmed = await _showAutoLocationDialog(
          autoLocation,
          descriptor,
          parsed,
        );
        if (confirmed == true) {
          ubicacion = _stockLocationFromAuto(autoLocation);
        }
      }
    }

    if (requiresLocation && ubicacion != null) {
      ubicacion = await _resolveSlotForLocation(ubicacion) ?? ubicacion;
    }

    try {
      final result = await stockService.procesarPalet(
        qr: parsed,
        ubicacion: ubicacion,
      );

      switch (result.action) {
        case StockProcessAction.creadoOcupado:
        case StockProcessAction.reubicado:
        case StockProcessAction.liberado:
          await _handleSuccess(result);
          break;
      }
    } on StockProcessException catch (e) {
      if (e.code == StockProcessException.requiresLocationCode) {
        _showError(ubicacionRequeridaMessage);
      } else {
        _showError(e.message);
      }
    }
  }

  PaletLocationDescriptor _buildPaletDescriptor(
    qr.ParsedQr parsed,
    Palet? existing,
  ) {
    String? preferExisting(String? existingValue, String? fallback) {
      if (existingValue != null && existingValue.trim().isNotEmpty) {
        return existingValue.trim();
      }
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
      return null;
    }

    String? rawField(String key) {
      final value = parsed.rawFields[key.toUpperCase()] ?? parsed.rawFields[key];
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    }

    return PaletLocationDescriptor(
      cultivo: preferExisting(existing?.cultivo, rawField('CULTIVO')),
      marca: preferExisting(existing?.marca, rawField('MARCA')),
      variedad: preferExisting(existing?.variedad, rawField('VARIEDAD')),
      calibre: preferExisting(existing?.calibre, rawField('CALIBRE')),
      categoria: rawField('CATEGORIA'),
    );
  }

  Future<AutoLocationResult?> _tryFindAutoLocation(
    PaletLocationDescriptor descriptor,
  ) async {
    final cameras = ref.read(camerasStreamProvider).value;
    final storageConfig = ref.read(storageConfigByCameraProvider).value;
    final stockByRow = ref.read(paletsByCameraAndRowProvider).value;

    if (cameras == null || storageConfig == null || stockByRow == null) {
      return null;
    }

    return _locationService.findAutoLocationForIncomingPalet(
      palet: descriptor,
      cameras: cameras,
      storageConfigByCamera: storageConfig,
      currentStockByCameraAndRow: stockByRow,
    );
  }

  StockLocation _stockLocationFromAuto(AutoLocationResult autoLocation) {
    return StockLocation(
      camara: autoLocation.camera.displayNumero,
      estanteria: autoLocation.fila.toString().padLeft(2, '0'),
      nivel: autoLocation.nivel,
      posicion: autoLocation.posicion,
    );
  }

  Future<StockLocation?> _resolveSlotForLocation(StockLocation base) async {
    if (base.posicion != null) {
      return base;
    }

    final cameras = ref.read(camerasStreamProvider).value;
    final stockByRow = ref.read(paletsByCameraAndRowProvider).value;
    if (cameras == null || stockByRow == null) {
      return base;
    }

    final camera = _findCamera(base.camara, cameras);
    if (camera == null) {
      return base;
    }

    final fila = _parseFila(base.estanteria);
    if (fila == null) {
      return base;
    }

    final slot = _locationService.findFirstAvailableSlot(
      camera: camera,
      fila: fila,
      currentStockByCameraAndRow: stockByRow,
    );

    if (slot == null) {
      return base;
    }

    return StockLocation(
      camara: camera.displayNumero,
      estanteria: fila.toString().padLeft(2, '0'),
      nivel: slot.nivel,
      posicion: slot.posicion,
    );
  }

  CameraModel? _findCamera(String camara, List<CameraModel> cameras) {
    final normalized = camara.trim();
    final padded = normalized.padLeft(2, '0');

    for (final camera in cameras) {
      final keys = {
        camera.id.trim(),
        camera.numero.trim(),
        camera.displayNumero,
      };
      if (keys.contains(normalized) || keys.contains(padded)) {
        return camera;
      }
    }
    return null;
  }

  int? _parseFila(String estanteria) {
    final digits = RegExp(r'\d+').firstMatch(estanteria.trim())?.group(0);
    if (digits == null) return null;
    return int.tryParse(digits);
  }

  Future<bool?> _showAutoLocationDialog(
    AutoLocationResult result,
    PaletLocationDescriptor descriptor,
    qr.ParsedQr parsed,
  ) {
    final titulo =
        'CÁMARA ${result.camera.displayNumero} – FILA ${result.fila.toString().padLeft(2, '0')}';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog.fullscreen(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    titulo,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nivel ${result.nivel} · Posición ${result.posicion}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  _AutoLocationInfo(
                    paletCode: parsed.p.toString().padLeft(10, '0'),
                    descriptor: descriptor,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Confirmar ubicación'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Elegir manualmente'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _esQrUbicacion(String raw) {
    final r = raw.toUpperCase();
    return r.contains('CAMARA=') && r.contains('ESTANTERIA=') && r.contains('NIVEL=');
  }

  Ubicacion? _parseUbicacion(String raw) {
    try {
      final parts = raw.split('|');
      String? camara;
      String? estanteria;
      int? nivel;
      for (final part in parts) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        final key = kv[0].trim().toUpperCase();
        final value = kv[1].trim();
        if (key == 'CAMARA') {
          camara = value;
        } else if (key == 'ESTANTERIA') {
          estanteria = value;
        } else if (key == 'NIVEL') {
          nivel = int.tryParse(value.trim());
        }
      }
      if (camara != null && estanteria != null && nivel != null) {
        return Ubicacion(camara: camara, estanteria: estanteria, nivel: nivel);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _esQrPalet(String raw) {
    return raw.toUpperCase().contains('P=');
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_busy) {
      return;
    }

    try {
      await controller.toggleTorch();
      if (!mounted) {
        return;
      }
      setState(() {
        _torchState =
            _torchState == TorchState.on ? TorchState.off : TorchState.on;
      });
    } on Exception {
      _showError('No se pudo alternar la linterna.');
    }
  }

  bool _esQrPalet(String raw) {
    return raw.toUpperCase().contains('P=');
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_busy) {
      return;
    }

    try {
      await controller.toggleTorch();
      if (!mounted) {
        return;
      }
      setState(() {
        _torchState =
            _torchState == TorchState.on ? TorchState.off : TorchState.on;
      });
    } on Exception {
      _showError('No se pudo alternar la linterna.');
    }
  }

  Widget _buildTorchButton() {
    final bool isOn = _torchState == TorchState.on;
    return _ScannerControlButton(
      icon: isOn ? Icons.flash_on : Icons.flash_off,
      label: 'Linterna',
      onTap: _busy ? null : _toggleTorch,
      active: isOn,
    );
  }

  Future<void> _handleSuccess(StockProcessResult result) async {
    ref.read(ubicacionPendienteProvider.notifier).state = null;

    try {
      await _controller?.stop();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(result.userMessage)),
      );

    // Cerramos el lector después de mostrar el mensaje
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateBack();
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFD32F2F),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      // DESKTOP-GUARD
      return _DesktopQrPlaceholder(
        onClose: _navigateBack,
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: controller,
            fit: BoxFit.cover,
            onDetect: (capture) async {
              if (_busy) {
                return;
              }

              final now = DateTime.now();
              if (_lastDetection != null &&
                  now.difference(_lastDetection!) < _detectionCooldown) {
                return;
              }

              final raw = capture.barcodes
                  .map((barcode) => barcode.rawValue)
                  .firstWhere(
                    (value) => value != null && value.trim().isNotEmpty,
                    orElse: () => null,
                  );

              if (raw == null) {
                return;
              }

              await _handle(raw);
            },
          ),
          const Positioned.fill(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(),
            ),
          ),
          SafeArea(
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _ScannerBackButton(
                      enabled: !_busy && !_analyzingFromGallery,
                      onPressed: _closeScanner,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32, left: 32, right: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const <Widget>[
                        Text(
                          'Busca un código QR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Escanea primero la ubicación y después el palet.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        _buildTorchButton(),
                        _ScannerControlButton(
                          icon: Icons.image_outlined,
                          label: 'Galería',
                          onTap: _busy || _analyzingFromGallery
                              ? null
                              : _scanFromGallery,
                          active: _analyzingFromGallery,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy || _analyzingFromGallery)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopQrPlaceholder extends StatelessWidget {
  const _DesktopQrPlaceholder({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lectura QR'),
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.desktop_windows, size: 72),
              SizedBox(height: 24),
              Text(
                'El escaneo de códigos QR está disponible solo en móvil.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Accede desde un dispositivo Android o iOS para usar la cámara.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoLocationInfo extends StatelessWidget {
  const _AutoLocationInfo({
    required this.paletCode,
    required this.descriptor,
  });

  final String paletCode;
  final PaletLocationDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <MapEntry<String, String?>>[
      MapEntry('Palet', paletCode),
      MapEntry('Cultivo', descriptor.cultivo),
      MapEntry('Variedad', descriptor.variedad),
      MapEntry('Marca', descriptor.marca),
      MapEntry('Calibre', descriptor.calibre),
      MapEntry('Categoría', descriptor.categoria),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.value?.isNotEmpty == true
                      ? entry.value!
                      : '—',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ScannerControlButton extends StatelessWidget {
  const _ScannerControlButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withOpacity(0.18)
                    : Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? Colors.white : Colors.white24,
                  width: 1.4,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Icon(
                icon,
                size: 28,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerBackButton extends StatelessWidget {
  const _ScannerBackButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.close, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double cutOut = math.min(size.width, size.height) * 0.68;
    final double left = (size.width - cutOut) / 2;
    final double top = (size.height - cutOut) / 2;
    final Rect cutOutRect = Rect.fromLTWH(left, top, cutOut, cutOut);
    final RRect cutOutRRect = RRect.fromRectXY(cutOutRect, 24, 24);

    final Path background = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path cutPath = Path()..addRRect(cutOutRRect);
    final Path overlay = Path.combine(PathOperation.difference, background, cutPath);

    final Paint overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlay, overlayPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double cornerLength = math.min(cutOut / 4.5, 48.0);
    final double right = cutOutRect.right;
    final double bottom = cutOutRect.bottom;
    final double leftEdge = cutOutRect.left;
    final double topEdge = cutOutRect.top;

    // Top-left corner
    canvas.drawLine(
      Offset(leftEdge, topEdge),
      Offset(leftEdge + cornerLength, topEdge),
      borderPaint,
    );
    canvas.drawLine(
      Offset(leftEdge, topEdge),
      Offset(leftEdge, topEdge + cornerLength),
      borderPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(right - cornerLength, topEdge),
      Offset(right, topEdge),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right, topEdge),
      Offset(right, topEdge + cornerLength),
      borderPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(leftEdge, bottom - cornerLength),
      Offset(leftEdge, bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(leftEdge, bottom),
      Offset(leftEdge + cornerLength, bottom),
      borderPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(right - cornerLength, bottom),
      Offset(right, bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right, bottom - cornerLength),
      Offset(right, bottom),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
