import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/palet.dart';
import '../models/palet_filters.dart';

/// Cámara seleccionada en la pantalla de mapa (ej: "01", "02"...)
final mapaCamaraSeleccionadaProvider = StateProvider<String?>((ref) => null);

/// Nivel seleccionado (1, 2, 3...)
final mapaNivelSeleccionadoProvider = StateProvider<int?>((ref) => null);

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

enum _FilterField {
  camara,
  estanteria,
  hueco,
  cultivo,
  variedad,
  calibre,
  marca,
  categoria,
  pedido,
  vida,
  confeccion,
  netoMin,
  netoMax,
}

bool _matchesFilters(
  Palet palet,
  PaletFilters filters, {
  Set<_FilterField> except = const {},
}) {
  bool matches(String? filter, String? value) {
    if (filter == null || filter.isEmpty) return true;
    if (value == null) return false;
    return value == filter;
  }

  if (!except.contains(_FilterField.camara) &&
      !matches(filters.camara, palet.camara)) {
    return false;
  }
  if (!except.contains(_FilterField.estanteria) &&
      !matches(filters.estanteria, palet.estanteria)) {
    return false;
  }
  if (!except.contains(_FilterField.hueco) &&
      !matches(filters.hueco, palet.hueco)) {
    return false;
  }
  if (!except.contains(_FilterField.cultivo) &&
      !matches(filters.cultivo, palet.cultivo)) {
    return false;
  }
  if (!except.contains(_FilterField.variedad) &&
      !matches(filters.variedad, palet.variedad)) {
    return false;
  }
  if (!except.contains(_FilterField.calibre) &&
      !matches(filters.calibre, palet.calibre)) {
    return false;
  }
  if (!except.contains(_FilterField.marca) &&
      !matches(filters.marca, palet.marca)) {
    return false;
  }
  if (!except.contains(_FilterField.categoria) &&
      !matches(filters.categoria, palet.categoria)) {
    return false;
  }
  if (!except.contains(_FilterField.pedido) &&
      !matches(filters.pedido, palet.pedido)) {
    return false;
  }
  if (!except.contains(_FilterField.vida) &&
      !matches(filters.vida, palet.vida)) {
    return false;
  }
  if (!except.contains(_FilterField.confeccion) &&
      !matches(filters.confeccion, palet.confeccion)) {
    return false;
  }

  if (!except.contains(_FilterField.netoMin) &&
      filters.netoMin != null &&
      palet.neto < filters.netoMin!) {
    return false;
  }
  if (!except.contains(_FilterField.netoMax) &&
      filters.netoMax != null &&
      palet.neto > filters.netoMax!) {
    return false;
  }

  return true;
}

/// Aplica los filtros de PaletFilters sobre una lista de Palet en memoria.
List<Palet> _applyFilters(
  List<Palet> palets,
  PaletFilters filters, {
  Set<_FilterField> except = const {},
}) {
  final filtered = palets
      .where((p) => _matchesFilters(p, filters, except: except))
      .toList(growable: false);

  // Mantenemos el mismo orden que antes: CAMARA, ESTANTERIA, NIVEL, POSICION
  filtered.sort((a, b) {
    final c = a.camara.compareTo(b.camara);
    if (c != 0) return c;
    final e = a.estanteria.compareTo(b.estanteria);
    if (e != 0) return e;
    final n = a.nivel.compareTo(b.nivel);
    if (n != 0) return n;
    return a.posicion.compareTo(b.posicion);
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

/// Palets a dibujar en el mapa, filtrados EN MEMORIA a partir del stream base
final paletsMapaProvider = Provider<AsyncValue<List<Palet>>>((ref) {
  final baseAsync = ref.watch(paletsBaseStreamProvider);
  final camara = ref.watch(mapaCamaraSeleccionadaProvider);
  final nivel = ref.watch(mapaNivelSeleccionadoProvider);

  return baseAsync.whenData((palets) {
    return palets.where((p) {
      if (camara != null && camara.isNotEmpty && p.camara != camara) {
        return false;
      }
      if (nivel != null) {
        if (p.nivel != nivel) return false;
      }

      if (p.hueco.toLowerCase() != 'ocupado') return false;

      return true;
    }).toList();
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

Map<String, List<Palet>> groupPaletsByCameraAndRow(List<Palet> palets) {
  final grouped = <String, List<Palet>>{};
  for (final palet in palets) {
    if (!palet.estaOcupado) continue;

    final camera = palet.camara.trim();
    final estanteria = palet.estanteria.trim();
    final key = '$camera|$estanteria';
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

final paletsByCameraAndRowProvider =
    Provider<AsyncValue<Map<String, List<Palet>>>>((ref) {
  final paletsAsync = ref.watch(paletsBaseStreamProvider);
  return paletsAsync.whenData(groupPaletsByCameraAndRow);
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
    required this.categorias,
    required this.pedidos,
    required this.vidas,
    required this.confecciones,
  });

  final List<String> camaras;
  final List<String> estanterias;
  final List<String> huecos;
  final List<String> cultivos;
  final List<String> variedades;
  final List<String> calibres;
  final List<String> marcas;
  final List<String> categorias;
  final List<String> pedidos;
  final List<String> vidas;
  final List<String> confecciones;
}

final paletFilterOptionsProvider = Provider<PaletFilterOptions?>((ref) {
  final baseAsync = ref.watch(paletsBaseStreamProvider);
  final filters = ref.watch(paletFiltersProvider);
  final palets = baseAsync.value;

  if (palets == null) return null;

  final camaras = <String>{};
  final estanterias = <String>{};
  final huecos = <String>{};
  final cultivos = <String>{};
  final variedades = <String>{};
  final calibres = <String>{};
  final marcas = <String>{};
  final categorias = <String>{};
  final pedidos = <String>{};
  final vidas = <String>{};
  final confecciones = <String>{};

  void addValue(String value, Set<String> target) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      target.add(normalized);
    }
  }

  for (final palet in palets) {
    if (_matchesFilters(palet, filters, except: {_FilterField.camara})) {
      addValue(palet.camara, camaras);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.estanteria})) {
      addValue(palet.estanteria, estanterias);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.hueco})) {
      addValue(palet.hueco, huecos);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.cultivo})) {
      addValue(palet.cultivo, cultivos);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.variedad})) {
      addValue(palet.variedad, variedades);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.calibre})) {
      addValue(palet.calibre, calibres);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.marca})) {
      addValue(palet.marca, marcas);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.categoria})) {
      addValue(palet.categoria, categorias);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.pedido})) {
      addValue(palet.pedido, pedidos);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.vida})) {
      addValue(palet.vida, vidas);
    }
    if (_matchesFilters(palet, filters, except: {_FilterField.confeccion})) {
      addValue(palet.confeccion, confecciones);
    }
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
    categorias: sortSet(categorias),
    pedidos: sortSet(pedidos),
    vidas: sortSet(vidas),
    confecciones: sortSet(confecciones),
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
