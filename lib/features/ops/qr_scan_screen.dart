import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sansebas_stock/features/ops/ops_providers.dart';

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
    final camposQR = _parsePaletQR(raw);
    if (camposQR.isEmpty) {
      _showError('QR de palet inválido');
      return;
    }

    final stockService = ref.read(stockServiceProvider);
    final ubicacionPendiente = ref.read(ubicacionPendienteProvider);

    final result = await stockService.procesarPalet(
      camposQR: camposQR,
      ubicacionQR: _ubicacionToServiceMap(ubicacionPendiente),
    );

    if (!result.ok) {
      if (result.errorCode == 'requires_location') {
        _showError(ubicacionRequeridaMessage);
      } else {
        _showError(result.message ?? 'No se pudo completar la operación');
      }
      return;
    }

    final String accion = (result.data?['accion'] as String?)?.toLowerCase() ?? '';
    final dynamic posicionRaw =
        result.data?['POSICION'] ?? result.data?['posicion'];
    final String? posicion = posicionRaw?.toString();

    switch (accion) {
      case 'entrada':
        if (posicion != null && posicion.isNotEmpty) {
          _showSuccess('Palet registrado correctamente (posición $posicion)');
        } else {
          _showSuccess('Palet registrado correctamente');
        }
        ref.read(ubicacionPendienteProvider.notifier).state = null;
        break;
      case 'salida':
        _showSuccess('Palet marcado como Libre');
        break;
      case 'reubicacion':
        if (posicion != null && posicion.isNotEmpty) {
          _showSuccess('Palet reubicado correctamente (posición $posicion)');
        } else {
          _showSuccess('Palet reubicado correctamente');
        }
        ref.read(ubicacionPendienteProvider.notifier).state = null;
        break;
      default:
        _showSuccess('Operación completada');
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
          nivel = int.tryParse(value);
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

  Map<String, String> _parsePaletQR(String raw) {
    final map = <String, String>{};
    for (final part in raw.split('|')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[kv[0].trim().toUpperCase()] = kv[1].trim();
      }
    }
    return map;
  }

  Map<String, String>? _ubicacionToServiceMap(Ubicacion? ubicacion) {
    if (ubicacion == null) {
      return null;
    }
    final rawMap = ubicacion.toMap();
    return rawMap.map((key, value) => MapEntry(key, value.toString()));
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
