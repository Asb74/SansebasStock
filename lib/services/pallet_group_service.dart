import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pallet_group.dart';

class PalletGroupConflictException implements Exception {
  const PalletGroupConflictException(this.palletId);

  final String palletId;

  @override
  String toString() => 'El QR $palletId ya pertenece a un grupo.';
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
