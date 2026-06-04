import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/cmr/cmr_utils.dart';
import '../models/pallet_group.dart';
import '../utils/stock_doc_id.dart';

class PalletGroupConflictException implements Exception {
  const PalletGroupConflictException(this.palletId);

  final String palletId;

  @override
  String toString() => 'El QR $palletId ya pertenece a un grupo.';
}

class PalletGroupUngroupResolution {
  const PalletGroupUngroupResolution({
    required this.scannedStockId,
    required this.groupId,
    required this.referencePalletId,
    required this.memberPalletIds,
    required this.stockExists,
    required this.stockHueco,
    required this.isExpedido,
    required this.pedidosEncontrados,
    this.group,
  });

  final String scannedStockId;
  final String groupId;
  final String referencePalletId;
  final List<String> memberPalletIds;
  final bool stockExists;
  final String stockHueco;
  final bool isExpedido;
  final List<String> pedidosEncontrados;
  final PalletGroup? group;

  bool get isGrouped => group != null && groupId.isNotEmpty;
  bool get canUngroup => isGrouped && !isExpedido;
}

class PalletGroupService {
  PalletGroupService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<bool> memberExists(String palletId) async {
    final snapshot = await _db
        .collection('PalletGroupMembers')
        .doc(palletId)
        .get();
    return snapshot.exists;
  }

  Future<PalletGroupUngroupResolution> resolveGroupForUngroup(
    String scannedStockId,
  ) async {
    final normalizedScannedStockId = scannedStockId.trim();
    if (normalizedScannedStockId.isEmpty) {
      return const PalletGroupUngroupResolution(
        scannedStockId: '',
        groupId: '',
        referencePalletId: '',
        memberPalletIds: <String>[],
        stockExists: false,
        stockHueco: '',
        isExpedido: false,
        pedidosEncontrados: <String>[],
      );
    }

    final cmrResolution = await resolverGrupoCmr(
      firestore: _db,
      scannedPalletId: normalizedScannedStockId,
    );
    final groupId = cmrResolution.groupId;

    if (!cmrResolution.isGrouped || groupId.isEmpty) {
      return PalletGroupUngroupResolution(
        scannedStockId: normalizedScannedStockId,
        groupId: groupId,
        referencePalletId: '',
        memberPalletIds: const <String>[],
        stockExists: false,
        stockHueco: '',
        isExpedido: false,
        pedidosEncontrados: const <String>[],
      );
    }

    final groupSnapshot = await _db
        .collection('PalletGroups')
        .doc(groupId)
        .get();
    if (!groupSnapshot.exists) {
      return PalletGroupUngroupResolution(
        scannedStockId: normalizedScannedStockId,
        groupId: groupId,
        referencePalletId: '',
        memberPalletIds: const <String>[],
        stockExists: false,
        stockHueco: '',
        isExpedido: false,
        pedidosEncontrados: const <String>[],
      );
    }

    final groupData = groupSnapshot.data() ?? <String, dynamic>{};
    final group = PalletGroup.fromDoc(groupSnapshot.id, groupData);
    final resolvedGroupId = group.groupId.trim().isNotEmpty
        ? group.groupId.trim()
        : groupSnapshot.id;
    final referencePalletId = group.referencePalletId.trim().isNotEmpty
        ? group.referencePalletId.trim()
        : resolvedGroupId;
    final memberPalletIds = group.memberPalletIds.isNotEmpty
        ? group.memberPalletIds
        : <String>[referencePalletId];

    final stockSnapshot = await _db
        .collection('Stock')
        .doc(buildStockDocId(referencePalletId))
        .get();
    final stockExists = stockSnapshot.exists;
    final stockData = stockSnapshot.data() ?? <String, dynamic>{};
    final stockHueco = stockData['HUECO']?.toString().trim() ?? '';
    final pedidosEncontrados = await _findExpedidoPedidos(memberPalletIds);
    final isExpedido = pedidosEncontrados.isNotEmpty;

    return PalletGroupUngroupResolution(
      scannedStockId: normalizedScannedStockId,
      groupId: resolvedGroupId,
      referencePalletId: referencePalletId,
      memberPalletIds: memberPalletIds,
      stockExists: stockExists,
      stockHueco: stockHueco,
      isExpedido: isExpedido,
      pedidosEncontrados: pedidosEncontrados,
      group: group,
    );
  }

