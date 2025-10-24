import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sansebas_stock/features/ops/ops_providers.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart';
import 'package:sansebas_stock/services/stock_service.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;
  DateTime? _lastDetection;

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
    ParsedQr parsed;
    try {
      parsed = parseQr(raw);
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

  Future<void> _handleSuccess(StockProcessResult result) async {
    ref.read(ubicacionPendienteProvider.notifier).state = null;
    try {
      await _controller.stop();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.userMessage)),
    );
    Navigator.of(context).pop();
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
