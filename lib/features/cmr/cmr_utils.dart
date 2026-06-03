import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'cmr_models.dart';

String normalizePaletForPedido(String value) {
  final digits = RegExp(r'\d+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .join();
  if (digits.isEmpty) {
    return '';
  }

  final pedidoDigits = RegExp(r'^[123]\d{10}$').hasMatch(digits)
      ? digits.substring(1)
      : digits;
  if (!RegExp(r'^\d{10}$').hasMatch(pedidoDigits)) {
    return '';
  }

  return pedidoDigits;
}

String normalizePaletForStock(String value) {
  final digits = RegExp(r'\d+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .join();
  if (digits.isEmpty) {
    return '';
  }
  if (!RegExp(r'^\d{10,11}$').hasMatch(digits)) {
    return '';
  }
  return digits;
}

String normalizePedidoDocId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'_+'), '_');
}

String normalizarPalet(String raw) {
  return normalizePaletForPedido(raw);
}

String normalizePaletId(String raw) {
  return normalizePaletForPedido(raw);
}

String? _parseNumericQrField(String raw, Iterable<String> keys) {
  final keyPattern = keys.map(RegExp.escape).join('|');
  final match = RegExp(
    '(?:^|[^A-Z0-9_])(?:$keyPattern)\\s*=\\s*([0-9]+)',
    caseSensitive: false,
  ).firstMatch(raw);
  return match?.group(1);
}

String parsePaletFromQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final candidate = _parseNumericQrField(trimmed, const ['P']) ??
      (RegExp(r'^\d+$').hasMatch(trimmed) ? trimmed : null);

  if (candidate == null || candidate.isEmpty) {
    return '';
  }

  return normalizePaletForStock(candidate);
}

({String basePalletId, String level})? _parseEmbeddedLevelInP(String raw) {
  final match = RegExp(
    r'(?:^|[^A-Z0-9_])P\s*=\s*([0-9]{10})\^#([123])(?:$|[^0-9])',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }

  return (basePalletId: match.group(1) ?? '', level: match.group(2) ?? '');
}

String parseStockPaletIdFromQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final embeddedLevel = _parseEmbeddedLevelInP(trimmed);
  if (embeddedLevel != null) {
    return normalizePaletForStock(
      '${embeddedLevel.level}${embeddedLevel.basePalletId}',
    );
  }

  final paletId = parsePaletFromQr(trimmed);
  if (paletId.isEmpty) {
    return '';
  }
  if (RegExp(r'^\d{11}$').hasMatch(paletId)) {
    return paletId;
  }

  final nivel = _parseNumericQrField(trimmed, const ['NIVEL', 'Q']);
  if (RegExp(r'^\d{10}$').hasMatch(paletId) &&
      nivel != null &&
      RegExp(r'^\d$').hasMatch(nivel)) {
    return normalizePaletForStock('$nivel$paletId');
  }

  return paletId;
}

List<String> parsePaletsFromLines(Iterable<String> rawPalets) {
  return rawPalets
      .map(normalizePaletForPedido)
      .where((value) => value.isNotEmpty)
      .toList();
}

class CmrPalletGroupResolution {
  const CmrPalletGroupResolution({
    required this.scannedPalletId,
    required this.effectivePalletId,
    required this.isGrouped,
    required this.groupId,
    required this.referencePalletId,
    required this.memberPalletIds,
    required this.foundByMember,
    required this.foundByGroupId,
  });

  final String scannedPalletId;
  final String effectivePalletId;
  final bool isGrouped;
  final String groupId;
  final String referencePalletId;
  final List<String> memberPalletIds;
  final bool foundByMember;
  final bool foundByGroupId;
}