  Future<void> ungroup(PalletGroupUngroupResolution resolution) async {
    final pedidosEncontrados = await _findExpedidoPedidos(
      resolution.memberPalletIds,
    );
    if (pedidosEncontrados.isNotEmpty) {
      throw StateError(
        'No se puede desagrupar: el grupo ya fue expedido por CMR',
      );
    }

    final groupRef = _db.collection('PalletGroups').doc(resolution.groupId);
    final stockRef = _db
        .collection('Stock')
        .doc(buildStockDocId(resolution.referencePalletId));
    final memberRefs = resolution.memberPalletIds
        .map((palletId) => _db.collection('PalletGroupMembers').doc(palletId))
        .toList(growable: false);
    final logRef = _db.collection('GroupLogs').doc();
    final user = FirebaseAuth.instance.currentUser;
    final userName = await _loadUserName(user);

    await _db.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final stockSnapshot = await transaction.get(stockRef);
      if (!groupSnapshot.exists) {
        throw StateError('No existe PalletGroups/${resolution.groupId}.');
      }

      final stockData = stockSnapshot.data() ?? <String, dynamic>{};
      final stockHueco = stockData['HUECO']?.toString().trim() ?? '';
      final groupData = groupSnapshot.data() ?? <String, dynamic>{};
      final now = FieldValue.serverTimestamp();
      transaction.set(logRef, <String, dynamic>{
        'action': 'ungroup',
        'groupId': resolution.groupId,
        'referencePalletId': resolution.referencePalletId,
        'memberPalletIds': resolution.memberPalletIds,
        'scannedStockId': resolution.scannedStockId,
        'boxesCount': resolution.group?.boxesCount ?? groupData['boxesCount'],
        'netoTotal': resolution.group?.netoTotal ?? groupData['netoTotal'],
        'brutoTotal': resolution.group?.brutoTotal ?? groupData['brutoTotal'],
        'cajasTotal': resolution.group?.cajasTotal ?? groupData['cajasTotal'],
        'stockDeleted': stockSnapshot.exists,
        'stockHueco': stockHueco,
        'timestamp': now,
        'userId': user?.uid,
        'userEmail': user?.email,
        'userName': userName,
        'group': groupData,
        if (stockSnapshot.exists) 'stock': stockData,
      });
      if (stockSnapshot.exists) {
        transaction.delete(stockRef);
      }
      transaction.delete(groupRef);
      for (final memberRef in memberRefs) {
        transaction.delete(memberRef);
      }
    });
  }

  Future<List<String>> _findExpedidoPedidos(List<String> memberPalletIds) async {
    final pedidoPaletIds = memberPalletIds
        .map(normalizePaletForPedido)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (pedidoPaletIds.isEmpty) {
      return const <String>[];
    }

    final found = <String>{};
    for (final paletId in pedidoPaletIds) {
      for (final field in const <String>['palets', 'Palets']) {
        final snapshot = await _db
            .collection('Pedidos')
            .where(field, arrayContains: paletId)
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (_isPedidoExpedidoPorCmr(data)) {
            found.add(doc.id);
          }
        }
      }
    }
    return found.toList(growable: false)..sort();
  }

  bool _isPedidoExpedidoPorCmr(Map<String, dynamic> data) {
    final estado = (data['Estado'] ?? data['estado'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final type = (data['type'] ?? data['Type'])
            ?.toString()
            .trim()
            .toUpperCase() ??
        '';
    return estado == 'expedido' || type == 'CMR';
  }

  Future<String?> _loadUserName(User? user) async {
    if (user == null) {
      return null;
    }

    try {
      final snapshot = await _db
          .collection('UsuariosAutorizados')
          .doc(user.uid)
          .get();
      return snapshot.data()?['Nombre']?.toString();
    } catch (error) {
      debugPrint('No se pudo cargar el usuario para GroupLogs: $error');
      return null;
    }
  }

  Future<void> closeGroup(PalletGroup group) async {
    if (group.memberPalletIds.isEmpty) {
      throw ArgumentError('El grupo debe contener al menos un QR.');
    }
    if (group.memberPalletIds.length > 6) {
      throw ArgumentError('El grupo no puede superar 6 QR.');
    }
    if (group.memberPalletIds.toSet().length != group.memberPalletIds.length) {
      throw ArgumentError('El grupo contiene QR duplicados.');
    }

    final groupRef = _db.collection('PalletGroups').doc(group.groupId);
    final memberRefs = group.memberPalletIds
        .map((palletId) => _db.collection('PalletGroupMembers').doc(palletId))
        .toList(growable: false);

    await _db.runTransaction((transaction) async {
      for (var i = 0; i < memberRefs.length; i++) {
        final snapshot = await transaction.get(memberRefs[i]);
        if (snapshot.exists) {
          throw PalletGroupConflictException(group.memberPalletIds[i]);
        }
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(
        groupRef,
        group.toFirestore(createdAt: now, updatedAt: now),
      );

      for (var i = 0; i < memberRefs.length; i++) {
        transaction.set(memberRefs[i], <String, dynamic>{
          'groupId': group.groupId,
          'referencePalletId': group.referencePalletId,
          'createdAt': now,
        });
      }
    });
  }
}
