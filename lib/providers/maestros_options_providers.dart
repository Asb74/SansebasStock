import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MaestrosOptions {
  MaestrosOptions({
    required this.marcas,
    required this.variedades,
    required this.calibres,
    required this.categorias,
  });

  final List<String> marcas;
  final List<String> variedades;
  final List<String> calibres;
  final List<String> categorias;
}

final maestrosOptionsProvider = FutureProvider<MaestrosOptions>((ref) async {
  final db = FirebaseFirestore.instance;

  Future<List<String>> loadCollection(String name, String field) async {
    final snap = await db.collection(name).get();
    final set = <String>{};
    for (final doc in snap.docs) {
      final value = (doc.data()[field] ?? '').toString().trim();
      if (value.isNotEmpty) set.add(value);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // AJUSTA estos campos a los reales de tus colecciones
  final marcas = await loadCollection('MMarca', 'marca');
  final variedades = await loadCollection('MVariedad', 'variedad');
  final calibres = await loadCollection('MCalibre', 'calibre');
  final categorias = await loadCollection('MCategoria', 'categoria');

  return MaestrosOptions(
    marcas: marcas,
    variedades: variedades,
    calibres: calibres,
    categorias: categorias,
  );
});
