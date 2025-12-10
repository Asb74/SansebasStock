import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MaestrosOptions {
  MaestrosOptions({
    required this.cultivos,
    required this.marcas,
    required this.variedades,
    required this.calibres,
    required this.categorias,
    required this.variedadesPorCultivo,
    required this.calibresPorCultivo,
    required this.categoriasPorCultivo,
  });

  final List<String> cultivos;
  final List<String> marcas;
  final List<String> variedades;
  final List<String> calibres;
  final List<String> categorias;
  final Map<String, List<String>> variedadesPorCultivo;
  final Map<String, List<String>> calibresPorCultivo;
  final Map<String, List<String>> categoriasPorCultivo;
}

final maestrosOptionsProvider = FutureProvider<MaestrosOptions>((ref) async {
  final db = FirebaseFirestore.instance;

  String? extractCultivo(Map<String, dynamic> data) {
    final value = (data['cultivo'] ?? data['CULTIVO'])?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value.toUpperCase();
  }

  List<String> sortList(Iterable<String> values) {
    final list = values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<List<String>> loadCollection(String name, String field) async {
    final snap = await db.collection(name).get();
    final set = <String>{};
    for (final doc in snap.docs) {
      final value = (doc.data()[field] ?? '').toString().trim();
      if (value.isNotEmpty) set.add(value);
    }
    return sortList(set);
  }

  Future<_CollectionWithCultivo> loadCollectionWithCultivo(
    String name,
    String valueField,
  ) async {
    final snap = await db.collection(name).get();
    final allValues = <String>{};
    final byCultivo = <String, Set<String>>{};
    final cultivos = <String>{};

    for (final doc in snap.docs) {
      final data = doc.data();
      final value = (data[valueField] ?? '').toString().trim();
      if (value.isEmpty) continue;

      allValues.add(value);
      final cultivo = extractCultivo(data);
      if (cultivo != null) {
        cultivos.add(cultivo);
        byCultivo.putIfAbsent(cultivo, () => <String>{});
        byCultivo[cultivo]!.add(value);
      }
    }

    return _CollectionWithCultivo(
      allValues: sortList(allValues),
      byCultivo: {
        for (final entry in byCultivo.entries)
          entry.key: sortList(entry.value),
      },
      cultivos: cultivos,
    );
  }

  // AJUSTA estos campos a los reales de tus colecciones
  final marcas = await loadCollection('MMarca', 'marca');
  final cultivosMaestros = await loadCollection('MCultivo', 'cultivo');
  final variedades = await loadCollectionWithCultivo('MVariedad', 'variedad');
  final calibres = await loadCollectionWithCultivo('MCalibre', 'calibre');
  final categorias = await loadCollectionWithCultivo('MCategoria', 'categoria');

  final allCultivos = <String>{
    ...cultivosMaestros,
    ...variedades.cultivos,
    ...calibres.cultivos,
    ...categorias.cultivos,
  };

  return MaestrosOptions(
    cultivos: sortList(allCultivos),
    marcas: marcas,
    variedades: variedades.allValues,
    calibres: calibres.allValues,
    categorias: categorias.allValues,
    variedadesPorCultivo: variedades.byCultivo,
    calibresPorCultivo: calibres.byCultivo,
    categoriasPorCultivo: categorias.byCultivo,
  );
});

class _CollectionWithCultivo {
  _CollectionWithCultivo({
    required this.allValues,
    required this.byCultivo,
    required this.cultivos,
  });

  final List<String> allValues;
  final Map<String, List<String>> byCultivo;
  final Set<String> cultivos;
}
