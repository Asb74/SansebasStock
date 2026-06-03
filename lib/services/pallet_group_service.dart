import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.stockIsAvailable,
    this.group,
  });

  final String scannedStockId;
  final String groupId;
  final String referencePalletId;
  final List<String> memberPalletIds;
  final bool stockExists;
  final bool stockIsAvailable;
  final PalletGroup? group;

  bool get isGrouped => group != null && groupId.isNotEmpty;
  bool get canUngroup => isGrouped && stockExists && stockIsAvailable;
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
        stockIsAvailable: false,
      );
    }

    var groupId = '';
    DocumentSnapshot<Map<String, dynamic>>? groupSnapshot;

    final memberSnapshot = await _db
        .collection('PalletGroupMembers')
        .doc(normalizedScannedStockId)
        .get();
    if (memberSnapshot.exists) {
      final memberData = memberSnapshot.data() ?? <String, dynamic>{};
      groupId = memberData['groupId']?.toString().trim() ?? '';
      if (groupId.isEmpty) {
        groupId = memberData['referencePalletId']?.toString().trim() ?? '';
      }
      if (groupId.isNotEmpty) {
        groupSnapshot = await _db.collection('PalletGroups').doc(groupId).get();
      }
    }

    if (groupSnapshot == null || !groupSnapshot.exists) {
      final directGroupSnapshot = await _db
          .collection('PalletGroups')
          .doc(normalizedScannedStockId)
          .get();
      if (directGroupSnapshot.exists) {
        groupId = normalizedScannedStockId;
        groupSnapshot = directGroupSnapshot;
      }
    }

    if (groupSnapshot == null || !groupSnapshot.exists) {
      return PalletGroupUngroupResolution(
        scannedStockId: normalizedScannedStockId,
        groupId: groupId,
        referencePalletId: '',
        memberPalletIds: const <String>[],
        stockExists: false,
        stockIsAvailable: false,
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
    final hueco = stockData['HUECO']?.toString().trim().toLowerCase() ?? '';

    return PalletGroupUngroupResolution(
      scannedStockId: normalizedScannedStockId,
      groupId: resolvedGroupId,
      referencePalletId: referencePalletId,
      memberPalletIds: memberPalletIds,
      stockExists: stockExists,
      stockIsAvailable: stockExists && hueco != 'libre',
      group: group,
    );
  }

  Future<void> ungroup(PalletGroupUngroupResolution resolution) async {
    if (!resolution.canUngroup) {
      throw StateError(
        'El grupo no está actualmente en stock o ya fue expedido.',
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

    await _db.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final stockSnapshot = await transaction.get(stockRef);
      if (!groupSnapshot.exists || !stockSnapshot.exists) {
        throw StateError(
          'El grupo no está actualmente en stock o ya fue expedido.',
        );
      }

      final stockData = stockSnapshot.data() ?? <String, dynamic>{};
      final hueco = stockData['HUECO']?.toString().trim().toLowerCase() ?? '';
      if (hueco == 'libre') {
        throw StateError(
          'El grupo no está actualmente en stock o ya fue expedido.',
        );
      }

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
        'createdAt': now,
        'group': groupData,
        'stock': stockData,
      });
      transaction.delete(stockRef);
      transaction.delete(groupRef);
      for (final memberRef in memberRefs) {
        transaction.delete(memberRef);
      }
    });
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
