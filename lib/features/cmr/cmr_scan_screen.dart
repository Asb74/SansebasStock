import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';

import '../ops/ops_providers.dart';
import '../qr/qr_parser.dart' as qr;
import 'cmr_models.dart';
import 'cmr_pdf_service.dart';
import 'cmr_utils.dart';

class CmrScanScreen extends ConsumerStatefulWidget {
  const CmrScanScreen({
    super.key,
    required this.pedido,
    required this.expectedPalets,
    required this.lineaByPalet,
    required this.initialScanned,
    required this.initialInvalid,
  });

  final CmrPedido pedido;
  final List<String> expectedPalets;
  final Map<String, int?> lineaByPalet;
  final Set<String> initialScanned;
  final Set<String> initialInvalid;

  @override
  ConsumerState<CmrScanScreen> createState() => _CmrScanScreenState();
}

final bool _isDesktop =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
final bool _isMobile = Platform.isAndroid || Platform.isIOS;

class _CmrScanScreenState extends ConsumerState<CmrScanScreen> {
  MobileScannerController? _controller;
  bool _busy = false;
  bool _showOverlay = false;
  _ScanOverlayData? _overlayData;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  final Set<String> _scanned = <String>{};
  final Set<String> _invalid = <String>{};

  static const Duration _detectionCooldown = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _scanned.addAll(widget.initialScanned.map(normalizePaletId));
    _invalid.addAll(widget.initialInvalid.map(normalizePaletId));
    if (_isMobile) {
      _controller = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pauseScanner() async {
    try {
      await _controller?.stop();
    } catch (_) {}
  }

  Future<void> _resumeScanner() async {
    try {
      await _controller?.start();
    } catch (_) {}
  }

  Future<void> _onBarcodeScanned(String raw) async {
    if (_busy || _showOverlay) {
      return;
    }
    final now = DateTime.now();
    if (_lastScannedCode == raw &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < _detectionCooldown) {
      return;
    }
    _lastScannedCode = raw;
    _lastScanTime = now;

    await _pauseScanner();
    await _handle(raw);
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final trimmed = raw.trim();
      if (!_isPaletQr(trimmed)) {
        await _showOverlayResult(
          paletId: trimmed,
          message: 'QR no reconocido',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final parsed = qr.parseQr(trimmed);
      final paletId = normalizePaletId('${parsed.linea}${parsed.p}');

      if (_scanned.contains(paletId)) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya escaneado',
          status: _OverlayStatus.alreadyScanned,
        );
        return;
      }

      if (!widget.expectedPalets.contains(paletId)) {
        _invalid.add(paletId);
        await _showOverlayResult(
          paletId: paletId,
          message: 'No pertenece al pedido',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final stockService = ref.read(stockServiceProvider);
      await stockService.liberarPaletParaCmr(palletId: paletId);
      _scanned.add(paletId);

      await _showOverlayResult(
        paletId: paletId,
        message: 'Palet correcto',
        status: _OverlayStatus.valid,
      );
    } on FormatException catch (e) {
      await _showOverlayResult(
        paletId: raw,
        message: e.message,
        status: _OverlayStatus.invalid,
      );
    } on FirebaseException {
      await _showOverlayResult(
        paletId: raw,
        message: 'No se pudo actualizar el palet',
        status: _OverlayStatus.invalid,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _showOverlayResult({
    required String paletId,
    required String message,
    required _OverlayStatus status,
  }) async {
    setState(() {
      _showOverlay = true;
      _overlayData = _ScanOverlayData(
        paletId: paletId,
        message: message,
        status: status,
      );
    });
  }

  Future<void> _closeOverlay() async {
    setState(() {
      _showOverlay = false;
      _overlayData = null;
    });
    await _resumeScanner();
  }

  Future<void> _finalizarCmr() async {
    final expectedSet = widget.expectedPalets.toSet();
    final pendientes = expectedSet.difference(_scanned).toList()..sort();

    final confirm = await _showFinalDialog(pendientes);
    if (confirm != true) {
      return;
    }

    await _confirmExpedicion(pendientes);
  }

  Future<void> _confirmExpedicion(List<String> pendientes) async {
    final db = FirebaseFirestore.instance;
    final pedidoRef = widget.pedido.ref;
    final user = FirebaseAuth.instance.currentUser;

    try {
      await db.runTransaction((tx) async {
        final pedidoSnap = await tx.get(pedidoRef);
        if (!pedidoSnap.exists) {
          throw Exception('Pedido no encontrado');
        }
        final data = pedidoSnap.data() as Map<String, dynamic>;
        if ((data['Estado']?.toString() ?? '') == 'Expedido') {
          throw Exception('Pedido ya expedido');
        }

        tx.update(pedidoRef, {
          'Estado': 'Expedido',
          'expedidoAt': FieldValue.serverTimestamp(),
          'expedidoPor': user?.uid,
          'expedidoPorEmail': user?.email,
        });

        for (final palet in _scanned) {
          final stockRef = db.collection('Stock').doc(palet);
          tx.set(stockRef, {'HUECO': 'Libre'}, SetOptions(merge: true));
        }

        for (final palet in pendientes) {
          final stockRef = db.collection('Stock').doc(palet);
          tx.set(
            stockRef,
            {
              'PEDIDO': 'S/P',
              'HUECO': 'Ocupado',
            },
            SetOptions(merge: true),
          );

          final incidenciaRef = db.collection('Incidencias').doc();
          tx.set(incidenciaRef, {
            'type': 'CMR_NO_ESCANEADO',
            'pedidoId': widget.pedido.idPedidoLora,
            'pedidoDocId': widget.pedido.id,
            'paletId': palet,
            'linea': widget.lineaByPalet[palet],
            'timestamp': FieldValue.serverTimestamp(),
            'userId': user?.uid,
            'userEmail': user?.email,
            'accion': 'PASAR_A_SP',
            'stockDespues': {
              'PEDIDO': 'S/P',
              'HUECO': 'Ocupado',
            },
          });
        }
      });

      if (!mounted) return;
      await _generateAndSharePdf();
      if (!mounted) return;
      Navigator.of(context).pop(
        CmrScanResult(scanned: _scanned, invalid: _invalid),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo finalizar el CMR: $e')),
      );
    }
  }

  Future<void> _generateAndSharePdf() async {
    final service = CmrPdfService(FirebaseFirestore.instance);
    final palets = widget.expectedPalets.map(normalizePaletId).toList();
    final file = await service.generatePdf(
      pedido: widget.pedido,
      palets: palets,
      lineaByPalet: widget.lineaByPalet,
    );

    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: 'cmr_${widget.pedido.idPedidoLora}.pdf',
    );
  }

  Future<bool?> _showFinalDialog(List<String> pendientes) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar expedición'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Esperados: ${widget.expectedPalets.length}'),
                Text('Escaneados: ${_scanned.length}'),
                Text('No escaneados: ${pendientes.length}'),
                const SizedBox(height: 12),
                if (pendientes.isNotEmpty)
                  SizedBox(
                    height: 140,
                    child: ListView.builder(
                      itemCount: pendientes.length,
                      itemBuilder: (context, index) {
                        return Text('• ${pendientes[index]}');
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar expedición'),
            ),
          ],
        );
      },
    );
  }

