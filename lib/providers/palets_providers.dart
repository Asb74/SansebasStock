import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/palet.dart';
import '../models/palet_filters.dart';

/// Proveedor de filtros activos seleccionados por el usuario.
final paletFiltersProvider =
    StateProvider<PaletFilters>((ref) => const PaletFilters());

/// Stream base de todos los palets de Stock (sin filtros de usuario).
/// Aquí es donde realmente se hacen las lecturas a Firestore.
/// A partir de este stream, todo lo demás (filtros, totales, agrupados)
/// se hace en memoria.
final paletsBaseStreamProvider = StreamProvider<List<Palet>>((ref) {
  final firestore = FirebaseFirestore.instance;

  final query = firestore
      .collection('Stock')
      .orderBy('CAMARA')
      .orderBy('ESTANTERIA')
      .orderBy('NIVEL')
      .orderBy('POSICION');

  return query.snapshots().map((snapshot) {
    return snapshot.docs
        .map((doc) => Palet.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  });
});

/// Aplica los filtros de PaletFilters sobre una lista de Palet en memoria.
List<Palet> _applyFilters(List<Palet> palets, PaletFilters filters) {
  bool matches(String? filter, String? value) {
    if (filter == null || filter.isEmpty) return true;
    if (value == null) return false;
    return value == filter;
  }

  final filtered = palets.where((p) {
    if (!matches(filters.camara, p.camara)) return false;
    if (!matches(filters.estanteria, p.estanteria)) return false;
    if (!matches(filters.hueco, p.hueco)) return false;
    if (!matches(filters.cultivo, p.cultivo)) return false;
    if (!matches(filters.variedad, p.variedad)) return false;
    if (!matches(filters.calibre, p.calibre)) return false;
    if (!matches(filters.marca, p.marca)) return false;

    if (filters.netoMin != null && p.neto < filters.netoMin!) return false;
    if (filters.netoMax != null && p.neto > filters.netoMax!) return false;

    return true;
  }).toList(growable: false);

  // Mantenemos el mismo orden que antes: CAMARA, ESTANTERIA, NIVEL, POSICION
  filtered.sort((a, b) {
    final c = (a.camara ?? '').compareTo(b.camara ?? '');
    if (c != 0) return c;
    final e = (a.estanteria ?? '').compareTo(b.estanteria ?? '');
    if (e != 0) return e;
    final n = (a.nivel ?? '').compareTo(b.nivel ?? '');
    if (n != 0) return n;
    return (a.posicion ?? '').compareTo(b.posicion ?? '');
  });

  return filtered;
}

/// Lista de palets ya filtrada según los filtros activos, envuelta en AsyncValue.
/// OJO: este provider ya NO habla con Firestore directamente.
/// Sólo escucha al stream base y aplica filtros en memoria.
///
/// Desde fuera, `ref.watch(paletsStreamProvider)` sigue devolviendo
/// AsyncValue<List<Palet>>, igual que antes, así que `StockFilterPage`
/// no necesita cambios.
final paletsStreamProvider = Provider<AsyncValue<List<Palet>>>((ref) {
  final baseAsync = ref.watch(paletsBaseStreamProvider);
  final filters = ref.watch(paletFiltersProvider);

  return baseAsync.whenData((palets) => _applyFilters(palets, filters));
});

/// Totales calculados en cliente para evitar consultas agregadas.
class PaletsTotals {
  const PaletsTotals({required this.totalPalets, required this.totalNeto});

  final int totalPalets;
  final int totalNeto;
}

PaletsTotals computePaletsTotals(List<Palet> palets) {
  final totalPalets = palets.length;
  final totalNeto = palets.fold<int>(0, (acc, palet) => acc + palet.neto);
  return PaletsTotals(totalPalets: totalPalets, totalNeto: totalNeto);
}

Map<String, List<Palet>> groupPaletsPorUbicacion(List<Palet> palets) {
  final grouped = SplayTreeMap<String, List<Palet>>();
  for (final palet in palets) {
    final key = 'C${palet.camara}-E${palet.estanteria}-H${palet.hueco}';
    grouped.putIfAbsent(key, () => <Palet>[]).add(palet);
  }
  return grouped;
}

final paletsTotalsProvider = Provider<AsyncValue<PaletsTotals>>((ref) {
  final paletsAsync = ref.watch(paletsStreamProvider);
  return paletsAsync.whenData(computePaletsTotals);
});

final paletsGroupByUbicacionProvider =
    Provider<AsyncValue<Map<String, List<Palet>>>>((ref) {
  final paletsAsync = ref.watch(paletsStreamProvider);
  return paletsAsync.whenData(groupPaletsPorUbicacion);
});

class PaletFilterOptions {
  PaletFilterOptions({
    required this.camaras,
    required this.estanterias,
    required this.huecos,
    required this.cultivos,
    required this.variedades,
    required this.calibres,
    required this.marcas,
  });

  final List<String> camaras;
  final List<String> estanterias;
  final List<String> huecos;
  final List<String> cultivos;
  final List<String> variedades;
  final List<String> calibres;
  final List<String> marcas;
}

final paletFilterOptionsProvider = Provider<PaletFilterOptions?>((ref) {
  final baseAsync = ref.watch(paletsBaseStreamProvider);
  final filters = ref.watch(paletFiltersProvider);
  final palets = baseAsync.value;

  if (palets == null) return null;

  final filtered = _applyFilters(palets, filters);

  final camaras = <String>{};
  final estanterias = <String>{};
  final huecos = <String>{};
  final cultivos = <String>{};
  final variedades = <String>{};
  final calibres = <String>{};
  final marcas = <String>{};

  void addValue(String value, Set<String> target) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      target.add(normalized);
    }
  }

  for (final palet in filtered) {
    addValue(palet.camara, camaras);
    addValue(palet.estanteria, estanterias);
    addValue(palet.hueco, huecos);
    addValue(palet.cultivo, cultivos);
    addValue(palet.variedad, variedades);
    addValue(palet.calibre, calibres);
    addValue(palet.marca, marcas);
  }

  List<String> sortSet(Set<String> set) => set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return PaletFilterOptions(
    camaras: sortSet(camaras),
    estanterias: sortSet(estanterias),
    huecos: sortSet(huecos),
    cultivos: sortSet(cultivos),
    variedades: sortSet(variedades),
    calibres: sortSet(calibres),
    marcas: sortSet(marcas),
  );
});