Future<CmrPalletGroupResolution> resolverGrupoCmr({
  required FirebaseFirestore firestore,
  required String scannedPalletId,
}) async {
  final rawScannedPalletId = scannedPalletId.replaceAll(' ', '').trim();
  final normalizedScannedPalletId =
      normalizePaletForStock(rawScannedPalletId).trim();
  if (normalizedScannedPalletId.isEmpty) {
    return const CmrPalletGroupResolution(
      scannedPalletId: '',
      effectivePalletId: '',
      isGrouped: false,
      groupId: '',
      referencePalletId: '',
      memberPalletIds: <String>[],
      foundByMember: false,
      foundByGroupId: false,
    );
  }

  final palletIdVariants = <String>{
    normalizedScannedPalletId,
    if (rawScannedPalletId.isNotEmpty) rawScannedPalletId,
  };
  var foundByMember = false;
  var foundByGroupId = false;
  DocumentSnapshot<Map<String, dynamic>>? groupSnapshot;
  var groupId = '';

  for (final palletId in palletIdVariants) {
    final memberSnapshot = await firestore
        .collection('PalletGroupMembers')
        .doc(palletId)
        .get();
    if (!memberSnapshot.exists) {
      continue;
    }

    foundByMember = true;
    final memberData = memberSnapshot.data() ?? <String, dynamic>{};
    groupId = memberData['groupId']?.toString().trim() ?? '';
    if (groupId.isEmpty) {
      groupId = normalizePaletForStock(
        memberData['referencePalletId']?.toString() ?? '',
      ).trim();
    }
    if (groupId.isNotEmpty) {
      groupSnapshot = await firestore
          .collection('PalletGroups')
          .doc(groupId)
          .get();
      if (groupSnapshot.exists) {
        break;
      }
    }
  }

  if (groupSnapshot == null || !groupSnapshot.exists) {
    for (final palletId in palletIdVariants) {
      groupSnapshot = await firestore
          .collection('PalletGroups')
          .doc(palletId)
          .get();
      if (groupSnapshot.exists) {
        foundByGroupId = true;
        groupId = palletId;
        break;
      }
    }
  }

  if (groupSnapshot == null || !groupSnapshot.exists) {
    for (final palletId in palletIdVariants) {
      final querySnapshot = await firestore
          .collection('PalletGroups')
          .where('memberPalletIds', arrayContains: palletId)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        groupSnapshot = querySnapshot.docs.first;
        groupId = groupSnapshot.id;
        break;
      }
    }
  }

  if (groupSnapshot == null || !groupSnapshot.exists) {
    return CmrPalletGroupResolution(
      scannedPalletId: normalizedScannedPalletId,
      effectivePalletId: normalizedScannedPalletId,
      isGrouped: false,
      groupId: groupId,
      referencePalletId: '',
      memberPalletIds: <String>[normalizedScannedPalletId],
      foundByMember: foundByMember,
      foundByGroupId: foundByGroupId,
    );
  }

  final groupData = groupSnapshot.data() ?? <String, dynamic>{};
  final resolvedGroupId =
      groupData['groupId']?.toString().trim().isNotEmpty == true
          ? groupData['groupId'].toString().trim()
          : groupSnapshot.id;
  final referencePalletId = normalizePaletForStock(
    groupData['referencePalletId']?.toString() ?? groupSnapshot.id,
  ).trim();
  final memberPalletIds =
      (groupData['memberPalletIds'] as List<dynamic>? ?? const [])
          .map(
            (value) => normalizePaletForStock(value?.toString() ?? '').trim(),
          )
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
  final effectivePalletId = referencePalletId;

  return CmrPalletGroupResolution(
    scannedPalletId: normalizedScannedPalletId,
    effectivePalletId: effectivePalletId,
    isGrouped: true,
    groupId: resolvedGroupId,
    referencePalletId: referencePalletId,
    memberPalletIds: memberPalletIds.isNotEmpty
        ? memberPalletIds
        : <String>[normalizedScannedPalletId],
    foundByMember: foundByMember,
    foundByGroupId: foundByGroupId,
  );
}

Future<bool> paletPerteneceAPedido({
  required FirebaseFirestore firestore,
  required DocumentReference<Map<String, dynamic>> pedidoRef,
  required String paletId,
}) async {
  return paletPerteneceALineasPedido(
    firestore: firestore,
    pedidoRef: pedidoRef,
    paletId: paletId,
  );
}

Future<bool> paletPerteneceALineasPedido({
  required FirebaseFirestore firestore,
  required DocumentReference<Map<String, dynamic>> pedidoRef,
  required String paletId,
}) async {
  final snapshot = await pedidoRef.get();
  if (!snapshot.exists) {
    return false;
  }

  final data = snapshot.data() ?? <String, dynamic>{};
  final rawLineas = data['lineas'] ?? data['Lineas'];
  if (rawLineas is! Iterable) {
    return false;
  }

  for (final item in rawLineas) {
    if (item is! Map) {
      continue;
    }

    final paletRaw = item['Palet']?.toString() ?? '';
    if (paletRaw.trim().isEmpty) {
      continue;
    }

    final palets = paletRaw.split('|');
    for (final palet in palets) {
      final normalized = normalizePaletForPedido(palet);
      if (normalized == normalizePaletForPedido(paletId)) {
        return true;
      }
    }
  }

  return false;
}

Future<Map<String, dynamic>> obtenerDireccionRemitente({
  required FirebaseFirestore firestore,
  required CmrPedido pedido,
}) async {
  final remitente = pedido.remitente.trim();
  final isComercializador = remitente.toUpperCase() == 'COMERCIALIZADOR';

  final collection = isComercializador ? 'MComercial' : 'MCliente_Pais';
  final values = <String>[
    if (isComercializador) pedido.comercializador.trim() else pedido.cliente.trim(),
    pedido.idPedidoCliente.trim(),
  ];

  final fields = isComercializador
      ? const ['Comercializador', 'COMERCIALIZADOR', 'Nombre', 'ID', 'Id']
      : const ['IdCliente', 'IdPedidoCliente', 'ID', 'Id', 'Cliente', 'Nombre'];

  final data = await _findByFields(
    firestore: firestore,
    collection: collection,
    values: values,
    fields: fields,
  );

  if (data == null) {
    debugPrint(
      'No se encontró remitente en $collection para '
      '${isComercializador ? pedido.comercializador : pedido.cliente}.',
    );
    return <String, dynamic>{};
  }

  return data;
}

Future<Map<String, dynamic>?> _findByFields({
  required FirebaseFirestore firestore,
  required String collection,
  required List<String> values,
  required List<String> fields,
}) async {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;

    for (final field in fields) {
      final snapshot = await firestore
          .collection(collection)
          .where(field, isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
    }

    final docSnap = await firestore.collection(collection).doc(trimmed).get();
    if (docSnap.exists) {
      return docSnap.data();
    }
  }

  return null;
}
