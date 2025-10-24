import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sansebas_stock/features/ops/ops_providers.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart' as qr;
import 'package:sansebas_stock/services/stock_service.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _busy = false;
  bool _analyzingFromGallery = false;
  DateTime? _lastDetection;

  static const Duration _detectionCooldown = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanFromGallery() async {
    if (_busy || _analyzingFromGallery) {
      return;
    }

    try {
      final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _analyzingFromGallery = true;
      });

      await _controller.analyzeImage(file.path);
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
      await _controller.stop();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    context.go('/');
  }

  Future<void> _handle(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
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

    StockLocation? ubicacion;
    if (ubicacionPendiente != null) {
      ubicacion = StockLocation(
        camara: ubicacionPendiente.camara,
        estanteria: ubicacionPendiente.estanteria,
        nivel: ubicacionPendiente.nivel,
      );
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

  Widget _buildTorchButton() {
    return ValueListenableBuilder<TorchState>(
      valueListenable: _controller.torchState,
      builder: (context, state, _) {
        final bool isOn = state == TorchState.on;
        return _ScannerControlButton(
          icon: isOn ? Icons.flash_on : Icons.flash_off,
          label: 'Linterna',
          onTap: _busy ? null : () => _controller.toggleTorch(),
          active: isOn,
        );
      },
    );
  }

  Future<void> _handleSuccess(StockProcessResult result) async {
    ref.read(ubicacionPendienteProvider.notifier).state = null;
    try {
      await _controller.stop();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go('/');
      }
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
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
                      onPressed: () => _closeScanner(),
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
                              : () => _scanFromGallery(),
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
