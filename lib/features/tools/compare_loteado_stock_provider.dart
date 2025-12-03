import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaletDiffItem {
  PaletDiffItem({
    required this.origen,
    required this.docId,
    required this.palletNumber,
    required this.caseNumber,
    this.idpalet,
    this.variedad,
    this.confeccion,
    this.marca,
    this.camara,
    this.estanteria,
    this.nivel,
    this.stockCamara,
    this.stockEstanteria,
    this.stockNivel,
    this.hueco,
    required this.neto,
  });

  final String origen; // 'Loteado', 'Stock' o combinaciones
  final String docId;
  final String palletNumber; // docId sin el prefijo inicial
  final int caseNumber; // 1,2,3
  final String? idpalet;
  final String? variedad;
  final String? confeccion;
  final String? marca;
  final String? camara;
  final String? estanteria;
  final String? nivel;
  final String? stockCamara;
  final String? stockEstanteria;
  final String? stockNivel;
  final String? hueco;
  final num neto;
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
    required this.caseNumber,
    required this.origen,
    required this.docId,
    required this.palletNumber,
    this.variedad,
    this.confeccion,
    this.camara,
    this.estanteria,
    this.nivel,
    this.hueco,
  });

  final int caseNumber;
  final String origen; // 'Loteado' o 'Stock'
  final String docId;
  final String palletNumber;
  final String? variedad;
  final String? confeccion;
  final String? camara;
  final String? estanteria;
  final String? nivel;
  final String? hueco;
}

class CompareLoteadoStockResult {
  CompareLoteadoStockResult({
    required this.case1LoteadoSinStock,
    required this.case2LoteadoMasLibre,
    required this.case3StockOcupadoSinLoteado,
    required this.totalLoteado,
    required this.totalStockOcupado,
    required this.totalNetoLoteado,
    required this.totalNetoStockOcupado,
    required this.variedadOptions,
    required this.camaraOptions,
    required this.marcaOptions,
    required this.diffRows,
  });

  final List<PaletDiffItem> case1LoteadoSinStock;
  final List<PaletDiffItem> case2LoteadoMasLibre;
  final List<PaletDiffItem> case3StockOcupadoSinLoteado;
  final int totalLoteado;
  final int totalStockOcupado;
  final num totalNetoLoteado;
  final num totalNetoStockOcupado;
  final List<String> variedadOptions;
  final List<String> camaraOptions;
  final List<String> marcaOptions;
  final List<DiffRow> diffRows;
}

