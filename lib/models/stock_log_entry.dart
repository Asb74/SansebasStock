import 'package:cloud_firestore/cloud_firestore.dart';

class StockLogEntry {
  StockLogEntry({
    required this.id,
    required this.palletId,
    required this.campo,
    this.from,
    this.to,
    this.userId,
    this.userName,
    this.userEmail,
    required this.timestamp,
  });

  final String id;
  final String palletId;
  final String campo;
  final String? from;
  final String? to;
  final String? userId;
  final String? userName;
  final String? userEmail;
  final DateTime timestamp;

  factory StockLogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTimestamp = data['timestamp'];
    final ts = rawTimestamp is Timestamp
        ? rawTimestamp
        : rawTimestamp is int
            ? Timestamp.fromMillisecondsSinceEpoch(rawTimestamp)
            : null;

    return StockLogEntry(
      id: doc.id,
      palletId: (data['palletId'] ?? '').toString(),
      campo: (data['campo'] ?? '').toString(),
      from: data['from']?.toString(),
      to: data['to']?.toString(),
      userId: data['userId']?.toString(),
      userName: data['userName']?.toString(),
      userEmail: data['userEmail']?.toString(),
      timestamp: ts?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
