import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Grupo de QR de boxes/palets que comparten un mismo palet físico.
class PalletGroup extends Equatable {
  const PalletGroup({
    required this.groupId,
    required this.referencePalletId,
    required this.memberPalletIds,
    required this.boxesCount,
    required this.netoTotal,
    required this.brutoTotal,
    required this.cajasTotal,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String groupId;
  final String referencePalletId;
  final List<String> memberPalletIds;
  final int boxesCount;
  final double netoTotal;
  final double brutoTotal;
  final int cajasTotal;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PalletGroup.fromDoc(String id, Map<String, dynamic> data) {
    DateTime? asDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PalletGroup(
      groupId: data['groupId']?.toString().trim().isNotEmpty == true
          ? data['groupId'].toString().trim()
          : id,
      referencePalletId: data['referencePalletId']?.toString().trim() ?? '',
      memberPalletIds: (data['memberPalletIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      boxesCount: asInt(data['boxesCount']),
      netoTotal: asDouble(data['netoTotal']),
      brutoTotal: asDouble(data['brutoTotal']),
      cajasTotal: asInt(data['cajasTotal']),
      status: data['status']?.toString().trim().isNotEmpty == true
          ? data['status'].toString().trim()
          : 'closed',
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore({Object? createdAt, Object? updatedAt}) {
    return <String, dynamic>{
      'groupId': groupId,
      'referencePalletId': referencePalletId,
      'memberPalletIds': memberPalletIds,
      'boxesCount': boxesCount,
      'netoTotal': netoTotal,
      'brutoTotal': brutoTotal,
      'cajasTotal': cajasTotal,
      'status': status,
      'createdAt': createdAt ?? this.createdAt,
      'updatedAt': updatedAt ?? this.updatedAt,
    };
  }

  @override
  List<Object?> get props => <Object?>[
        groupId,
        referencePalletId,
        memberPalletIds,
        boxesCount,
        netoTotal,
        brutoTotal,
        cajasTotal,
        status,
        createdAt,
        updatedAt,
      ];
}
