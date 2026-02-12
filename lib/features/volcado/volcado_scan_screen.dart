import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sansebas_stock/utils/stock_doc_id.dart';

import '../cmr/cmr_utils.dart';
import '../ops/qr_scan_screen.dart';

class VolcadoScanScreen extends StatefulWidget {
  const VolcadoScanScreen({super.key, required this.loteId});

  final String loteId;

  @override
  State<VolcadoScanScreen> createState() => _VolcadoScanScreenState();
}

class _VolcadoScanScreenState extends State<VolcadoScanScreen> {
  bool _busy = false;
  bool _showOverlay = false;
  bool _scanInProgress = false;
  _ScanOverlayData? _overlayData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startScan();
      }
    });
  }

  Future<void> _startScan() async {
    if (_scanInProgress || _busy || _showOverlay) {
      return;
    }

    setState(() {
      _scanInProgress = true;
    });

    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(
          returnScanResult: true,
          scanResultMode: QrScanResultMode.raw,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _scanInProgress = false;
    });

    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    await _handle(raw);
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    final paletId = _parsePaletId(raw);

    var transactionAttempted = false;
    try {
      if (paletId.isEmpty) {
        await _showOverlayResult(
          paletId: '—',
          message: 'QR no reconocido',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final stockDocId = buildStockDocId(paletId);
      final stockSnapshot = await FirebaseFirestore.instance
          .collection('Stock')
          .doc(stockDocId)
          .get();
      if (!stockSnapshot.exists) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'El palet no existe en Stock',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final stockData = stockSnapshot.data() ?? <String, dynamic>{};
      final idLote = stockData['idLote']?.toString().trim() ?? '';
      if (idLote.isNotEmpty) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'El palet ya está asignado a un lote',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final loteSnapshot = await FirebaseFirestore.instance
          .collection('Lotes')
          .doc(widget.loteId)
          .get();
      if (!loteSnapshot.exists) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'El lote no existe',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final loteData = loteSnapshot.data() ?? <String, dynamic>{};
      final stockCultivo = (stockData['CULTIVO'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final loteCultivo2 = (loteData['cultivo2'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final cultivoValido = stockCultivo.isNotEmpty &&
          loteCultivo2.isNotEmpty &&
          stockCultivo == loteCultivo2;
      if (!cultivoValido) {
        await _showCultivoMismatchDialog(
          stockCultivo: stockCultivo,
          loteCultivo2: loteCultivo2,
        );
        return;
      }

      final estado = loteData['estado']?.toString().trim() ?? '';
      if (estado != 'ABIERTO' && estado != 'EN_CURSO') {
        await _showOverlayResult(
          paletId: paletId,
          message: 'El lote no está abierto',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final paletKey = paletId.replaceAll('.', '_');
      final palets = loteData['palets'];
      if (palets is Map && palets.containsKey(paletKey)) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya añadido al lote',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      transactionAttempted = true;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final stockRef = FirebaseFirestore.instance
            .collection('Stock')
            .doc(stockDocId);
        final loteRef = FirebaseFirestore.instance
            .collection('Lotes')
            .doc(widget.loteId);

        final stockDoc = await transaction.get(stockRef);
        if (!stockDoc.exists) {
          throw StateError('Stock no existe');
        }

        final stockTxData = stockDoc.data() ?? <String, dynamic>{};
        final idLoteTx = stockTxData['idLote']?.toString().trim() ?? '';
        if (idLoteTx.isNotEmpty) {
          throw StateError('Stock ya asignado');
        }

        final loteDoc = await transaction.get(loteRef);
        if (!loteDoc.exists) {
          throw StateError('Lote no existe');
        }

        final loteTxData = loteDoc.data() ?? <String, dynamic>{};
        final stockCultivoTx = (stockTxData['CULTIVO'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final loteCultivo2Tx = (loteTxData['cultivo2'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (stockCultivoTx.isEmpty ||
            loteCultivo2Tx.isEmpty ||
            stockCultivoTx != loteCultivo2Tx) {
          throw StateError('Cultivo incompatible');
        }

        final estadoTx = loteTxData['estado']?.toString().trim() ?? '';
        if (estadoTx != 'ABIERTO' && estadoTx != 'EN_CURSO') {
          throw StateError('Lote no abierto');
        }

        final paletKey = paletId.replaceAll('.', '_');
        final paletsTx = loteTxData['palets'];
        if (paletsTx is Map && paletsTx.containsKey(paletKey)) {
          throw StateError('Palet ya en lote');
        }

        final pedido = stockTxData['PEDIDO']?.toString().trim() ?? '';
        final tipo = pedido == 'PRECALIBRADO'
            ? 0
            : pedido == 'ESTANDAR'
                ? 1
                : 2;
        final idPartida = loteTxData['idPartida'];
        final paletsMap =
            (loteTxData['palets'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final updatedPalets = Map<String, dynamic>.from(paletsMap);
        updatedPalets[paletKey] = {
          'palet': paletId,
          'neto': stockTxData['NETO'],
          'cajas': stockTxData['CAJAS'],
          'pedido': stockTxData['PEDIDO'],
          'idPartida': idPartida,
          'calibre': stockTxData['CALIBRE'],
          'tipo': tipo,
          'p_p': 'F',
          'fechaAlta': FieldValue.serverTimestamp(),
        };

        transaction.update(loteRef, {
          'palets': updatedPalets,
        });

        transaction.update(stockRef, {
          'HUECO': 'Libre',
          'idLote': widget.loteId,
        });
      });

      await _showOverlayResult(
        paletId: paletId,
        message: 'Palet añadido al lote',
        status: _OverlayStatus.valid,
        popOnAccept: true,
      );
    } on FirebaseException {
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: transactionAttempted
            ? 'No se pudo añadir el palet'
            : 'No se pudo validar el palet',
        status: _OverlayStatus.invalid,
      );
    } on StateError {
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: 'No se pudo añadir el palet',
        status: _OverlayStatus.invalid,
      );
    } catch (_) {
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: 'No se pudo añadir el palet',
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

  Future<void> _showCultivoMismatchDialog({
    required String stockCultivo,
    required String loteCultivo2,
  }) async {
    final stockValue = stockCultivo.isEmpty ? '—' : stockCultivo;
    final loteValue = loteCultivo2.isEmpty ? '—' : loteCultivo2;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Producto incorrecto'),
          ],
        ),
        content: Text(
          'El palet escaneado pertenece a "$stockValue"\n'
          'y este lote es de "$loteValue".\n\n'
          'No puede añadirse a este lote.',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  String _parsePaletId(String raw) {
    final parsed = parsePaletFromQr(raw);
    if (parsed.isNotEmpty) {
      return parsed;
    }
    return raw.trim();
  }

  Future<void> _showOverlayResult({
    required String paletId,
    required String message,
    required _OverlayStatus status,
    bool popOnAccept = false,
  }) async {
    setState(() {
      _showOverlay = true;
      _overlayData = _ScanOverlayData(
        paletId: paletId,
        message: message,
        status: status,
        popOnAccept: popOnAccept,
      );
    });
  }

  Future<void> _closeOverlay() async {
    setState(() {
      _showOverlay = false;
      _overlayData = null;
    });
  }

  Future<void> _acceptOverlay() async {
    final shouldPop = _overlayData?.popOnAccept ?? false;
    await _closeOverlay();
    if (!mounted || _busy) {
      return;
    }
    if (shouldPop) {
      Navigator.of(context).pop();
      return;
    }
    await _startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear palet'),
      ),
      body: Stack(
        children: [
          const Center(
            child: Text('Escanea un palet para validar el volcado'),
          ),
          if (_showOverlay && _overlayData != null)
            Positioned.fill(
              child: _ScanOverlay(
                data: _overlayData!,
                onAccept: _acceptOverlay,
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
        onPressed: _scanInProgress || _busy || _showOverlay ? null : _startScan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Escanear palet'),
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

enum _OverlayStatus { valid, invalid }

extension on _OverlayStatus {
  Color get color {
    switch (this) {
      case _OverlayStatus.valid:
        return Colors.greenAccent;
      case _OverlayStatus.invalid:
        return Colors.redAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case _OverlayStatus.valid:
        return Icons.check_circle;
      case _OverlayStatus.invalid:
        return Icons.error;
    }
  }
}

class _ScanOverlayData {
  const _ScanOverlayData({
    required this.paletId,
    required this.message,
    required this.status,
    required this.popOnAccept,
  });

  final String paletId;
  final String message;
  final _OverlayStatus status;
  final bool popOnAccept;
}
