import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sansebas_stock/features/qr/qr_parser.dart';

class Result {
  final bool ok;
  final String? errorCode;
  final String? message;
  final Map<String, dynamic>? data;

  const Result.ok({this.data})
      : ok = true,
        errorCode = null,
        message = null;

  const Result.err(this.errorCode, this.message)
      : ok = false,
        data = null;
}

class StockService {
  StockService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Procesa la lógica de entrada, salida y reubicación de un palet.
  Future<Result> procesarPalet({
    required Map<String, String> camposQR,
    Map<String, String>? ubicacionQR,
  }) async {
    try {
      debugPrint('Procesar palet con camposQR=$camposQR ubicacionQR=$ubicacionQR');

      final Map<String, dynamic> datosPalet = _normalizarCamposQR(camposQR);
      final int lineaNumero = (datosPalet['LINEA'] as int?) ?? 0;
      final String linea = lineaNumero > 0 ? lineaNumero.toString() : '';
      final String? pRaw = datosPalet['P']?.toString();
      final String p = onlyDigits(pRaw);

      if (linea.isEmpty || p.isEmpty) {
        return const Result.err(
          'bad_qr',
          'El QR del palet no incluye valores válidos para LINEA y P.',
        );
      }

      final String docId = '$linea$p';
      final DocumentReference<Map<String, dynamic>> docRef =
          _db.collection('Stock').doc(docId);

      final _Ubicacion? ubicacion = _normalizarUbicacion(ubicacionQR);

      debugPrint('Comprobando documento Stock/$docId');
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await docRef.get();

      if (!snapshot.exists) {
        debugPrint('Documento no existe. Se trata de una entrada.');
        if (ubicacion == null) {
          return const Result.err(
            'requires_location',
            'Escanea primero el QR de la cámara para ubicar el palet.',
          );
        }

        final int siguientePosicion = await _siguientePosicion(
          camara: ubicacion.camara,
          estanteria: ubicacion.estanteria,
          nivel: ubicacion.nivel,
        );
        debugPrint(
          'Entrada en ${ubicacion.camara}/${ubicacion.estanteria}/${ubicacion.nivel} -> POSICION $siguientePosicion',
        );

        await _db.runTransaction((transaction) async {
          transaction.set(docRef, {
            ...datosPalet,
            'CAMARA': ubicacion.camara,
            'ESTANTERIA': ubicacion.estanteria,
            'NIVEL': ubicacion.nivel,
            'POSICION': siguientePosicion,
            'HUECO': 'Ocupado',
          });
        });

        return Result.ok(
          data: {
            'accion': 'entrada',
            'docId': docId,
            'CAMARA': ubicacion.camara,
            'ESTANTERIA': ubicacion.estanteria,
            'NIVEL': ubicacion.nivel,
            'POSICION': siguientePosicion,
          },
        );
      }

      final Map<String, dynamic> datosActuales = snapshot.data() ?? <String, dynamic>{};
      final String huecoActual =
          (datosActuales['HUECO']?.toString().toLowerCase() ?? 'ocupado');

      if (huecoActual == 'ocupado') {
        debugPrint('Documento existente con HUECO=Ocupado. Se procesa salida.');
        await _db.runTransaction((transaction) async {
          transaction.update(docRef, {'HUECO': 'Libre'});
        });

        return Result.ok(
          data: {
            'accion': 'salida',
            'docId': docId,
          },
        );
      }

      debugPrint('Documento existente con HUECO=Libre. Se requiere reubicación.');
      if (ubicacion == null) {
        return const Result.err(
          'requires_location',
          'El palet está Libre. Escanea el QR de ubicación para reubicarlo.',
        );
      }

      final int siguientePosicion = await _siguientePosicion(
        camara: ubicacion.camara,
        estanteria: ubicacion.estanteria,
        nivel: ubicacion.nivel,
      );
      debugPrint(
        'Reubicación a ${ubicacion.camara}/${ubicacion.estanteria}/${ubicacion.nivel} -> POSICION $siguientePosicion',
      );

      await _db.runTransaction((transaction) async {
        transaction.update(docRef, {
          ...datosPalet,
          'CAMARA': ubicacion.camara,
          'ESTANTERIA': ubicacion.estanteria,
          'NIVEL': ubicacion.nivel,
          'POSICION': siguientePosicion,
          'HUECO': 'Ocupado',
        });
      });

      return Result.ok(
        data: {
          'accion': 'reubicacion',
          'docId': docId,
          'CAMARA': ubicacion.camara,
          'ESTANTERIA': ubicacion.estanteria,
          'NIVEL': ubicacion.nivel,
          'POSICION': siguientePosicion,
        },
      );
    } on FirebaseException catch (e, st) {
      debugPrint('Firestore error [${e.code}]: ${e.message}');
      debugPrintStack(label: 'Firestore stack', stackTrace: st);
      final String friendly = _friendlyMessage(e.code, e.message);
      return Result.err(e.code, friendly);
    } catch (e, st) {
      debugPrint('Error inesperado al procesar palet: $e');
      debugPrintStack(label: 'Stack', stackTrace: st);
      return const Result.err('unknown', 'No se pudo completar la operación.');
    }
  }

