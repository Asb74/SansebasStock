import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/qr/qr_parser.dart';

const String ubicacionRequeridaMessage =
    'Ubicación requerida: escanea QR de cámara/estantería/nivel.';

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

    await _db.runTransaction((tx) async {
      final docSnapshot = await tx.get(docRef);
      final baseData = _buildBaseData(palet);
      final serverTimestamp = FieldValue.serverTimestamp();

      if (!docSnapshot.exists) {
        final ubicacion =
            ubicacionPendiente ?? (throw Exception(ubicacionRequeridaMessage));
        final nextPos = await _getNextPosInTx(tx: tx, ubic: ubicacion);
        final payload = <String, dynamic>{
          ...baseData,
          'CAMARA': ubicacion.camara,
          'ESTANTERIA': ubicacion.estanteria,
          'NIVEL': ubicacion.nivel,
          'POSICION': nextPos,
          'HUECO': 'Ocupado',
          'createdAt': serverTimestamp,
          'updatedAt': serverTimestamp,
          'createdBy': uid,
          'updatedBy': uid,
        };
        tx.set(docRef, payload);
        operationResult = StockProcessResult(
          action: StockProcessAction.creadoOcupado,
          ubicacion: ubicacion,
          posicion: nextPos,
        );
        // TODO: Registrar auditoría de ocupaciones/liberaciones (usuario, dispositivo).
        return;
      }

      final data = docSnapshot.data()!;
      final currentHueco = data['HUECO']?.toString().toLowerCase();

      if (currentHueco != 'libre') {
        final update = <String, dynamic>{
          'HUECO': 'Libre',
          'updatedAt': serverTimestamp,
          'updatedBy': uid,
        };
        tx.update(docRef, update);
        operationResult = const StockProcessResult(
          action: StockProcessAction.liberado,
        );
        return;
      }

      final ubicacion =
          ubicacionPendiente ?? (throw Exception(ubicacionRequeridaMessage));
      final nextPos = await _getNextPosInTx(tx: tx, ubic: ubicacion);
      final updateData = <String, dynamic>{
        ...baseData,
        'CAMARA': ubicacion.camara,
        'ESTANTERIA': ubicacion.estanteria,
        'NIVEL': ubicacion.nivel,
        'POSICION': nextPos,
        'HUECO': 'Ocupado',
        'updatedAt': serverTimestamp,
        'updatedBy': uid,
      };
      tx.update(docRef, updateData);
      operationResult = StockProcessResult(
        action: StockProcessAction.reubicado,
        ubicacion: ubicacion,
        posicion: nextPos,
      );
    });

    _lastResult = operationResult;
  }

  Future<int> _getNextPosInTx({
    required Transaction tx,
    required Ubicacion ubic,
  }) async {
    final query = _db
        .collection('Stock')
        .where('CAMARA', isEqualTo: ubic.camara)
        .where('ESTANTERIA', isEqualTo: ubic.estanteria)
        .where('NIVEL', isEqualTo: ubic.nivel)
        .where('HUECO', isEqualTo: 'Ocupado')
        .orderBy('POSICION', descending: true)
        .limit(1);
    // Nota: es posible que Firestore solicite crear un índice compuesto para
    // (CAMARA, ESTANTERIA, NIVEL) con orderBy en POSICION descendente.
    final snapshot = await tx.get(query);
    int? maxPos;
    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      final pos = data['POSICION'];
      if (pos is int) {
        maxPos = pos;
      } else if (pos is num) {
        maxPos = pos.toInt();
      }
    }
    return (maxPos ?? 0) + 1;
  }

  Map<String, dynamic> _buildBaseData(PaletQr palet) {
    return <String, dynamic>{
      'P': palet.paletId,
      'LINEAS_QR': palet.lineas,
      ...palet.campos,
    };
  }
}
