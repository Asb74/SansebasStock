import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/stock_service.dart';
import '../qr/qr_parser.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;
  DateTime? _lastDetection;

  static const bool _mantenerUbicacionTrasOcupar = true;
  static const Duration _detectionCooldown = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      if (_isUbicacionQr(trimmed)) {
        await _onScanUbicacion(trimmed);
      } else if (_isPaletQr(trimmed)) {
        await _onScanPalet(trimmed);
      } else {
        throw const FormatException('QR no reconocido.');
      }

      _lastDetection = DateTime.now();
    } on FormatException catch (e) {
      _showError(e.message);
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
    final ubicacion = parseUbicacionQr(raw);
    ref.read(ubicacionPendienteProvider.notifier).state = ubicacion;

    if (!mounted) {
      return;
    }

    _showMessage('Ubicación guardada: ${ubicacion.etiqueta}');
  }

  Future<void> _onScanPalet(String raw) async {
    final stockService = ref.read(stockServiceProvider);
    final ubicacionPendiente = ref.read(ubicacionPendienteProvider);

    await stockService.procesarLecturaPalet(
      rawPaletQr: raw,
      ubicacionPendiente: ubicacionPendiente,
    );

    if (!mounted) {
      return;
    }

    final result = stockService.lastResult;
    if (result == null) {
      _showMessage('Operación completada.');
      return;
    }

    switch (result.action) {
      case StockProcessAction.creadoOcupado:
        final ubicacion = result.ubicacion;
        final posicion = result.posicion;
        if (ubicacion != null && posicion != null) {
          _showMessage(
            'Palet creado y ocupado en ${ubicacion.etiqueta} (Posición $posicion)',
          );
        } else {
          _showMessage('Palet creado y ocupado.');
        }
        break;
      case StockProcessAction.liberado:
        _showMessage('Palet liberado');
        break;
      case StockProcessAction.reubicado:
        final ubicacion = result.ubicacion;
        final posicion = result.posicion;
        if (ubicacion != null && posicion != null) {
          _showMessage(
            'Palet reubicado en ${ubicacion.etiqueta} (Posición $posicion)',
          );
        } else {
          _showMessage('Palet reubicado.');
        }
        break;
    }

    if (!_mantenerUbicacionTrasOcupar &&
        (result.action == StockProcessAction.creadoOcupado ||
            result.action == StockProcessAction.reubicado)) {
      ref.read(ubicacionPendienteProvider.notifier).state = null;
    }
  }

  bool _isUbicacionQr(String value) {
    final upper = value.toUpperCase();
    return upper.contains('CAMARA=') &&
        upper.contains('ESTANTERIA=') &&
        upper.contains('NIVEL=');
  }

  bool _isPaletQr(String value) {
    return value.toUpperCase().startsWith('P=');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lectura QR'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Escanea primero la ubicación y después el palet.',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
