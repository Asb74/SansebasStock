import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/camera_model.dart';
import '../services/camera_repository.dart';

enum StorageSide { left, right }

class StorageSlotCoordinate {
  const StorageSlotCoordinate({
    required this.side,
    required this.fila,
    required this.posicion,
  });

  final StorageSide side;
  final int fila;
  final int posicion;

  @override
  bool operator ==(Object other) {
    return other is StorageSlotCoordinate &&
        other.side == side &&
        other.fila == fila &&
        other.posicion == posicion;
  }

  @override
  int get hashCode => Object.hash(side, fila, posicion);
}

class StockEntry {
  StockEntry({
    required this.id,
    required this.coordinate,
    required this.data,
    required this.palletCode,
  });

  final String id;
  final StorageSlotCoordinate coordinate;
  final Map<String, dynamic> data;
  final String palletCode;

  int get fila => coordinate.fila;
  int get posicion => coordinate.posicion;
  StorageSide get side => coordinate.side;

  int? get cajas => _asInt(data['CAJAS']);
  int? get neto => _asInt(data['NETO']);

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

class CameraLevelKey {
  const CameraLevelKey({required this.numero, required this.nivel, required this.pasillo});

  final String numero;
  final int nivel;
  final CameraPasillo pasillo;

  @override
  bool operator ==(Object other) {
    return other is CameraLevelKey &&
        other.numero == numero &&
        other.nivel == nivel &&
        other.pasillo == pasillo;
  }

  @override
  int get hashCode => Object.hash(numero, nivel, pasillo);
}

final cameraRepositoryProvider = Provider<CameraRepository>((ref) {
  return CameraRepository();
});

final camerasStreamProvider = StreamProvider<List<CameraModel>>((ref) {
  return ref.watch(cameraRepositoryProvider).watchAll();
});

final cameraByNumeroProvider = StreamProvider.family<CameraModel?, String>((ref, numero) {
  return ref.watch(cameraRepositoryProvider).watchByNumero(numero);
});

final stockByCameraLevelProvider =
    StreamProvider.family<Map<StorageSlotCoordinate, StockEntry>, CameraLevelKey>((ref, key) {
  final firestore = FirebaseFirestore.instance;
  final normalizedNumero = key.numero.padLeft(2, '0');
  final query = firestore
      .collection('Stock')
      .where('CAMARA', isEqualTo: normalizedNumero)
      .where('NIVEL', isEqualTo: key.nivel)
      .where('HUECO', isEqualTo: 'Ocupado');

  return query.snapshots().map((snapshot) {
    final entries = <StorageSlotCoordinate, StockEntry>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final coordinate = _coordinateFromData(data, key.pasillo);
      if (coordinate == null) {
        debugPrint('Ignorando doc ${doc.id} por coordenadas inválidas: ${data.toString()}');
        continue;
      }
      final pallet = _extractPalletCode(doc.id, data);
      entries[coordinate] = StockEntry(
        id: doc.id,
        coordinate: coordinate,
        data: data,
        palletCode: pallet,
      );
    }
    return entries;
  });
});

StorageSlotCoordinate? _coordinateFromData(
  Map<String, dynamic> data,
  CameraPasillo pasillo,
) {
  final rawFila = data['ESTANTERIA'];
  int? fila;
  if (rawFila is int) {
    fila = rawFila;
  } else if (rawFila is String) {
    final digits = RegExp(r'\d+').firstMatch(rawFila)?.group(0);
    fila = int.tryParse(digits ?? rawFila);
  }

  if (fila == null || fila <= 0) {
    return null;
  }

  final rawPos = data['POSICION'];
  int? pos;
  if (rawPos is int) {
    pos = rawPos;
  } else {
    pos = int.tryParse(rawPos?.toString() ?? '');
  }

  if (pos == null || pos <= 0) {
    return null;
  }

  StorageSide side = StorageSide.right;
  if (pasillo == CameraPasillo.central) {
    final rawSide = (data['SIDE'] ?? data['LADO'] ?? data['CARA'] ?? data['S'])?.toString().toLowerCase();
    if (rawSide != null) {
      if (rawSide.contains('left') || rawSide.contains('iz') || rawSide.contains('l')) {
        side = StorageSide.left;
      } else if (rawSide.contains('right') || rawSide.contains('de') || rawSide.contains('r')) {
        side = StorageSide.right;
      }
    } else if (rawFila is String) {
      final upper = rawFila.toUpperCase();
      if (upper.endsWith('I') || upper.endsWith('L')) {
        side = StorageSide.left;
      } else if (upper.endsWith('D') || upper.endsWith('R')) {
        side = StorageSide.right;
      }
    }
  }

  return StorageSlotCoordinate(side: side, fila: fila, posicion: pos);
}

String _extractPalletCode(String docId, Map<String, dynamic> data) {
  final rawP = data['P'];
  if (rawP != null) {
    final value = rawP.toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  if (docId.length <= 4) {
    return docId;
  }
  return docId.substring(docId.length - 4);
}