  bool _isPaletQr(String raw) {
    return raw.toUpperCase().contains('P=');
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return _DesktopQrPlaceholder(
        onClose: () => Navigator.of(context).pop(
          CmrScanResult(scanned: _scanned, invalid: _invalid),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escaneo CMR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag),
            tooltip: 'Finalizar CMR',
            onPressed: _finalizarCmr,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            fit: BoxFit.cover,
            onDetect: (capture) async {
              if (_busy || _showOverlay) {
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

              await _onBarcodeScanned(raw);
            },
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_scanner),
                      const SizedBox(width: 8),
                      Text(
                        'Escaneados: ${_scanned.length}/${widget.expectedPalets.length}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showOverlay && _overlayData != null)
            Positioned.fill(
              child: _ScanOverlay(
                data: _overlayData!,
                onAccept: _closeOverlay,
              ),
            ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _finalizarCmr,
        icon: const Icon(Icons.check),
        label: const Text('Finalizar CMR'),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.data, required this.onAccept});

  final _ScanOverlayData data;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = data.status.color;
    final subtitle = data.message;

    return Material(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Palet leído:',
                style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                data.paletId,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(data.status.icon, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: theme.textTheme.titleMedium?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: onAccept,
                child: const Text('Aceptar'),
              ),
            ],
          ),
        ),
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
        title: const Text('Escaneo CMR'),
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
            ],
          ),
        ),
      ),
    );
  }
}

enum _OverlayStatus { valid, invalid, alreadyScanned }

extension on _OverlayStatus {
  Color get color {
    switch (this) {
      case _OverlayStatus.valid:
        return Colors.greenAccent;
      case _OverlayStatus.invalid:
        return Colors.redAccent;
      case _OverlayStatus.alreadyScanned:
        return Colors.orangeAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case _OverlayStatus.valid:
        return Icons.check_circle;
      case _OverlayStatus.invalid:
        return Icons.error;
      case _OverlayStatus.alreadyScanned:
        return Icons.info;
    }
  }
}

class _ScanOverlayData {
  const _ScanOverlayData({
    required this.paletId,
    required this.message,
    required this.status,
  });

  final String paletId;
  final String message;
  final _OverlayStatus status;
}