/// Información agregada de capacidad por cámara y estantería.
class StorageCapacityInfo {
  StorageCapacityInfo({
    required this.camara,
    required this.capacidadTotal,
    required this.capacidadPorEstanteria,
    required this.estanterias,
    required this.niveles,
    required this.huecosPorEstanteria,
    this.posicionesMax,
  });

  final String camara;
  final int capacidadTotal;
  final double capacidadPorEstanteria;
  final int estanterias;
  final int niveles;
  final int huecosPorEstanteria;
  final int? posicionesMax;
}

final storageByCamaraProvider =
    FutureProvider<Map<String, StorageCapacityInfo>>((ref) async {
  final firestore = FirebaseFirestore.instance;
  final snapshot = await firestore.collection('Storage').get();

  final result = <String, StorageCapacityInfo>{};
  for (final doc in snapshot.docs) {
    final data = doc.data();

    int? _asInt(String key) {
      final raw = data[key];
      if (raw == null) return null;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    final camara = (data['CAMARA'] ?? doc.id).toString();
    final estanterias = _asInt('ESTANTERIAS') ?? 0;
    final niveles = _asInt('NIVELES') ?? 0;
    final huecosPorEstanteria =
        _asInt('HUECOS_POR_ESTANTERIA') ?? _asInt('HUECOS') ?? 0;
    final posicionesMax = _asInt('posicionesMax') ?? _asInt('POSICIONES_MAX');

    int capacidadTotal = estanterias * niveles * huecosPorEstanteria;
    if (posicionesMax != null && posicionesMax > 0) {
      capacidadTotal *= posicionesMax;
    }

    final capacidadPorEstanteria = estanterias > 0
        ? capacidadTotal / estanterias
        : capacidadTotal.toDouble();

    result[camara] = StorageCapacityInfo(
      camara: camara,
      capacidadTotal: capacidadTotal,
      capacidadPorEstanteria: capacidadPorEstanteria,
      estanterias: estanterias,
      niveles: niveles,
      huecosPorEstanteria: huecosPorEstanteria,
      posicionesMax: posicionesMax,
    );
  }

  return result;
});
