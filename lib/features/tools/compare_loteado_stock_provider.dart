import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaletDiffItem {
  PaletDiffItem({
    required this.origen,
    required this.docId,
    this.idpalet,
    this.variedad,
    this.confeccion,
    this.camara,
    this.estanteria,
    this.nivel,
  });

  final String origen; // 'Loteado' o 'Stock'
  final String docId;
  final String? idpalet;
  final String? variedad;
  final String? confeccion;
  final String? camara;
  final String? estanteria;
  final String? nivel;
}

class PaletDiffGroup {
  PaletDiffGroup({
    required this.key,
    this.variedad,
    this.confeccion,
    this.camara,
    this.estanteria,
    this.nivel,
    required this.items,
  });

  final String key; // combinación de campos
  final String? variedad;
  final String? confeccion;
  final String? camara;
  final String? estanteria;
  final String? nivel;
  final List<PaletDiffItem> items;
}

class DiffRow {
  DiffRow({
    required this.origen,
    required this.docId,
    this.idpalet,
    this.variedad,
    this.confeccion,
    this.camara,
    this.estanteria,
    this.nivel,
  });

  final String origen; // 'Loteado' o 'Stock'
  final String docId;
  final String? idpalet;
  final String? variedad;
  final String? confeccion;
  final String? camara;
  final String? estanteria;
  final String? nivel;
}

class LoteadoStockDiff {
  LoteadoStockDiff({
    required this.docsEnLoteadoNoStock,
    required this.docsEnStockNoLoteado,
    required this.totalLoteado,
    required this.totalStockOcupado,
    required this.enLoteadoNoStockItems,
    required this.enStockNoLoteadoItems,
    required this.diffRows,
    required this.variedadOptions,
    required this.camaraOptions,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docsEnLoteadoNoStock;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docsEnStockNoLoteado;
  final int totalLoteado;
  final int totalStockOcupado;
  final List<PaletDiffItem> enLoteadoNoStockItems;
  final List<PaletDiffItem> enStockNoLoteadoItems;
  final List<DiffRow> diffRows;
  final List<String> variedadOptions;
  final List<String> camaraOptions;
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

  PaletDiffItem _mapDocToItem(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String origen,
  ) {
    final data = doc.data();
    String? _readString(List<String> keys) {
      for (final key in keys) {
        final value = data[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isEmpty) continue;
        return text;
      }
      return null;
    }

    return PaletDiffItem(
      origen: origen,
      docId: doc.id,
      idpalet: _readString(['idpalet', 'IDPALET', 'idPalet']),
      variedad: _readString(['VARIEDAD', 'variedad']),
      confeccion: _readString(['CONFECCION', 'confeccion']),
      camara: _readString(['CAMARA', 'idcamara', 'camara']),
      estanteria: _readString(['ESTANTERIA', 'estanteria']),
      nivel: _readString(['NIVEL', 'nivel', 'POSICION', 'posicion']),
    );
  }

  final enLoteadoNoStockItems = docsEnLoteadoNoStock
      .map((doc) => _mapDocToItem(doc, 'Loteado'))
      .toList();
  final enStockNoLoteadoItems = docsEnStockNoLoteado
      .map((doc) => _mapDocToItem(doc, 'Stock'))
      .toList();

  final diffRows = <DiffRow>[
    ...enLoteadoNoStockItems.map(
      (item) => DiffRow(
        origen: item.origen,
        docId: item.docId,
        idpalet: item.idpalet,
        variedad: item.variedad,
        confeccion: item.confeccion,
        camara: item.camara,
        estanteria: item.estanteria,
        nivel: item.nivel,
      ),
    ),
    ...enStockNoLoteadoItems.map(
      (item) => DiffRow(
        origen: item.origen,
        docId: item.docId,
        idpalet: item.idpalet,
        variedad: item.variedad,
        confeccion: item.confeccion,
        camara: item.camara,
        estanteria: item.estanteria,
        nivel: item.nivel,
      ),
    ),
  ];

  List<String> _buildOptions(Iterable<String?> values) {
    final set = values
        .where((v) => v != null && v.trim().isNotEmpty)
        .map((v) => v!.trim())
        .toSet()
      ..removeWhere((v) => v.isEmpty);
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  final variedadOptions = _buildOptions(
    enLoteadoNoStockItems.map((e) => e.variedad)
        .followedBy(enStockNoLoteadoItems.map((e) => e.variedad)),
  );
  final camaraOptions = _buildOptions(
    enLoteadoNoStockItems.map((e) => e.camara)
        .followedBy(enStockNoLoteadoItems.map((e) => e.camara)),
  );

  return LoteadoStockDiff(
    docsEnLoteadoNoStock: docsEnLoteadoNoStock,
    docsEnStockNoLoteado: docsEnStockNoLoteado,
    totalLoteado: loteadoSnap.docs.length,
    totalStockOcupado: stockSnap.docs.length,
    enLoteadoNoStockItems: enLoteadoNoStockItems,
    enStockNoLoteadoItems: enStockNoLoteadoItems,
    diffRows: diffRows,
    variedadOptions: variedadOptions,
    camaraOptions: camaraOptions,
  );
});

Map<String, PaletDiffGroup> agruparPorCampos(List<PaletDiffItem> items) {
  final Map<String, PaletDiffGroup> grupos = {};

  for (final item in items) {
    final v = item.variedad ?? 'Sin variedad';
    final c = item.confeccion ?? 'Sin confección';
    final cam = item.camara ?? 'Sin cámara';
    final est = item.estanteria ?? 'Sin estantería';
    final n = item.nivel ?? 'Sin nivel';

    final key = '$v | $c | Cam:$cam | Est:$est | Niv:$n';

    grupos.putIfAbsent(
      key,
      () => PaletDiffGroup(
        key: key,
        variedad: v,
        confeccion: c,
        camara: cam,
        estanteria: est,
        nivel: n,
        items: [],
      ),
    );

    grupos[key]!.items.add(item);
  }

  return grupos;
}

final lastLoteadoSyncProvider = FutureProvider<DateTime?>((ref) async {
  final doc =
      await FirebaseFirestore.instance.collection('SyncStock').doc('Loteado').get();

  final ts = doc.data()?['lastSync'];
  if (ts is Timestamp) return ts.toDate();
  return null;
});

final lastLoteSyncProvider = FutureProvider<DateTime?>((ref) async {
  final doc =
      await FirebaseFirestore.instance.collection('SyncStock').doc('Lote').get();

  final ts = doc.data()?['lastSync'];
  if (ts is Timestamp) return ts.toDate();
  return null;
});
