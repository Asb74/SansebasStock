import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/qr/qr_parser.dart';

const String ubicacionRequeridaMessage =
    'Ubicación requerida: escanea QR de cámara/estantería/nivel.';

const kOcupado = 'Ocupado';
const kLibre = 'Libre';

final ubicacionPendienteProvider = StateProvider<Ubicacion?>((ref) => null);

final stockServiceProvider = Provider<StockService>((ref) {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  return StockService(firestore, auth);
});

enum StockProcessAction { creadoOcupado, liberado, reubicado }

class StockProcessResult {
  const StockProcessResult({
    required this.action,
    this.ubicacion,
    this.posicion,
  });

  final StockProcessAction action;
  final Ubicacion? ubicacion;
  final int? posicion;
}

class StockService {
  StockService(FirebaseFirestore db, FirebaseAuth auth)
      : _db = db,
        _auth = auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  StockProcessResult? _lastResult;

  StockProcessResult? get lastResult => _lastResult;

  Future<void> procesarLecturaPalet({
    required String rawPaletQr,
    Ubicacion? ubicacionPendiente,
  }) async {
    try {
      final palet = parsePaletQr(rawPaletQr);
      final docRef = _db.collection('Stock').doc(palet.docId);
      final uid = _auth.currentUser?.uid;
      StockProcessResult? operationResult;

      final docSnapshot = await docRef.get();
      final baseData = _buildBaseData(palet);
      final serverTimestamp = FieldValue.serverTimestamp();

      if (!docSnapshot.exists) {
        final ubicacion =
            ubicacionPendiente ?? (throw Exception(ubicacionRequeridaMessage));
        final nextPos = await _getNextPos(ubicacion);
        final payload = <String, dynamic>{
          ...baseData,
          ..._buildUbicacionData(ubicacion, nextPos),
          'HUECO': kOcupado,
          'createdAt': serverTimestamp,
          'updatedAt': serverTimestamp,
          'createdBy': uid,
          'updatedBy': uid,
        };
        await docRef.set(payload, const SetOptions(merge: true));
        operationResult = StockProcessResult(
          action: StockProcessAction.creadoOcupado,
          ubicacion: ubicacion,
          posicion: nextPos,
        );
        _lastResult = operationResult;
        return;
      }

      final data = docSnapshot.data()!;
      final currentHueco = data['HUECO']?.toString().toUpperCase();

      if (currentHueco != kLibre.toUpperCase()) {
        final update = <String, dynamic>{
          'HUECO': kLibre,
          'updatedAt': serverTimestamp,
          'updatedBy': uid,
        };
        await docRef.set(update, const SetOptions(merge: true));
        operationResult = const StockProcessResult(
          action: StockProcessAction.liberado,
        );
        _lastResult = operationResult;
        return;
      }

      final ubicacion =
          ubicacionPendiente ?? (throw Exception(ubicacionRequeridaMessage));
      final nextPos = await _getNextPos(ubicacion);
      final updateData = <String, dynamic>{
        ...baseData,
        ..._buildUbicacionData(ubicacion, nextPos),
        'HUECO': kOcupado,
        'updatedAt': serverTimestamp,
        'updatedBy': uid,
      };
      await docRef.set(updateData, const SetOptions(merge: true));
      operationResult = StockProcessResult(
        action: StockProcessAction.reubicado,
        ubicacion: ubicacion,
        posicion: nextPos,
      );

      _lastResult = operationResult;
    } on FirebaseException catch (e, st) {
      debugPrint('🔥 Firestore Error: ${e.code} -> ${e.message}');
      debugPrintStack(label: '🔥 Firestore stack', stackTrace: st);
      rethrow;
    } catch (e, st) {
      debugPrint('⚠️ Error inesperado: $e');
      debugPrintStack(label: '⚠️ Stack', stackTrace: st);
      rethrow;
    }
  }

  Future<int> _getNextPos(Ubicacion ubicacion) async {
    final nivel = _parseIntValue(ubicacion.nivel, fieldName: 'NIVEL');
    final query = _db
        .collection('Stock')
        .where('CAMARA', isEqualTo: ubicacion.camara)
        .where('ESTANTERIA', isEqualTo: ubicacion.estanteria)
        .where('NIVEL', isEqualTo: nivel)
        .where('HUECO', isEqualTo: kOcupado)
        .orderBy('POSICION', descending: true)
        .limit(1);

    final qSnap = await query.get();
    if (qSnap.docs.isEmpty) {
      return 1;
    }

    final rawPos = qSnap.docs.first.data()['POSICION'];
    final currentPos = rawPos is int
        ? rawPos
        : int.tryParse(rawPos.toString()) ??
            (throw const FormatException('POSICION almacenada no válida.'));

    return currentPos + 1;
  }

  Map<String, dynamic> _buildBaseData(PaletQr palet) {
    final data = <String, dynamic>{
      'P': palet.paletId,
      'LINEAS_QR': palet.lineas,
    };

    palet.campos.forEach((key, value) {
      switch (key) {
        case 'CAJAS':
        case 'NETO':
        case 'LINEA':
          data[key] = _parseIntValue(value, fieldName: key);
          break;
        case 'VIDA':
          data[key] = value;
          break;
        default:
          data[key] = value;
      }
    });

    return data;
  }

  Map<String, dynamic> _buildUbicacionData(Ubicacion ubicacion, int posicion) {
    final nivel = _parseIntValue(ubicacion.nivel, fieldName: 'NIVEL');
    return <String, dynamic>{
      'CAMARA': ubicacion.camara,
      'ESTANTERIA': ubicacion.estanteria,
      'NIVEL': nivel,
      'POSICION': posicion,
    };
  }

  int _parseIntValue(String rawValue, {required String fieldName}) {
    final normalized = rawValue.trim();
    final parsed = int.tryParse(normalized);
    if (parsed == null) {
      throw FormatException('El campo $fieldName requiere un entero. Valor: "$rawValue"');
    }
    return parsed;
  }
}
