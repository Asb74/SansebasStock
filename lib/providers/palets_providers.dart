import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/palet.dart';
import '../models/palet_filters.dart';

/// Proveedor de filtros activos seleccionados por el usuario.
final paletFiltersProvider =
    StateProvider<PaletFilters>((ref) => const PaletFilters());

/// Stream de palets filtrados según los filtros activos.
final paletsStreamProvider = StreamProvider<List<Palet>>((ref) {
  final filters = ref.watch(paletFiltersProvider);
  final firestore = FirebaseFirestore.instance;

  Query<Map<String, dynamic>> query = firestore.collection('Stock');

  if (filters.camara != null && filters.camara!.isNotEmpty) {
    query = query.where('CAMARA', isEqualTo: filters.camara);
  }
  if (filters.estanteria != null && filters.estanteria!.isNotEmpty) {
    query = query.where('ESTANTERIA', isEqualTo: filters.estanteria);
  }
  if (filters.hueco != null && filters.hueco!.isNotEmpty) {
    query = query.where('HUECO', isEqualTo: filters.hueco);
  }
  if (filters.cultivo != null && filters.cultivo!.isNotEmpty) {
    query = query.where('CULTIVO', isEqualTo: filters.cultivo);
  }
  if (filters.variedad != null && filters.variedad!.isNotEmpty) {
    query = query.where('VARIEDAD', isEqualTo: filters.variedad);
  }
  if (filters.calibre != null && filters.calibre!.isNotEmpty) {
    query = query.where('CALIBRE', isEqualTo: filters.calibre);
  }
  if (filters.marca != null && filters.marca!.isNotEmpty) {
    query = query.where('MARCA', isEqualTo: filters.marca);
  }
  if (filters.netoMin != null) {
    query = query.where('NETO', isGreaterThanOrEqualTo: filters.netoMin);
  }
  if (filters.netoMax != null) {
    query = query.where('NETO', isLessThanOrEqualTo: filters.netoMax);
  }

  query = query
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

/// Valores únicos para poblar los dropdowns de filtros.
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

final paletFilterOptionsProvider =
    FutureProvider<PaletFilterOptions>((ref) async {
  final firestore = FirebaseFirestore.instance;
  final snapshot = await firestore.collection('Stock').limit(500).get();
  final camaras = <String>{};
  final estanterias = <String>{};
  final huecos = <String>{};
  final cultivos = <String>{};
  final variedades = <String>{};
  final calibres = <String>{};
  final marcas = <String>{};

  for (final doc in snapshot.docs) {
    final data = doc.data();
    void addString(String key, Set<String> target) {
      final raw = data[key];
      if (raw == null) return;
      final value = raw.toString().trim();
      if (value.isEmpty) return;
      target.add(value);
    }

    addString('CAMARA', camaras);
    addString('ESTANTERIA', estanterias);
    addString('HUECO', huecos);
    addString('CULTIVO', cultivos);
    addString('VARIEDAD', variedades);
    addString('CALIBRE', calibres);
    addString('MARCA', marcas);
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
