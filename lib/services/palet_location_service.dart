import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/camera_model.dart';
import '../models/palet.dart';
import '../models/stock_location.dart';
import '../models/storage_row_config.dart';

class PaletLocationDescriptor {
  const PaletLocationDescriptor({
    this.cultivo,
    this.marca,
    this.variedad,
    this.calibre,
    this.categoria,
  });

  final String? cultivo;
  final String? marca;
  final String? variedad;
  final String? calibre;
  final String? categoria;
}

String? norm(String? v) =>
    v == null ? null : v.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

bool isActiveRow(StorageRowConfig row) {
  return row.cultivo?.isNotEmpty == true &&
      row.variedad?.isNotEmpty == true &&
      row.calibre?.isNotEmpty == true &&
      row.categoria?.isNotEmpty == true;
}

class AutoLocationResult {
  const AutoLocationResult({
    required this.camera,
    required this.fila,
    required this.nivel,
    required this.posicion,
  });

  final CameraModel camera;
  final int fila;
  final int nivel;
  final int posicion;
}

class NextSlotResult {
  const NextSlotResult({required this.nivel, required this.posicion});

  final int nivel;
  final int posicion;
}

class PaletLocationService {
  AutoLocationResult? findAutoLocationForIncomingPalet({
    required PaletLocationDescriptor palet,
    required List<CameraModel> cameras,
    required Map<String, List<StorageRowConfig>> storageConfigByCamera,
    required Map<String, List<Palet>> currentStockByCameraAndRow,
  }) {
    final candidates = _rowCandidates(
      palet: palet,
      cameras: cameras,
      storageConfigByCamera: storageConfigByCamera,
      currentStockByCameraAndRow: currentStockByCameraAndRow,
    );

    for (final candidate in candidates) {
      if (candidate.nextSlot == null) continue;
      if (candidate.ocupados >= candidate.capacidad) continue;

      return AutoLocationResult(
        camera: candidate.camera,
        fila: candidate.fila,
        nivel: candidate.nextSlot!.nivel,
        posicion: candidate.nextSlot!.posicion,
      );
    }

    return null;
  }

  Future<AutoLocationResult?> findAutoLocationForIncomingPaletFresh({
    required PaletLocationDescriptor palet,
    required List<CameraModel> cameras,
    required Map<String, List<Palet>> currentStockByCameraAndRow,
    required FirebaseFirestore firestore,
  }) async {
    return _rowCandidatesFresh(
      palet: palet,
      cameras: cameras,
      currentStockByCameraAndRow: currentStockByCameraAndRow,
      firestore: firestore,
    );
  }

  Future<StockLocation?> resolveQrLocation({
    required StockLocation? ubicacionQr,
    required bool esExpedicion,
    required CameraModel? camera,
    required FirebaseFirestore firestore,
  }) async {
    if (esExpedicion && ubicacionQr != null) {
      return ubicacionQr;
    }

    if (ubicacionQr == null || ubicacionQr.posicion != null) {
      return ubicacionQr;
    }

    if (camera == null) {
      return ubicacionQr;
    }

    final fila = _parseFila(ubicacionQr.estanteria);
    if (fila == null) {
      return ubicacionQr;
    }

    final slot = await findNextFreeSlotFresh(
      camara: camera.displayNumero,
      fila: fila,
      niveles: camera.niveles,
      posicionesMax: camera.posicionesMax,
      firestore: firestore,
    );

    if (slot == null) {
      return ubicacionQr;
    }

    return StockLocation(
      camara: camera.displayNumero,
      estanteria: fila.toString().padLeft(2, '0'),
      nivel: slot.nivel,
      posicion: slot.posicion,
    );
  }

  _Slot? findFirstAvailableSlot({
    required CameraModel camera,
    required int fila,
    required Map<String, List<Palet>> currentStockByCameraAndRow,
  }) {
    final stock = _occupiedForRow(
      currentStockByCameraAndRow,
      _cameraKeys(camera),
      fila,
    );

    return _firstFreeSlot(
      stock,
      niveles: camera.niveles,
      posicionesMax: camera.posicionesMax,
    );
  }

