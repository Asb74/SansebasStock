import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/qr/qr_parser.dart';

const String ubicacionRequeridaMessage =
    'Ubicación requerida: escanea QR de cámara/estantería/nivel.';

const kOcupado = 'OCUPADO';
const kLibre = 'LIBRE';

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
        'CAMARA': ubicacion.camara,
        'ESTANTERIA': ubicacion.estanteria,
        'NIVEL': ubicacion.nivel,
        'POSICION': nextPos,
        'HUECO': kOcupado,
        'createdAt': serverTimestamp,
        'updatedAt': serverTimestamp,
        'createdBy': uid,
        'updatedBy': uid,
      };
      await docRef.set(payload, SetOptions(merge: true));
      operationResult = StockProcessResult(
        action: StockProcessAction.creadoOcupado,
        ubicacion: ubicacion,
        posicion: nextPos,
      );
      // TODO: Registrar auditoría de ocupaciones/liberaciones (usuario, dispositivo).
      _lastResult = operationResult;
      return;
    }

    final data = docSnapshot.data()!;
    final currentHueco = data['HUECO']?.toString().toUpperCase();

    if (currentHueco != kLibre) {
      final update = <String, dynamic>{
        'HUECO': kLibre,
        'updatedAt': serverTimestamp,
        'updatedBy': uid,
      };
      await docRef.update(update);
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
      'CAMARA': ubicacion.camara,
      'ESTANTERIA': ubicacion.estanteria,
      'NIVEL': ubicacion.nivel,
      'POSICION': nextPos,
      'HUECO': kOcupado,
      'updatedAt': serverTimestamp,
      'updatedBy': uid,
    };
    await docRef.update(updateData);
    operationResult = StockProcessResult(
      action: StockProcessAction.reubicado,
      ubicacion: ubicacion,
      posicion: nextPos,
    );

    _lastResult = operationResult;
  }

  Future<int> _getNextPos(Ubicacion ubicacion) async {
    final query = _db
        .collection('Stock')
        .where('CAMARA', isEqualTo: ubicacion.camara)
        .where('ESTANTERIA', isEqualTo: ubicacion.estanteria)
        .where('NIVEL', isEqualTo: ubicacion.nivel)
        .where('HUECO', isEqualTo: kOcupado)
        .orderBy('POSICION', descending: true)
        .limit(1);

    final qSnap = await query.get();
    final nextPos = qSnap.docs.isEmpty
        ? 1
        : (qSnap.docs.first.data()['POSICION'] as int) + 1;

    return nextPos;
  }

  Map<String, dynamic> _buildBaseData(PaletQr palet) {
    return <String, dynamic>{
      'P': palet.paletId,
      'LINEAS_QR': palet.lineas,
      ...palet.campos,
    };
  }
}
