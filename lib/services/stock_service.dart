import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart';

import '../models/camera_model.dart';
import '../models/stock_location.dart';
import 'palet_location_service.dart';

enum StockProcessAction { creadoOcupado, liberado, reubicado }

class StockProcessResult {
  const StockProcessResult({
    required this.action,
    required this.id,
    this.posicion,
    this.ubicacion,
  });

  final StockProcessAction action;
  final String id;
  final int? posicion;
  final StockLocation? ubicacion;

  String get userMessage {
    switch (action) {
      case StockProcessAction.creadoOcupado:
        if (posicion != null && posicion! > 0) {
          return 'Palet registrado correctamente (posición $posicion)';
        }
        return 'Palet registrado correctamente';
      case StockProcessAction.liberado:
        return 'Palet marcado como Libre';
      case StockProcessAction.reubicado:
        if (posicion != null && posicion! > 0) {
          return 'Palet reubicado correctamente (posición $posicion)';
        }
        return 'Palet reubicado correctamente';
    }
  }
}

class StockProcessException implements Exception {
  const StockProcessException(this.code, this.message);

  final String code;
  final String message;

  static const String requiresLocationCode = 'requires_location';

  @override
  String toString() => 'StockProcessException($code, $message)';
}

class StockService {
  StockService(
    this._db, {
    PaletLocationService? locationService,
  }) : _locationService = locationService ?? PaletLocationService();

  final FirebaseFirestore _db;
  final PaletLocationService _locationService;

  Future<void> movePalet({
    required String stockDocId,
    required String idPalet,
    required String fromCamara,
    required String fromEstanteria,
    required int fromPosicion,
    required int fromNivel,
    required String toCamara,
    required String toEstanteria,
    required int toPosicion,
    required int toNivel,
    required String usuario,
  }) async {
    final db = _db;

    await db.runTransaction((tx) async {
      final stockRef = db.collection('Stock').doc(stockDocId);

      final snap = await tx.get(stockRef);
      if (!snap.exists) {
        throw Exception('El palet ya no existe en Stock');
      }

      final data = snap.data() as Map<String, dynamic>;

      // Confirmar posición de origen
      if (data['CAMARA'] != fromCamara ||
          data['ESTANTERIA'] != fromEstanteria ||
          (data['POSICION'] as num).toInt() != fromPosicion ||
          (data['NIVEL'] as num).toInt() != fromNivel) {
        throw Exception('El palet cambió de posición mientras tanto');
      }

      if (data['HUECO'] != 'Ocupado') {
        throw Exception('El palet ya no está en un hueco ocupado');
      }

      // Actualizar posición
      tx.update(stockRef, {
        'CAMARA': toCamara,
        'ESTANTERIA': toEstanteria,
        'POSICION': toPosicion,
        'NIVEL': toNivel,
      });

      // Crear log
      final logRef = db.collection('StockLogs').doc();
      tx.set(logRef, {
        'tipo': 'MOVE',
        'idpalet': idPalet,
        'stockDocId': stockDocId,
        'fromCamara': fromCamara,
        'fromEstanteria': fromEstanteria,
        'fromPosicion': fromPosicion,
        'fromNivel': fromNivel,
        'toCamara': toCamara,
        'toEstanteria': toEstanteria,
        'toPosicion': toPosicion,
        'toNivel': toNivel,
        'fechaHora': FieldValue.serverTimestamp(),
        'usuario': usuario,
      });
    });
  }

