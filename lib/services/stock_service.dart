import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart';

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

class StockLocation {
  const StockLocation({
    required this.camara,
    required this.estanteria,
    required this.nivel,
  });

  final String camara;
  final String estanteria;
  final int nivel;

  Map<String, dynamic> toMap() => {
        'CAMARA': camara,
        'ESTANTERIA': estanteria,
        'NIVEL': nivel,
      };
}

class StockService {
  StockService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<StockProcessResult> procesarPalet({
    required ParsedQr qr,
    StockLocation? ubicacion,
  }) async {
    try {
      final String docId = '${qr.linea}${qr.p}';
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection('Stock').doc(docId);

      debugPrint('Procesando Stock/$docId');
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();

      if (!snapshot.exists) {
        if (ubicacion == null) {
          throw const StockProcessException(
            StockProcessException.requiresLocationCode,
            'Escanea primero el QR de la cámara para ubicar el palet.',
          );
        }

        final int posicion = await _siguientePosicion(ubicacion);
        final Map<String, dynamic> data = _buildBaseData(qr)
          ..addAll(ubicacion.toMap())
          ..['POSICION'] = posicion
          ..['HUECO'] = 'Ocupado';

        await ref.set(data, SetOptions(merge: true));

        return StockProcessResult(
          action: StockProcessAction.creadoOcupado,
          id: docId,
          posicion: posicion,
          ubicacion: ubicacion,
        );
      }

      final Map<String, dynamic> current = snapshot.data() ?? <String, dynamic>{};
      final String huecoActual =
          (current['HUECO']?.toString().toLowerCase() ?? 'ocupado');

      if (huecoActual == 'ocupado') {
        await ref.set({'HUECO': 'Libre'}, SetOptions(merge: true));
        return StockProcessResult(
          action: StockProcessAction.liberado,
          id: docId,
        );
      }

      if (ubicacion == null) {
        throw const StockProcessException(
          StockProcessException.requiresLocationCode,
          'El palet está Libre. Escanea el QR de ubicación para reubicarlo.',
        );
      }

      final int posicion = await _siguientePosicion(ubicacion);
      final Map<String, dynamic> data = _buildBaseData(qr)
        ..addAll(ubicacion.toMap())
        ..['POSICION'] = posicion
        ..['HUECO'] = 'Ocupado';

      await ref.set(data, SetOptions(merge: true));

      return StockProcessResult(
        action: StockProcessAction.reubicado,
        id: docId,
        posicion: posicion,
        ubicacion: ubicacion,
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
