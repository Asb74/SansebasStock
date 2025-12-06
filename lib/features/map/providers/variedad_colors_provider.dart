import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Color? accessColorToFlutter(String? raw) {
  if (raw == null) return null;

  final sanitized = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (sanitized.isEmpty) return null;

  final hex = sanitized.padLeft(8, '0');
  final blue = int.tryParse(hex.substring(hex.length - 6, hex.length - 4), radix: 16);
  final green = int.tryParse(hex.substring(hex.length - 4, hex.length - 2), radix: 16);
  final red = int.tryParse(hex.substring(hex.length - 2), radix: 16);

  if (red == null || green == null || blue == null) return null;

  return Color(
    (0xFF << 24) |
        ((red & 0xFF) << 16) |
        ((green & 0xFF) << 8) |
        (blue & 0xFF),
  );
}

final variedadColorsProvider = FutureProvider<Map<String, Color>>((ref) async {
  final snapshot = await FirebaseFirestore.instance.collection('MVariedad').get();
  final result = <String, Color>{};

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final variedad = (data['variedad'] ?? '').toString().toUpperCase().trim();
    final colorValue = accessColorToFlutter(data['color']?.toString());

    if (variedad.isEmpty || colorValue == null) continue;

    result[variedad] = colorValue;
  }

  debugPrint('MVariedad colors loaded: ${result.length}');

  return result;
});
