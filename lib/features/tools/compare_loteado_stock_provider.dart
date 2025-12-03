import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoteadoStockDiff {
  LoteadoStockDiff({
    required this.docsEnLoteadoNoStock,
    required this.docsEnStockNoLoteado,
    required this.totalLoteado,
    required this.totalStockOcupado,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docsEnLoteadoNoStock;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docsEnStockNoLoteado;
  final int totalLoteado;
  final int totalStockOcupado;
}

final compareLoteadoStockProvider =
    FutureProvider<LoteadoStockDiff>((ref) async {
  final firestore = FirebaseFirestore.instance;

  final loteadoSnap = await firestore.collection('Loteado').get();
  final stockSnap = await firestore
      .collection('Stock')
      .where('Hueco', isEqualTo: 'Ocupado')
      .get();

  final loteadoIds = loteadoSnap.docs.map((d) => d.id).toSet();
  final stockIds = stockSnap.docs.map((d) => d.id).toSet();

  final enLoteadoNoStock = loteadoIds.difference(stockIds).toList()
    ..sort();
  final enStockNoLoteado = stockIds.difference(loteadoIds).toList()
    ..sort();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<String> ids,
  ) {
    final idSet = ids.toSet();
    final filtered = docs.where((doc) => idSet.contains(doc.id)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return filtered;
  }

  final docsEnLoteadoNoStock = filterDocs(loteadoSnap.docs, enLoteadoNoStock);
  final docsEnStockNoLoteado = filterDocs(stockSnap.docs, enStockNoLoteado);

  return LoteadoStockDiff(
    docsEnLoteadoNoStock: docsEnLoteadoNoStock,
    docsEnStockNoLoteado: docsEnStockNoLoteado,
    totalLoteado: loteadoSnap.docs.length,
    totalStockOcupado: stockSnap.docs.length,
  );
});
