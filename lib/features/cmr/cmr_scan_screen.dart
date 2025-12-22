import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:sansebas_stock/services/stock_service.dart';

import '../ops/ops_providers.dart';
import '../ops/qr_scan_screen.dart';
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

class _CmrScanScreenState extends ConsumerState<CmrScanScreen> {
  bool _busy = false;
  bool _showOverlay = false;
  bool _scanInProgress = false;
  _ScanOverlayData? _overlayData;
  final Set<String> _scanned = <String>{};
  final Set<String> _invalid = <String>{};
  late final Set<String> _expectedPalets;
  late final Map<String, int?> _lineaByPalet;

  @override
  void initState() {
    super.initState();
    _expectedPalets = widget.expectedPalets.map(normalizarPalet).toSet();
    _lineaByPalet = {
      for (final entry in widget.lineaByPalet.entries)
        normalizarPalet(entry.key): entry.value,
    };
    _scanned.addAll(widget.initialScanned.map(normalizarPalet));
    _invalid.addAll(widget.initialInvalid.map(normalizarPalet));

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

    try {
      final paletId = parsePaletFromQr(raw);
      if (paletId.isEmpty) {
        await _showOverlayResult(
          paletId: '—',
          message: 'QR no reconocido',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      if (_scanned.contains(paletId)) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya escaneado',
          status: _OverlayStatus.alreadyScanned,
        );
        return;
      }

      final pertenece = await paletPerteneceAPedido(
        firestore: FirebaseFirestore.instance,
        pedidoRef: widget.pedido.ref,
        paletId: paletId,
      );
      if (!pertenece) {
        _invalid.add(paletId);
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet $paletId no pertenece a este pedido',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      final stockService = ref.read(stockServiceProvider);
      await stockService.liberarPaletParaCmr(
        palletId: paletId,
        pedidoId: widget.pedido.idPedidoLora,
      );
      _scanned.add(paletId);

      await _showOverlayResult(
        paletId: paletId,
        message: 'Palet correcto',
        status: _OverlayStatus.valid,
      );
    } on FormatException catch (e) {
      final paletId = parsePaletFromQr(raw);
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: e.message,
        status: _OverlayStatus.invalid,
      );
    } on StockProcessException catch (e) {
      final paletId = parsePaletFromQr(raw);
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: e.message,
        status: _OverlayStatus.invalid,
      );
    } on FirebaseException {
      final paletId = parsePaletFromQr(raw);
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
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
  }

  Future<void> _finalizarCmr() async {
    final pendientes = _expectedPalets.difference(_scanned).toList()..sort();

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
    final userName = await _loadUserName(user);

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
          'updatedAt': FieldValue.serverTimestamp(),
          'expedidoPor': user?.uid,
          'expedidoPorEmail': user?.email,
        });

        for (final palet in pendientes) {
          final stockDocId = '1$palet';
          final stockRef = db.collection('Stock').doc(stockDocId);
          await tx.get(stockRef);
          tx.set(
            stockRef,
            {
              'PEDIDO': 'S/P',
              'HUECO': 'Ocupado',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });

      try {
        for (final palet in pendientes) {
          await db.collection('Incidencias').doc().set({
            'paletId': palet,
            'pedidoOriginal': widget.pedido.idPedidoLora,
            'motivo': 'No cargado en CMR',
            'fecha': FieldValue.serverTimestamp(),
            'userId': user?.uid,
            'userEmail': user?.email,
            'userName': userName,
            'estado': 'Pendiente',
          });
        }
      } catch (e) {
        debugPrint('No se pudo guardar la incidencia: $e');
      }

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

  Future<String?> _loadUserName(User? user) async {
    if (user == null) {
      return null;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('UsuariosAutorizados')
          .doc(user.uid)
          .get();
      return snapshot.data()?['Nombre']?.toString();
    } catch (e) {
      debugPrint('No se pudo cargar el nombre de usuario: $e');
      return null;
    }
  }

  Future<void> _generateAndSharePdf() async {
    final service = CmrPdfService(FirebaseFirestore.instance);
    final palets = _expectedPalets.toList();
    final file = await service.generatePdf(
      pedido: widget.pedido,
      palets: palets,
      lineaByPalet: _lineaByPalet,
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
                const Text(
                  'Los palets no escaneados pasarán a S/P y se registrará '
                  'una incidencia. ¿Continuar?',
                ),
                const SizedBox(height: 12),
                Text('Esperados: ${_expectedPalets.length}'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_scanner),
                      const SizedBox(width: 8),
                      Text(
                        'Escaneados: ${_scanned.length}/${_expectedPalets.length}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_invalid.isNotEmpty) ...[
                Text(
                  'Palets no válidos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._invalid.map(
                  (palet) => Card(
                    color: Colors.red.withOpacity(0.05),
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.redAccent),
                      title: Text(palet),
                      subtitle: const Text('No pertenece al pedido'),
                    ),
                  ),
                ),
              ],
            ],
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