  List<Palet> _occupiedForRow(
    Map<String, List<Palet>> stockMap,
    Set<String> cameraKeys,
    int fila,
  ) {
    final normalizedFila = fila.toString().padLeft(2, '0');
    final matches = <Palet>[];

    for (final cameraKey in cameraKeys) {
      final candidates = stockMap['${cameraKey.trim()}|$normalizedFila'];
      if (candidates != null) {
        matches.addAll(candidates);
      }
    }

    return matches;
  }

  Future<AutoLocationResult?> _rowCandidatesFresh({
    required PaletLocationDescriptor palet,
    required List<CameraModel> cameras,
    required Map<String, List<Palet>> currentStockByCameraAndRow,
    required FirebaseFirestore firestore,
  }) async {
    final orderedCameras = cameras
        .where((camera) => camera.tipo == CameraTipo.recepcion)
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));

    for (final camera in orderedCameras) {
      final lookup = _CameraLookup(camera: camera, keys: _cameraKeys(camera));
      final rows = await _getConfigsForCamera(lookup.camera.id, firestore);
      if (rows.isEmpty) continue;

      final filteredRows = rows.where(isActiveRow).toList()
        ..sort((a, b) => a.fila.compareTo(b.fila));

      for (final row in filteredRows) {
        if (!_matchesConfig(row, palet)) continue;

        final stock = _occupiedForRow(
          currentStockByCameraAndRow,
          lookup.keys,
          row.fila,
        );
        final capacity = lookup.camera.niveles * lookup.camera.posicionesMax;
        if (capacity <= 0) continue;

        final nextSlot = _firstFreeSlot(
          stock,
          niveles: lookup.camera.niveles,
          posicionesMax: lookup.camera.posicionesMax,
        );

        final occupiedCount = stock.length;
        if (nextSlot != null && occupiedCount < capacity) {
          return AutoLocationResult(
            camera: lookup.camera,
            fila: row.fila,
            nivel: nextSlot.nivel,
            posicion: nextSlot.posicion,
          );
        }
      }
    }

    return null;
  }

  Future<List<StorageRowConfig>> _getConfigsForCamera(
    String camaraId,
    FirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore
        .collection('StorageConfig')
        .doc(camaraId)
        .collection('rows')
        .orderBy('fila')
        .get();

    return snapshot.docs
        .map(
          (doc) => StorageRowConfig.fromDoc(
            camaraId,
            doc.id,
            doc.data(),
          ),
        )
        .toList();
  }

  List<_RowCandidate> _rowCandidates({
    required PaletLocationDescriptor palet,
    required List<CameraModel> cameras,
    required Map<String, List<StorageRowConfig>> storageConfigByCamera,
    required Map<String, List<Palet>> currentStockByCameraAndRow,
  }) {
    final normalizedCameras = cameras
        .where((camera) => camera.tipo == CameraTipo.recepcion)
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));

    final candidates = <_RowCandidate>[];

    for (final camera in normalizedCameras) {
      final lookup = _CameraLookup(camera: camera, keys: _cameraKeys(camera));
      final rows = storageConfigByCamera[lookup.camera.id];
      if (rows == null || rows.isEmpty) continue;

      final filteredRows = rows.where(isActiveRow).toList()
        ..sort((a, b) => a.fila.compareTo(b.fila));

      for (final row in filteredRows) {
        if (!_matchesConfig(row, palet)) continue;

        final stock = _occupiedForRow(
          currentStockByCameraAndRow,
          lookup.keys,
          row.fila,
        );
        final capacity = lookup.camera.niveles * lookup.camera.posicionesMax;
        if (capacity <= 0) continue;

        final nextSlot = _firstFreeSlot(
          stock,
          niveles: lookup.camera.niveles,
          posicionesMax: lookup.camera.posicionesMax,
        );

        final occupiedCount = stock.length;
        candidates.add(
          _RowCandidate(
            camera: lookup.camera,
            fila: row.fila,
            capacidad: capacity,
            ocupados: occupiedCount,
            nextSlot: nextSlot,
            niveles: lookup.camera.niveles,
            posicionesMax: lookup.camera.posicionesMax,
          ),
        );
      }
    }

    candidates.sort((a, b) {
      final byCamera = a.camera.numero.compareTo(b.camera.numero);
      if (byCamera != 0) return byCamera;
      return a.fila.compareTo(b.fila);
    });

    return candidates;
  }

  bool _matchesConfig(StorageRowConfig row, PaletLocationDescriptor palet) {
    bool matchesField(String? expected, String? actual) {
      final normalizedExpected = norm(expected);
      if (normalizedExpected == null || normalizedExpected.isEmpty) {
        return true;
      }

      final normalizedActual = norm(actual);
      if (normalizedActual == null || normalizedActual.isEmpty) {
        return false;
      }

      return normalizedExpected == normalizedActual;
    }

    if (!matchesField(row.cultivo, palet.cultivo)) return false;
    if (!matchesField(row.variedad, palet.variedad)) return false;
    if (!matchesField(row.calibre, palet.calibre)) return false;
    if (!matchesField(row.categoria, palet.categoria)) return false;
    if (row.marca != null && row.marca!.trim().isNotEmpty) {
      if (!matchesField(row.marca, palet.marca)) return false;
    }

    return true;
  }

  _Slot? _firstFreeSlot(
    List<Palet> occupied, {
    required int niveles,
    required int posicionesMax,
  }) {
    if (niveles <= 0 || posicionesMax <= 0) return null;

    final taken = occupied
        .where((p) => p.estaOcupado)
        .map((p) => _Slot(nivel: p.nivel, posicion: p.posicion))
        .toSet();

    for (int posicion = 1; posicion <= posicionesMax; posicion++) {
      for (int nivel = 1; nivel <= niveles; nivel++) {
        final slot = _Slot(nivel: nivel, posicion: posicion);
        if (!taken.contains(slot)) {
          return slot;
        }
      }
    }

    return null;
  }

  Set<String> _cameraKeys(CameraModel camera) {
    final numero = camera.numero.trim();
    final paddedNumero = numero.padLeft(2, '0');
    return {camera.id.trim(), numero, paddedNumero, camera.displayNumero};
  }

  int? _parseFila(String estanteria) {
    final digits = RegExp(r'\d+').firstMatch(estanteria.trim())?.group(0);
    if (digits == null) return null;
    return int.tryParse(digits);
  }

  Future<NextSlotResult?> findNextFreeSlotFresh({
    required String camara,
    required int fila,
    required int niveles,
    required int posicionesMax,
    required FirebaseFirestore firestore,
  }) async {
    if (niveles <= 0 || posicionesMax <= 0) return null;

    final normalizedCamara = camara.padLeft(2, '0');
    final normalizedFila = fila.toString().padLeft(2, '0');

    final snapshot = await firestore
        .collection('Stock')
        .where('CAMARA', isEqualTo: normalizedCamara)
        .where('ESTANTERIA', isEqualTo: normalizedFila)
        .where('HUECO', isEqualTo: 'Ocupado')
        .get();

    final taken = snapshot.docs.map((doc) {
      final data = doc.data();
      final nivel = data['NIVEL'];
      final posicion = data['POSICION'];
      return _Slot(
        nivel: nivel is int ? nivel : int.tryParse(nivel?.toString() ?? '') ?? 0,
        posicion:
            posicion is int ? posicion : int.tryParse(posicion?.toString() ?? '') ?? 0,
      );
    }).toSet();

    for (int posicion = 1; posicion <= posicionesMax; posicion++) {
      for (int nivel = 1; nivel <= niveles; nivel++) {
        final slot = _Slot(nivel: nivel, posicion: posicion);
        if (!taken.contains(slot)) {
          return NextSlotResult(nivel: nivel, posicion: posicion);
        }
      }
    }

    return null;
  }
}

class _Slot {
  const _Slot({required this.nivel, required this.posicion});

  final int nivel;
  final int posicion;

  @override
  bool operator ==(Object other) {
    return other is _Slot && other.nivel == nivel && other.posicion == posicion;
  }

  @override
  int get hashCode => Object.hash(nivel, posicion);
}

class _CameraLookup {
  _CameraLookup({required this.camera, required this.keys});

  final CameraModel camera;
  final Set<String> keys;
}

class _RowCandidate {
  _RowCandidate({
    required this.camera,
    required this.fila,
    required this.capacidad,
    required this.ocupados,
    required this.nextSlot,
    required this.niveles,
    required this.posicionesMax,
  });

  final CameraModel camera;
  final int fila;
  final int capacidad;
  final int ocupados;
  final _Slot? nextSlot;
  final int niveles;
  final int posicionesMax;
}
