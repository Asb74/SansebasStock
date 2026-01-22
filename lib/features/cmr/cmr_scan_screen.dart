import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart' as qr;
import 'package:sansebas_stock/services/stock_service.dart';

import '../ops/ops_providers.dart';
import '../ops/qr_scan_screen.dart';
import 'cmr_models.dart';
import 'cmr_pdf_actions.dart';
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

  final CmrPedido? pedido;
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
  final Set<String> _invalid = <String>{};
  Set<String> _expectedPalets = <String>{};
  Map<String, int?> _lineaByPalet = <String, int?>{};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pedidoSubscription;
  Set<String> _firestorePalets = <String>{};
  String _pedidoEstado = '';
  CmrPedido? _pedido;
  DocumentReference<Map<String, dynamic>>? _pedidoRef;
  String _pedidoId = '';

  @override
  void initState() {
    super.initState();
    _expectedPalets = widget.expectedPalets.map(normalizarPalet).toSet();
    _lineaByPalet = {
      for (final entry in widget.lineaByPalet.entries)
        normalizarPalet(entry.key): entry.value,
    };
    _invalid.addAll(widget.initialInvalid.map(normalizarPalet));
    _pedido = widget.pedido;
    _pedidoRef = widget.pedido?.ref;
    _pedidoId = widget.pedido?.idPedidoLora ?? '';
    if (_pedidoRef != null) {
      _pedidoSubscription = _pedidoRef!
          .snapshots()
          .listen(_handlePedidoSnapshot);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startScan();
      }
    });
  }

  @override
  void dispose() {
    _pedidoSubscription?.cancel();
    super.dispose();
  }

  void _handlePedidoSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!mounted) return;
    if (!snapshot.exists) {
      setState(() {
        _pedidoEstado = '';
        _firestorePalets = <String>{};
        _pedido = null;
      });
      return;
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final estado = data['Estado']?.toString() ?? '';
    final palets = _extractPaletsFromData(data).toSet();
    final expectedFromLineas =
        _expectedPalets.isEmpty ? _buildExpectedPaletsFromData(data) : null;
    final pedido = CmrPedido.fromSnapshot(snapshot);

    setState(() {
      _pedidoEstado = estado;
      _firestorePalets = palets;
      _pedido = pedido;
      if (pedido.idPedidoLora.trim().isNotEmpty) {
        _pedidoId = pedido.idPedidoLora.trim();
      }
      if (expectedFromLineas != null && expectedFromLineas.isNotEmpty) {
        _expectedPalets = expectedFromLineas.keys.toSet();
        _lineaByPalet = expectedFromLineas;
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

      var pedidoRef = _pedidoRef;
      final manualCreated = pedidoRef == null
          ? await _initManualPedidoFromPalet(paletId: paletId, raw: raw)
          : false;
      pedidoRef = _pedidoRef;
      if (pedidoRef == null && !manualCreated) {
        pedidoRef = await _resolvePedidoRefFromQr(raw);
        if (pedidoRef == null) {
          await _showOverlayResult(
            paletId: paletId,
            message: 'No se pudo obtener IdPedidoLora del QR',
            status: _OverlayStatus.invalid,
          );
          return;
        }
      }

      final isManual = manualCreated || _pedidoEstado == 'En_Curso_Manual';
      if (isManual && !_expectedPalets.contains(paletId)) {
        setState(() {
          _expectedPalets.add(paletId);
        });
      }

      final shouldValidate = _expectedPalets.isNotEmpty && !isManual;
      if (shouldValidate) {
        final pedidoSnapshot = await pedidoRef.get();
        final pedidoExiste = pedidoSnapshot.exists;
        final pertenece = await paletPerteneceAPedido(
          firestore: FirebaseFirestore.instance,
          pedidoRef: pedidoRef,
          paletId: paletId,
        );
        if (!pertenece &&
            !(!pedidoExiste && _expectedPalets.contains(paletId))) {
          _invalid.add(paletId);
          await _showOverlayResult(
            paletId: paletId,
            message: 'Palet $paletId no pertenece a este pedido',
            status: _OverlayStatus.invalid,
          );
          return;
        }
      }

      final scanResult = await _upsertPaletInPedido(
        pedidoRef: pedidoRef,
        paletId: paletId,
      );
      if (scanResult == _ScanTransactionResult.expedido) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Pedido ya expedido',
          status: _OverlayStatus.invalid,
        );
        return;
      }
      if (scanResult == _ScanTransactionResult.duplicate) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya escaneado',
          status: _OverlayStatus.alreadyScanned,
        );
        return;
      }

      if (scanResult == _ScanTransactionResult.added) {
        final stockService = ref.read(stockServiceProvider);
        final pedidoId = _pedidoId.isNotEmpty
            ? _pedidoId
            : _pedido?.idPedidoLora ?? '';
        await stockService.liberarPaletParaCmr(
          palletId: paletId,
          pedidoId: pedidoId,
        );
      }

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

  List<String> _extractPaletsFromData(Map<String, dynamic> data) {
    final raw = data['palets'] ?? data['Palets'];
    if (raw is! Iterable) {
      return const [];
    }
    return raw
        .map((value) => normalizarPalet(value?.toString() ?? ''))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Map<String, int?> _buildExpectedPaletsFromData(
    Map<String, dynamic> data,
  ) {
    final rawLineas = data['Lineas'] ?? data['lineas'];
    if (rawLineas is! Iterable) {
      return <String, int?>{};
    }

    final Map<String, int?> map = <String, int?>{};
    for (final item in rawLineas) {
      if (item is! Map) {
        continue;
      }
      final lineNumber = _asLineNumber(item['Linea']);
      final paletRaw = item['Palet']?.toString() ?? '';
      if (paletRaw.trim().isEmpty) {
        continue;
      }
      final palets = paletRaw
          .split('|')
          .map(normalizarPalet)
          .where((value) => value.isNotEmpty);
      for (final palet in palets) {
        map.putIfAbsent(palet, () => lineNumber);
      }
    }
    return map;
  }

  int? _asLineNumber(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  Future<Set<String>> _fetchPaletsFromFirestore() async {
    final pedidoRef = _pedidoRef;
    if (pedidoRef == null) {
      return <String>{};
    }

    final snapshot = await pedidoRef.get();
    if (!snapshot.exists) {
      return <String>{};
    }
    final data = snapshot.data() ?? <String, dynamic>{};
    return _extractPaletsFromData(data).toSet();
  }

  Future<_ScanTransactionResult> _upsertPaletInPedido({
    required DocumentReference<Map<String, dynamic>> pedidoRef,
    required String paletId,
  }) async {
    final db = FirebaseFirestore.instance;
    return db.runTransaction((tx) async {
      final pedidoSnap = await tx.get(pedidoRef);
      if (!pedidoSnap.exists) {
        final base = Map<String, dynamic>.from(
          _pedido?.raw ??
              <String, dynamic>{
                'IdPedidoLora': _pedidoId,
              },
        );
        base['Estado'] = 'En_Curso';
        base['palets'] = [paletId];
        base['createdAt'] = FieldValue.serverTimestamp();
        base['updatedAt'] = FieldValue.serverTimestamp();
        tx.set(pedidoRef, base);
        return _ScanTransactionResult.added;
      }

      final data = pedidoSnap.data() ?? <String, dynamic>{};
      final estado = data['Estado']?.toString() ?? '';
      if (estado == 'Expedido') {
        return _ScanTransactionResult.expedido;
      }

      final palets = _extractPaletsFromData(data);
      if (palets.contains(paletId)) {
        return _ScanTransactionResult.duplicate;
      }

      tx.update(pedidoRef, {
        'Estado': estado == 'Pendiente' ? 'En_Curso' : estado,
        'palets': FieldValue.arrayUnion([paletId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return _ScanTransactionResult.added;
    });
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
    if (_pedidoRef == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedido cargado.')),
      );
      return;
    }

    final scannedPalets = await _fetchPaletsFromFirestore();
    final pendientes = _expectedPalets.difference(scannedPalets).toList()..sort();

    final confirm = await _showFinalDialog(pendientes);
    if (confirm != true) {
      return;
    }

    await _confirmExpedicion(
      pendientes: pendientes,
      scannedPalets: scannedPalets,
    );
  }

  Future<void> _confirmExpedicion({
    required List<String> pendientes,
    required Set<String> scannedPalets,
  }) async {
    final pedidoRef = _pedidoRef;
    if (pedidoRef == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedido cargado.')),
      );
      return;
    }

    final db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    final userName = await _loadUserName(user);
    final pendientesSet = pendientes
        .map(normalizarPalet)
        .where((value) => value.isNotEmpty)
        .toSet();

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

        final lineasKey = data.containsKey('Lineas')
            ? 'Lineas'
            : data.containsKey('lineas')
                ? 'lineas'
                : null;
        if (lineasKey != null && pendientesSet.isNotEmpty) {
          final rawLineas = data[lineasKey];
          if (rawLineas is Iterable) {
            final updatedLineas = <dynamic>[];
            for (final item in rawLineas) {
              if (item is! Map) {
                updatedLineas.add(item);
                continue;
              }
              final lineData = Map<String, dynamic>.from(item);
              final paletRaw = item['Palet']?.toString() ?? '';
              if (paletRaw.trim().isEmpty) {
                updatedLineas.add(lineData);
                continue;
              }
              final palets = paletRaw
                  .split('|')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .where(
                    (value) =>
                        !pendientesSet.contains(normalizarPalet(value)),
                  )
                  .toList();
              if (palets.isEmpty) {
                continue;
              }
              lineData['Palet'] = palets.join('|');
              updatedLineas.add(lineData);
            }

            tx.update(pedidoRef, {lineasKey: updatedLineas});
          }
        }

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
            'pedidoOriginal': _pedido?.idPedidoLora ?? _pedidoId,
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
      final updatedSnapshot = await pedidoRef.get();
      final pedidoActualizado = updatedSnapshot.exists
          ? CmrPedido.fromSnapshot(updatedSnapshot)
          : _pedido;
      if (!mounted) return;
      if (pedidoActualizado == null) {
        throw Exception('Pedido no encontrado');
      }
      await showCmrPdfActions(context: context, pedido: pedidoActualizado);
      if (!mounted) return;
      Navigator.of(context).pop(
        CmrScanResult(scanned: scannedPalets, invalid: _invalid),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo finalizar el CMR: $e')),
      );
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolvePedidoRefFromQr(
    String raw,
  ) async {
    final pedidoId = _parsePedidoIdFromQr(raw);
    if (pedidoId.isEmpty) {
      return null;
    }

    final pedidoRef =
        FirebaseFirestore.instance.collection('Pedidos').doc(pedidoId);
    _pedidoId = pedidoId;
    _pedidoRef = pedidoRef;
    _pedidoSubscription?.cancel();
    _pedidoSubscription = pedidoRef.snapshots().listen(_handlePedidoSnapshot);
    return pedidoRef;
  }

  String _parsePedidoIdFromQr(String raw) {
    final match = RegExp(
      r'(?:IDPEDIDOLORA|PEDIDOLORA|IDPEDIDO|PEDIDO)=([^|^]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }

    try {
      final parsed = qr.parseQr(raw);
      for (final entry in parsed.rawFields.entries) {
        final key = entry.key.toUpperCase();
        if (key == 'IDPEDIDOLORA' ||
            key == 'PEDIDOLORA' ||
            key == 'IDPEDIDO' ||
            key == 'PEDIDO') {
          return entry.value.trim();
        }
      }
    } catch (_) {}

    return '';
  }

  Future<bool> _initManualPedidoFromPalet({
    required String paletId,
    required String raw,
  }) async {
    if (_pedidoRef != null || _pedidoEstado == 'En_Curso_Manual') {
      return false;
    }

    final db = FirebaseFirestore.instance;
    final stockSnapshot =
        await db.collection('Stock').doc('1$paletId').get();
    final pedidoFromStock =
        stockSnapshot.data()?['PEDIDO']?.toString().trim() ?? '';
    if (pedidoFromStock.isNotEmpty) {
      final pedidoSnapshot =
          await db.collection('Pedidos').doc(pedidoFromStock).get();
      if (pedidoSnapshot.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este palet pertenece a un pedido existente. Accede desde la lista de pedidos.',
              ),
            ),
          );
          Navigator.of(context).pop();
        }
        return false;
      }
    }

    final pedidoId = _parsePedidoIdFromQr(raw);
    DocumentReference<Map<String, dynamic>> pedidoRef;
    if (pedidoId.isNotEmpty) {
      final candidateRef = db.collection('Pedidos').doc(pedidoId);
      final snapshot = await candidateRef.get();
      if (snapshot.exists) {
        return false;
      }
      pedidoRef = candidateRef;
      _pedidoId = pedidoId;
    } else {
      pedidoRef = db.collection('Pedidos').doc();
    }

    final base = Map<String, dynamic>.from(_pedido?.raw ?? <String, dynamic>{});
    if (_pedidoId.isNotEmpty) {
      base['IdPedidoLora'] = _pedidoId;
    }
    base['Estado'] = 'En_Curso_Manual';
    base['palets'] = [paletId];
    base['createdAt'] = FieldValue.serverTimestamp();
    base['updatedAt'] = FieldValue.serverTimestamp();

    await pedidoRef.set(base, SetOptions(merge: true));

    _pedidoRef = pedidoRef;
    _pedidoSubscription?.cancel();
    _pedidoSubscription = pedidoRef.snapshots().listen(_handlePedidoSnapshot);

    if (mounted) {
      setState(() {
        _pedidoEstado = 'En_Curso_Manual';
        _expectedPalets = {paletId};
      });
    }

    return true;
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
                Text('Escaneados: ${_firestorePalets.length}'),
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
    final scannedCount = _firestorePalets.length;
    final isExpedido = _pedidoEstado == 'Expedido';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escaneo CMR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag),
            tooltip: 'Finalizar CMR',
            onPressed: _pedidoRef == null ? null : _finalizarCmr,
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
                        'Escaneados: $scannedCount/${_expectedPalets.length}',
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
        onPressed: _scanInProgress || _busy || _showOverlay || isExpedido
            ? null
            : _startScan,
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

enum _ScanTransactionResult { added, duplicate, expedido }

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