  Future<int> _siguientePosicion({
    required String camara,
    required String estanteria,
    required int nivel,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> q = await _db
        .collection('Stock')
        .where('CAMARA', isEqualTo: camara)
        .where('ESTANTERIA', isEqualTo: estanteria)
        .where('NIVEL', isEqualTo: nivel)
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

  Map<String, dynamic> _normalizarCamposQR(Map<String, String> campos) {
    final Map<String, dynamic> normalizados = <String, dynamic>{};

    campos.forEach((key, value) {
      final String campo = key.trim();
      if (campo.isEmpty) {
        return;
      }
      final String valor = value.trim();
      switch (campo) {
        case 'LINEA':
        case 'CAJAS':
        case 'NETO':
        case 'NIVEL':
        case 'POSICION':
          normalizados[campo] = _intValue(valor);
          break;
        case 'VIDA':
          normalizados[campo] = valor;
          break;
        default:
          if (campo == 'P') {
            final String? p = _stringValue(valor);
            if (p != null) {
              normalizados[campo] = p;
            }
          } else if (valor.isNotEmpty) {
            normalizados[campo] = valor;
          }
      }
    });

    normalizados['LINEA'] = _intValue(campos['LINEA']);
    normalizados['CAJAS'] = _intValue(campos['CAJAS']);
    normalizados['NETO'] = _intValue(campos['NETO']);
    normalizados['NIVEL'] = _intValue(campos['NIVEL']);
    normalizados['POSICION'] = _intValue(campos['POSICION']);
    normalizados['VIDA'] = _stringValue(campos['VIDA']) ?? '';

    final String? p = _stringValue(campos['P']);
    if (p != null) {
      normalizados['P'] = p;
    }

    return normalizados;
  }

  _Ubicacion? _normalizarUbicacion(Map<String, String>? ubicacionQR) {
    if (ubicacionQR == null) {
      return null;
    }
    final String? camara = _stringValue(ubicacionQR['CAMARA']);
    final String? estanteria = _stringValue(ubicacionQR['ESTANTERIA']);
    final int nivel = _intValue(ubicacionQR['NIVEL']);

    if (camara == null || estanteria == null || nivel <= 0) {
      return null;
    }

    return _Ubicacion(
      camara: camara,
      estanteria: estanteria,
      nivel: nivel,
    );
  }

  int _intValue(String? value) => int.tryParse(value?.trim() ?? '') ?? 0;

  String? _stringValue(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
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

class _Ubicacion {
  const _Ubicacion({
    required this.camara,
    required this.estanteria,
    required this.nivel,
  });

  final String camara;
  final String estanteria;
  final int nivel;
}