final compareLoteadoStockProvider =
    FutureProvider<CompareLoteadoStockResult>((ref) async {
  final firestore = FirebaseFirestore.instance;

  final loteadoSnap = await firestore.collection('Loteado').get();
  final stockSnap = await firestore.collection('Stock').get();

  final loteadoDocs = loteadoSnap.docs;
  final stockDocs = stockSnap.docs;

  final loteadoIds = loteadoDocs.map((d) => d.id).toSet();
  final stockIdsAll = stockDocs.map((d) => d.id).toSet();

  final stockLibreDocs =
      stockDocs.where((doc) => _readHueco(doc.data()) == 'Libre').toList();
  final stockOcupadoDocs =
      stockDocs.where((doc) => _readHueco(doc.data()) == 'Ocupado').toList();

  final stockLibreIds = stockLibreDocs.map((d) => d.id).toSet();
  final stockOcupadoIds = stockOcupadoDocs.map((d) => d.id).toSet();

  // Casuísticas
  final case1Ids = loteadoIds.difference(stockIdsAll); // L - S_all
  final case2Ids = loteadoIds.intersection(stockLibreIds); // L ∩ S_libre
  final case3Ids = stockOcupadoIds.difference(loteadoIds); // S_ocup - L

  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
      loteadoById = {
    for (final doc in loteadoDocs) doc.id: doc,
  };
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> stockById = {
    for (final doc in stockDocs) doc.id: doc,
  };

  PaletDiffItem mapToItem({
    required String origen,
    required int caseNumber,
    required QueryDocumentSnapshot<Map<String, dynamic>> primaryDoc,
    QueryDocumentSnapshot<Map<String, dynamic>>? secondaryDoc,
  }) {
    final primaryData = primaryDoc.data();
    final secondaryData = secondaryDoc?.data();

    return PaletDiffItem(
      origen: origen,
      docId: primaryDoc.id,
      palletNumber: _palletNumber(primaryDoc.id),
      caseNumber: caseNumber,
      idpalet: _readString(primaryData, ['idpalet', 'IDPALET', 'idPalet']) ??
          _palletNumber(primaryDoc.id),
      variedad: _readString(primaryData, ['VARIEDAD', 'variedad']),
      confeccion: _readString(primaryData, ['CONFECCION', 'confeccion']),
      marca: _readString(primaryData, ['MARCA', 'marca']),
      camara: _readString(primaryData, ['CAMARA', 'idcamara', 'camara']),
      estanteria:
          _readString(primaryData, ['ESTANTERIA', 'estanteria', 'pasillo']),
      nivel: _readString(primaryData, ['NIVEL', 'nivel', 'POSICION', 'posicion']),
      stockCamara:
          _readString(secondaryData, ['CAMARA', 'idcamara', 'camara']),
      stockEstanteria: _readString(
          secondaryData, ['ESTANTERIA', 'estanteria', 'pasillo']),
      stockNivel: _readString(
          secondaryData, ['NIVEL', 'nivel', 'POSICION', 'posicion']),
      hueco: _readHueco(secondaryData ?? primaryData),
      neto: _readNetoFromDoc(primaryDoc, esStock: origen == 'Stock'),
    );
  }

  PaletDiffItem? _tryBuildCase2(String id) {
    final loteadoDoc = loteadoById[id];
    final stockDoc = stockById[id];
    if (loteadoDoc == null || stockDoc == null) return null;
    return mapToItem(
      origen: 'Loteado+Stock',
      caseNumber: 2,
      primaryDoc: loteadoDoc,
      secondaryDoc: stockDoc,
    );
  }

  final case1Items = case1Ids
      .map((id) => loteadoById[id])
      .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
      .map(
        (doc) => mapToItem(
          origen: 'Loteado',
          caseNumber: 1,
          primaryDoc: doc,
        ),
      )
      .toList()
    ..sort((a, b) => a.palletNumber.compareTo(b.palletNumber));

  final case2Items = case2Ids
      .map(_tryBuildCase2)
      .whereType<PaletDiffItem>()
      .toList()
    ..sort((a, b) => a.palletNumber.compareTo(b.palletNumber));

  final case3Items = case3Ids
      .map((id) => stockById[id])
      .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
      .map(
        (doc) => mapToItem(
          origen: 'Stock',
          caseNumber: 3,
          primaryDoc: doc,
        ),
      )
      .toList()
    ..sort((a, b) => a.palletNumber.compareTo(b.palletNumber));

  List<String> _buildOptions(Iterable<String?> values) {
    final set = values
        .where((v) => v != null && v.trim().isNotEmpty)
        .map((v) => v!.trim())
        .toSet();
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  final variedadOptions = _buildOptions(
    case1Items
        .map((e) => e.variedad)
        .followedBy(case2Items.map((e) => e.variedad))
        .followedBy(case3Items.map((e) => e.variedad)),
  );

  final camaraOptions = _buildOptions(
    case1Items
        .expand<String?>((e) => [e.camara])
        .followedBy(case2Items.expand<String?>((e) => [e.camara, e.stockCamara]))
        .followedBy(case3Items.expand<String?>((e) => [e.camara, e.stockCamara])),
  );

  final marcaOptions = _buildOptions(
    case1Items
        .map((e) => e.marca)
        .followedBy(case2Items.map((e) => e.marca))
        .followedBy(case3Items.map((e) => e.marca)),
  );

  num _totalNetoFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool esStock,
  }) =>
      docs.fold<num>(0, (acc, doc) => acc + _readNetoFromDoc(doc, esStock: esStock));

  String? _camaraForRow(PaletDiffItem item) => item.camara ?? item.stockCamara;
  String? _estanteriaForRow(PaletDiffItem item) =>
      item.estanteria ?? item.stockEstanteria;
  String? _nivelForRow(PaletDiffItem item) => item.nivel ?? item.stockNivel;

  final diffRows = <DiffRow>[
    ...case1Items.map(
      (item) => DiffRow(
        caseNumber: item.caseNumber,
        origen: item.origen,
        docId: item.docId,
        palletNumber: item.palletNumber,
        variedad: item.variedad,
        confeccion: item.confeccion,
        camara: _camaraForRow(item),
        estanteria: _estanteriaForRow(item),
        nivel: _nivelForRow(item),
        hueco: item.hueco,
      ),
    ),
    ...case2Items.map(
      (item) => DiffRow(
        caseNumber: item.caseNumber,
        origen: item.origen,
        docId: item.docId,
        palletNumber: item.palletNumber,
        variedad: item.variedad,
        confeccion: item.confeccion,
        camara: _camaraForRow(item),
        estanteria: _estanteriaForRow(item),
        nivel: _nivelForRow(item),
        hueco: item.hueco,
      ),
    ),
    ...case3Items.map(
      (item) => DiffRow(
        caseNumber: item.caseNumber,
        origen: item.origen,
        docId: item.docId,
        palletNumber: item.palletNumber,
        variedad: item.variedad,
        confeccion: item.confeccion,
        camara: _camaraForRow(item),
        estanteria: _estanteriaForRow(item),
        nivel: _nivelForRow(item),
        hueco: item.hueco,
      ),
    ),
  ];

  return CompareLoteadoStockResult(
    case1LoteadoSinStock: case1Items,
    case2LoteadoMasLibre: case2Items,
    case3StockOcupadoSinLoteado: case3Items,
    totalLoteado: loteadoDocs.length,
    totalStockOcupado: stockOcupadoDocs.length,
    totalNetoLoteado: _totalNetoFromDocs(loteadoDocs, esStock: false),
    totalNetoStockOcupado:
        _totalNetoFromDocs(stockOcupadoDocs, esStock: true),
    variedadOptions: variedadOptions,
    camaraOptions: camaraOptions,
    marcaOptions: marcaOptions,
    diffRows: diffRows,
  );
});

Map<String, PaletDiffGroup> agruparPorCampos(List<PaletDiffItem> items) {
  final Map<String, PaletDiffGroup> grupos = {};

  for (final item in items) {
    final v = item.variedad ?? 'Sin variedad';
    final c = item.confeccion ?? 'Sin confección';
    final cam = item.camara ?? item.stockCamara ?? 'Sin cámara';
    final est = item.estanteria ?? item.stockEstanteria ?? 'Sin estantería';
    final n = item.nivel ?? item.stockNivel ?? 'Sin nivel';

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

String _palletNumber(String docId) =>
    docId.length > 1 ? docId.substring(1) : docId;

String? _readString(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return null;
  for (final key in keys) {
    if (data.containsKey(key)) {
      final value = data[key];
      if (value == null) return null;
      return value.toString();
    }
  }
  return null;
}

String? _readHueco(Map<String, dynamic>? data) {
  final raw = _readString(data, ['Hueco', 'HUECO', 'hueco']);
  if (raw == null) return null;
  return raw.trim();
}

num _readNetoFromDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc, {
  required bool esStock,
}) {
  final data = doc.data();
  if (esStock) {
    final v = data['NETO'];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  } else {
    final v = data['neto'];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }
}