  Future<StockProcessResult> procesarPalet({
    required ParsedQr qr,
    StockLocation? ubicacion,
  }) async {
    try {
      final StockLocation? resolvedUbicacion = await _resolveUbicacion(ubicacion);
      final String docId = '${qr.linea}${qr.p}';
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection('Stock').doc(docId);

      debugPrint('Procesando Stock/$docId');
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();

      if (!snapshot.exists) {
        if (resolvedUbicacion == null) {
          throw const StockProcessException(
            StockProcessException.requiresLocationCode,
            'Escanea primero el QR de la cámara para ubicar el palet.',
          );
        }

        final int posicion =
            resolvedUbicacion.posicion ?? await _siguientePosicion(resolvedUbicacion);
        final Map<String, dynamic> data = _buildBaseData(qr)
          ..addAll(resolvedUbicacion.toMap())
          ..['POSICION'] = posicion
          ..['HUECO'] = 'Ocupado';

        await ref.set(data, SetOptions(merge: true));

        await _writeStockLog(
          palletId: docId,
          fromValue: 'new',
          toValue: 'Ocupado',
        );

        return StockProcessResult(
          action: StockProcessAction.creadoOcupado,
          id: docId,
          posicion: posicion,
          ubicacion: resolvedUbicacion,
        );
      }

      final Map<String, dynamic> current = snapshot.data() ?? <String, dynamic>{};
      final String huecoAnterior = _normalizeHuecoValue(current['HUECO']);
      final String huecoActual =
          (current['HUECO']?.toString().toLowerCase() ?? 'ocupado');

      if (huecoActual == 'ocupado') {
        await ref.set({'HUECO': 'Libre'}, SetOptions(merge: true));

        await _writeStockLog(
          palletId: docId,
          fromValue: huecoAnterior,
          toValue: 'Libre',
        );

        return StockProcessResult(
          action: StockProcessAction.liberado,
          id: docId,
        );
      }

      if (resolvedUbicacion == null) {
        throw const StockProcessException(
          StockProcessException.requiresLocationCode,
          'El palet está Libre. Escanea el QR de ubicación para reubicarlo.',
        );
      }

      final int posicion =
          resolvedUbicacion.posicion ?? await _siguientePosicion(resolvedUbicacion);
      final Map<String, dynamic> data = _buildBaseData(qr)
        ..addAll(resolvedUbicacion.toMap())
        ..['POSICION'] = posicion
        ..['HUECO'] = 'Ocupado';

      await ref.set(data, SetOptions(merge: true));

      await _writeStockLog(
        palletId: docId,
        fromValue: huecoAnterior,
        toValue: 'Ocupado',
      );

      return StockProcessResult(
        action: StockProcessAction.reubicado,
        id: docId,
        posicion: posicion,
        ubicacion: resolvedUbicacion,
      );
    } on FirebaseException catch (e, st) {
      debugPrint('Firestore error [${e.code}]: ${e.message}');
      debugPrintStack(label: 'Firestore stack', stackTrace: st);
      throw StockProcessException(e.code, _friendlyMessage(e.code, e.message));
    } on StockProcessException {
      rethrow;
    } catch (e, st) {
      debugPrint('Error inesperado al procesar palet: $e');
      debugPrintStack(label: 'Stack', stackTrace: st);
      throw const StockProcessException(
        'unknown',
        'No se pudo completar la operación.',
      );
    }
  }

  Future<void> liberarPaletParaCmr({
    required String palletId,
    String? pedidoId,
  }) async {
    final stockDocId = '1$palletId';
    final ref = _db.collection('Stock').doc(stockDocId);
    final normalizedPedidoId = pedidoId?.trim() ?? '';

    try {
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        debugPrint('Palet $palletId no existe en Stock');
        return;
      }

      final current = snapshot.data() ?? <String, dynamic>{};
      final huecoAnterior = _normalizeHuecoValue(current['HUECO']);

      final updateData = <String, dynamic>{
        'HUECO': 'Libre',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (normalizedPedidoId.isNotEmpty) {
        updateData['PEDIDO'] = normalizedPedidoId;
      }

      await ref.set(updateData, SetOptions(merge: true));
      await _writeStockLog(
        palletId: stockDocId,
        fromValue: huecoAnterior,
        toValue: 'Libre',
      );
    } on FirebaseException catch (e, st) {
      debugPrint('Firestore error [${e.code}]: ${e.message}');
      debugPrintStack(label: 'Firestore stack', stackTrace: st);
    } catch (e, st) {
      debugPrint('Error inesperado al liberar palet: $e');
      debugPrintStack(label: 'Stack', stackTrace: st);
    }
  }

