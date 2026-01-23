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
  final Set<String> _processingPalets = <String>{};
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
    _expectedPalets = widget.expectedPalets.map(_normalizePaletId).toSet();
    _lineaByPalet = {
      for (final entry in widget.lineaByPalet.entries)
        _normalizePaletId(entry.key): entry.value,
    };
    _invalid.addAll(widget.initialInvalid.map(_normalizePaletId));
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

    var processedPaletId = '';
    setState(() {
      _busy = true;
    });

    try {
      final paletId = _normalizePaletId(parsePaletFromQr(raw));
      processedPaletId = paletId;
      if (paletId.isEmpty) {
        await _showOverlayResult(
          paletId: '—',
          message: 'QR no reconocido',
          status: _OverlayStatus.invalid,
        );
        return;
      }
      if (_processingPalets.contains(paletId)) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya escaneado',
          status: _OverlayStatus.alreadyScanned,
        );
        return;
      }
      _processingPalets.add(paletId);

      final pedidoResolution = await _resolvePedidoForPalet(
        raw: raw,
        paletId: paletId,
      );
      if (pedidoResolution == null) {
        _processingPalets.remove(paletId);
        return;
      }

      final manualInit = await _initManualPedidoFromPalet(
        paletId: paletId,
        pedido: pedidoResolution,
      );
      if (manualInit == null) {
        _processingPalets.remove(paletId);
        return;
      }

      final pedidoRef = manualInit.ref;
      final estadoNormalizado = manualInit.estado;
      final isManual = estadoNormalizado == 'En_Curso_Manual';
      if (isManual && !_expectedPalets.contains(paletId)) {
        setState(() {
          _expectedPalets.add(paletId);
        });
      }

      if (estadoNormalizado == 'En_Curso') {
        final pertenece = await paletPerteneceALineasPedido(
          firestore: FirebaseFirestore.instance,
          pedidoRef: pedidoRef,
          paletId: paletId,
        );
        if (!pertenece) {
          _invalid.add(paletId);
          await _showOverlayResult(
            paletId: paletId,
            message: 'El palet no pertenece al pedido',
            status: _OverlayStatus.invalid,
          );
          return;
        }
      } else if (!isManual && _expectedPalets.isNotEmpty) {
        final pertenece = await paletPerteneceAPedido(
          firestore: FirebaseFirestore.instance,
          pedidoRef: pedidoRef,
          paletId: paletId,
        );
        if (!pertenece) {
          _invalid.add(paletId);
          await _showOverlayResult(
            paletId: paletId,
            message: 'El palet no pertenece al pedido',
            status: _OverlayStatus.invalid,
          );
          return;
        }
      }

      final alreadyScanned = await _isPaletAlreadyScanned(
        pedidoRef: pedidoRef,
        paletId: paletId,
      );
      if (alreadyScanned) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'Palet ya escaneado',
          status: _OverlayStatus.alreadyScanned,
        );
        return;
      }

      final scanResult =
          manualInit.created
              ? _ScanTransactionResult.added
              : await _upsertPaletInPedido(
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
      if (scanResult == _ScanTransactionResult.missingPedido) {
        await _showOverlayResult(
          paletId: paletId,
          message: 'No se pudo cargar el pedido del palet',
          status: _OverlayStatus.invalid,
        );
        return;
      }

      if (scanResult == _ScanTransactionResult.added) {
        final stockService = ref.read(stockServiceProvider);
        final pedidoId = pedidoRef.id;
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
      final paletId = _normalizePaletId(parsePaletFromQr(raw));
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: e.message,
        status: _OverlayStatus.invalid,
      );
    } on StockProcessException catch (e) {
      final paletId = _normalizePaletId(parsePaletFromQr(raw));
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: e.message,
        status: _OverlayStatus.invalid,
      );
    } on FirebaseException {
      final paletId = _normalizePaletId(parsePaletFromQr(raw));
      await _showOverlayResult(
        paletId: paletId.isEmpty ? '—' : paletId,
        message: 'No se pudo actualizar el palet',
        status: _OverlayStatus.invalid,
      );
    } finally {
      if (processedPaletId.isNotEmpty) {
        _processingPalets.remove(processedPaletId);
      }
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
        .map((value) => _normalizePaletId(value?.toString() ?? ''))
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
          .map(_normalizePaletId)
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

  String _normalizePaletId(String raw) {
    final normalized = normalizarPalet(raw).trim();
    if (normalized.isEmpty) {
      return '';
    }
    if (RegExp(r'^\d{11}$').hasMatch(normalized) &&
        normalized.startsWith('1')) {
      return normalized.substring(1);
    }
    return normalized;
  }

  String _normalizePedidoId(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }
    final whitespaceNormalized = value.replaceAll(RegExp(r'\s+'), '_');
    final slashNormalized = whitespaceNormalized.replaceAll('/', '_');
    return slashNormalized.replaceAll(RegExp(r'_+'), '_');
  }

  bool _isPedidoSeleccionable(String pedidoDisplay) {
    final normalized = pedidoDisplay.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final upper = normalized.toUpperCase();
    if (upper == 'S/P' || upper == 'S_P' || upper == 'SP') {
      return false;
    }
    const prefixes = <String>['PC', 'PK', 'PM', 'PN', 'PS'];
    return prefixes.any((prefix) => upper.startsWith(prefix));
  }

  Future<_PedidoResolution?> _resolvePedidoForPalet({
    required String raw,
    required String paletId,
  }) async {
    final pedidoFromQr = _parsePedidoDisplayFromQr(raw);
    var pedidoDisplay = pedidoFromQr.trim();
    if (pedidoDisplay.isEmpty) {
      final stockSnapshot = await FirebaseFirestore.instance
          .collection('Stock')
          .doc('1$paletId')
          .get();
      pedidoDisplay = stockSnapshot.data()?['PEDIDO']?.toString().trim() ?? '';
    }

    if (!_isPedidoSeleccionable(pedidoDisplay)) {
      await _showOverlayResult(
        paletId: paletId,
        message: 'Palet no seleccionable para CMR (sin pedido válido)',
        status: _OverlayStatus.invalid,
      );
      return null;
    }

    final pedidoDocId = _normalizePedidoId(pedidoDisplay);
    if (pedidoDocId.isEmpty) {
      await _showOverlayResult(
        paletId: paletId,
        message: 'Palet no seleccionable para CMR (sin pedido válido)',
        status: _OverlayStatus.invalid,
      );
      return null;
    }

    final pedidoRef =
        FirebaseFirestore.instance.collection('Pedidos').doc(pedidoDocId);
    return _PedidoResolution(
      displayId: pedidoDisplay,
      docId: pedidoDocId,
      ref: pedidoRef,
    );
  }

  void _switchPedidoContext({
    required DocumentReference<Map<String, dynamic>> pedidoRef,
    required String pedidoDisplay,
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  }) {
    final isDifferent = _pedidoRef?.id != pedidoRef.id;
    _pedidoRef = pedidoRef;
    _pedidoId = pedidoDisplay;
    if (snapshot != null && snapshot.exists) {
      _pedido = CmrPedido.fromSnapshot(snapshot);
      _pedidoEstado = snapshot.data()?['Estado']?.toString() ?? '';
    } else {
      _pedido = null;
      _pedidoEstado = '';
    }
    if (isDifferent) {
      _pedidoSubscription?.cancel();
      _pedidoSubscription = pedidoRef.snapshots().listen(_handlePedidoSnapshot);
      _expectedPalets = <String>{};
      _lineaByPalet = <String, int?>{};
      _firestorePalets = <String>{};
    }
    if (mounted) {
      setState(() {});
    }
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

  Future<bool> _isPaletAlreadyScanned({
    required DocumentReference<Map<String, dynamic>> pedidoRef,
    required String paletId,
  }) async {
    if (_firestorePalets.contains(paletId)) {
      return true;
    }
    final snapshot = await pedidoRef.get();
    if (!snapshot.exists) {
      return false;
    }
    final data = snapshot.data() ?? <String, dynamic>{};
    final palets = _extractPaletsFromData(data);
    return palets.contains(paletId);
  }

  Future<_ScanTransactionResult> _upsertPaletInPedido({
    required DocumentReference<Map<String, dynamic>> pedidoRef,
    required String paletId,
  }) async {
    final db = FirebaseFirestore.instance;
    return db.runTransaction((tx) async {
      final pedidoSnap = await tx.get(pedidoRef);
      if (!pedidoSnap.exists) {
        return _ScanTransactionResult.missingPedido;
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

      final estadoActual = data['Estado']?.toString() ?? '';
      final nuevoEstado =
          estadoActual == 'Pendiente'
              ? 'En_Curso'
              : estadoActual == 'En_Curso_Manual'
                  ? 'En_Curso_Manual'
                  : estadoActual;
      tx.update(pedidoRef, {
        'Estado': nuevoEstado,
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
    if (status == _OverlayStatus.invalid &&
        _processingPalets.contains(paletId)) {
      _processingPalets.remove(paletId);
    }
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
        .map(_normalizePaletId)
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
                        !pendientesSet.contains(_normalizePaletId(value)),
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

  String _parsePedidoDisplayFromQr(String raw) {
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

  Future<_PedidoLoadResult?> _initManualPedidoFromPalet({
    required String paletId,
    required _PedidoResolution pedido,
  }) async {
    final db = FirebaseFirestore.instance;
    final pedidoRef = pedido.ref;
    final pedidoSnapshot = await pedidoRef.get();
    if (!pedidoSnapshot.exists) {
      await _createManualPedido(
        db: db,
        paletId: paletId,
        pedidoDocId: pedido.docId,
        pedidoDisplay: pedido.displayId,
      );
      return _PedidoLoadResult(
        ref: pedidoRef,
        estado: 'En_Curso_Manual',
        created: true,
      );
    }

    _switchPedidoContext(
      pedidoRef: pedidoRef,
      pedidoDisplay: pedido.displayId,
      snapshot: pedidoSnapshot,
    );
    final estadoNormalizado = _normalizePedidoEstado(
      pedidoSnapshot.data()?['Estado']?.toString(),
    );
    return _PedidoLoadResult(
      ref: pedidoRef,
      estado: estadoNormalizado,
      created: false,
    );
  }

  Future<void> _createManualPedido({
    required FirebaseFirestore db,
    required String paletId,
    required String pedidoDocId,
    required String pedidoDisplay,
  }) async {
    final pedidoRef = db.collection('Pedidos').doc(pedidoDocId);
    _pedidoId = pedidoDisplay;

    final base = <String, dynamic>{
      'IdPedidoLora': pedidoDisplay,
      'Estado': 'En_Curso_Manual',
      'palets': [paletId],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await pedidoRef.set(base, SetOptions(merge: true));

    _switchPedidoContext(
      pedidoRef: pedidoRef,
      pedidoDisplay: pedidoDisplay,
      snapshot: null,
    );

    if (mounted) {
      setState(() {
        _pedidoEstado = 'En_Curso_Manual';
        _expectedPalets = {paletId};
        _lineaByPalet = <String, int?>{};
        _firestorePalets = <String>{};
      });
    }

    return;
  }

  String _normalizePedidoEstado(String? estadoRaw) {
    final estado = estadoRaw?.trim() ?? '';
    if (estado == 'Expedido') {
      return 'Expedido';
    }
    if (estado == 'En_Curso_Manual') {
      return 'En_Curso_Manual';
    }
    if (estado == 'Pendiente' || estado == 'En_Curso' || estado.isEmpty) {
      return 'En_Curso';
    }
    return 'En_Curso';
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

class _PedidoResolution {
  const _PedidoResolution({
    required this.displayId,
    required this.docId,
    required this.ref,
  });

  final String displayId;
  final String docId;
  final DocumentReference<Map<String, dynamic>> ref;
}

class _PedidoLoadResult {
  const _PedidoLoadResult({
    required this.ref,
    required this.estado,
    required this.created,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final String estado;
  final bool created;
}

enum _ScanTransactionResult { added, duplicate, expedido, missingPedido }

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