  Future<StockLocation?> _resolveUbicacion(StockLocation? ubicacion) async {
    if (ubicacion == null) {
      return null;
    }

    final camera = await _fetchCamera(ubicacion.camara);
    final esExpedicion = camera?.tipo == CameraTipo.expedicion;

    return _locationService.resolveQrLocation(
      ubicacionQr: ubicacion,
      esExpedicion: esExpedicion,
      camera: camera,
      firestore: _db,
    );
  }

  Future<CameraModel?> _fetchCamera(String camara) async {
    final normalized = camara.trim().padLeft(2, '0');
    final doc = await _db.collection('Storage').doc(normalized).get();
    if (!doc.exists) {
      return null;
    }
    return CameraModel.fromDoc(doc);
  }

  Future<int> _siguientePosicion(StockLocation ubicacion) async {
    final QuerySnapshot<Map<String, dynamic>> q = await _db
        .collection('Stock')
        .where('CAMARA', isEqualTo: ubicacion.camara)
        .where('ESTANTERIA', isEqualTo: ubicacion.estanteria)
        .where('NIVEL', isEqualTo: ubicacion.nivel)
        .where('HUECO', isEqualTo: 'Ocupado')
        .orderBy('POSICION', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      return 1;
    }

    final Map<String, dynamic> lastData = q.docs.first.data();
    final dynamic rawPosicion = lastData['POSICION'];
    final int posicion = rawPosicion is int
        ? rawPosicion
        : int.tryParse(rawPosicion?.toString() ?? '') ?? 0;

    return posicion <= 0 ? 1 : posicion + 1;
  }

  Map<String, dynamic> _buildBaseData(ParsedQr qr) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(qr.data);
    data['P'] = qr.p;
    data['LINEA'] = qr.linea;
    data['CAJAS'] = qr.cajas;
    data['NETO'] = qr.neto;
    data['NIVEL'] = qr.nivel;
    data['POSICION'] = qr.posicion;
    data['VIDA'] = qr.vida;
    data['LINEAS'] = qr.lineas;
    return data;
  }

  String _normalizeHuecoValue(dynamic value) {
    final String raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return 'Ocupado';
    }

    final String lower = raw.toLowerCase();
    if (lower == 'ocupado') {
      return 'Ocupado';
    }
    if (lower == 'libre') {
      return 'Libre';
    }

    return raw;
  }

  Future<void> _writeStockLog({
    required String palletId,
    required String fromValue,
    required String toValue,
  }) async {
    try {
      if (fromValue.toLowerCase() == toValue.toLowerCase()) {
        return;
      }

      final User? user = FirebaseAuth.instance.currentUser;
      final String? uid = user?.uid;
      if (uid == null) {
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> userDoc = await _db
          .collection('UsuariosAutorizados')
          .doc(uid)
          .get();

      final String? userName = userDoc.data()?['Nombre']?.toString();

      await _db.collection('StockLogs').add(<String, dynamic>{
        'palletId': palletId,
        'campo': 'HUECO',
        'from': fromValue,
        'to': toValue,
        'userId': uid,
        'userEmail': user?.email,
        'userName': userName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('Error al escribir en StockLogs: $e');
      debugPrintStack(label: 'StockLogs stack', stackTrace: st);
    }
  }

  String _friendlyMessage(String code, String? rawMessage) {
    switch (code) {
      case 'permission-denied':
        return 'Permiso denegado por las reglas de seguridad.';
      case 'unavailable':
        return 'Servicio no disponible. Revisa tu conexión.';
      case 'failed-precondition':
        return 'Operación no válida en el estado actual.';
      case 'aborted':
        return 'La transacción fue abortada. Intenta de nuevo.';
      default:
        return rawMessage?.isNotEmpty == true
            ? rawMessage!
            : 'No se pudo completar la operación.';
    }
  }
}
