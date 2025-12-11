import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/commercial_filters.dart';
import '../models/palet.dart';
import 'palets_providers.dart';

enum CommercialColumn {
  camara,
  estanteria,
  nivel,
  posicion,
  cultivo,
  variedad,
  calibre,
  marca,
  categoria,
  pedido,
  vida,
  neto,
  linea,
  confeccion,
  codigo,
}

class CommercialFilterOptions {
  const CommercialFilterOptions({
    this.cultivos = const <String>{},
    this.variedades = const <String>{},
    this.calibres = const <String>{},
    this.categorias = const <String>{},
    this.marcas = const <String>{},
    this.pedidos = const <String>{},
    this.vidaRange,
  });

  final Set<String> cultivos;
  final Set<String> variedades;
  final Set<String> calibres;
  final Set<String> categorias;
  final Set<String> marcas;
  final Set<String> pedidos;
  final DateTimeRange? vidaRange;
}

class CommercialTotals {
  const CommercialTotals({
    required this.totalPalets,
    required this.totalNeto,
    required this.numPedidos,
  });

  final int totalPalets;
  final int totalNeto;
  final int numPedidos;
}

final commercialFiltersProvider =
    StateProvider<CommercialFilters>((ref) => const CommercialFilters());

final commercialColumnsProvider =
    StateProvider<Set<CommercialColumn>>((ref) => {
          CommercialColumn.camara,
          CommercialColumn.estanteria,
          CommercialColumn.nivel,
          CommercialColumn.posicion,
          CommercialColumn.variedad,
          CommercialColumn.calibre,
          CommercialColumn.categoria,
          CommercialColumn.pedido,
          CommercialColumn.neto,
        });

final _commercialPaletsProvider = Provider<AsyncValue<List<Palet>>>((ref) {
  final baseAsync = ref.watch(paletsBaseStreamProvider);
  return baseAsync.whenData(
    (palets) => palets.where((palet) => palet.estaOcupado).toList(),
  );
});

enum _FilterField {
  cultivo,
  variedad,
  calibre,
  categoria,
  marca,
  pedido,
  vida,
}

DateTime? _parseVida(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

bool _matchesCommercialFilters(
  Palet palet,
  CommercialFilters filters, {
  Set<_FilterField> except = const {},
}) {
  bool matchesSet(Set<String> filter, String? value, _FilterField field) {
    if (except.contains(field)) return true;
    if (filter.isEmpty) return true;
    if (value == null || value.isEmpty) return false;
    return filter.contains(value.trim());
  }

  if (!matchesSet(filters.cultivos, palet.cultivo, _FilterField.cultivo)) {
    return false;
  }
  if (!matchesSet(filters.variedades, palet.variedad, _FilterField.variedad)) {
    return false;
  }
  if (!matchesSet(filters.calibres, palet.calibre, _FilterField.calibre)) {
    return false;
  }
  if (!matchesSet(filters.categorias, palet.categoria, _FilterField.categoria)) {
    return false;
  }
  if (!matchesSet(filters.marcas, palet.marca, _FilterField.marca)) {
    return false;
  }
  if (!matchesSet(filters.pedidos, palet.pedido, _FilterField.pedido)) {
    return false;
  }

  if (!except.contains(_FilterField.vida) && filters.vidaRange != null) {
    final vidaDate = _parseVida(palet.vida);
    if (vidaDate == null) return false;
    final start = filters.vidaRange!.start;
    final end = filters.vidaRange!.end;
    if (vidaDate.isBefore(start) || vidaDate.isAfter(end)) {
      return false;
    }
  }

  return true;
}

List<Palet> applyCommercialFilters(
  List<Palet> palets,
  CommercialFilters filters,
) {
  final filtered = palets
      .where((palet) => _matchesCommercialFilters(palet, filters))
      .toList(growable: false);

  filtered.sort((a, b) {
    final camara = a.camara.compareTo(b.camara);
    if (camara != 0) return camara;
    final estanteria = a.estanteria.compareTo(b.estanteria);
    if (estanteria != 0) return estanteria;
    final nivel = a.nivel.compareTo(b.nivel);
    if (nivel != 0) return nivel;
    return a.posicion.compareTo(b.posicion);
  });

  return filtered;
}

CommercialFilterOptions computeCommercialOptions(
  List<Palet> palets,
  CommercialFilters filters,
) {
  final cultivos = <String>{};
  final variedades = <String>{};
  final calibres = <String>{};
  final categorias = <String>{};
  final marcas = <String>{};
  final pedidos = <String>{};
  DateTime? minVida;
  DateTime? maxVida;

  void addValue(String? value, Set<String> target) {
    if (value == null) return;
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      target.add(normalized);
    }
  }

  for (final palet in palets) {
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.cultivo},
    )) {
      addValue(palet.cultivo, cultivos);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.variedad},
    )) {
      addValue(palet.variedad, variedades);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.calibre},
    )) {
      addValue(palet.calibre, calibres);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.categoria},
    )) {
      addValue(palet.categoria, categorias);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.marca},
    )) {
      addValue(palet.marca, marcas);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.pedido},
    )) {
      addValue(palet.pedido, pedidos);
    }
    if (_matchesCommercialFilters(
      palet,
      filters,
      except: {_FilterField.vida},
    )) {
      final vidaDate = _parseVida(palet.vida);
      if (vidaDate != null) {
        minVida = minVida == null ? vidaDate : (vidaDate.isBefore(minVida!) ? vidaDate : minVida);
        maxVida = maxVida == null ? vidaDate : (vidaDate.isAfter(maxVida!) ? vidaDate : maxVida);
      }
    }
  }

  DateTimeRange? vidaRange;
  if (minVida != null && maxVida != null) {
    vidaRange = DateTimeRange(start: minVida!, end: maxVida!);
  }

  List<String> sortSet(Set<String> values) => values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return CommercialFilterOptions(
    cultivos: sortSet(cultivos).toSet(),
    variedades: sortSet(variedades).toSet(),
    calibres: sortSet(calibres).toSet(),
    categorias: sortSet(categorias).toSet(),
    marcas: sortSet(marcas).toSet(),
    pedidos: sortSet(pedidos).toSet(),
    vidaRange: vidaRange,
  );
}

CommercialTotals computeCommercialTotals(List<Palet> palets) {
  final totalPalets = palets.length;
  final totalNeto = palets.fold<int>(0, (acc, palet) => acc + palet.neto);
  final pedidos = palets.map((p) => p.pedido?.trim()).whereType<String>().toSet();
  return CommercialTotals(
    totalPalets: totalPalets,
    totalNeto: totalNeto,
    numPedidos: pedidos.length,
  );
}

final filteredCommercialPaletsProvider =
    Provider<AsyncValue<List<Palet>>>((ref) {
  final baseAsync = ref.watch(_commercialPaletsProvider);
  final filters = ref.watch(commercialFiltersProvider);
  return baseAsync.whenData((palets) => applyCommercialFilters(palets, filters));
});

final commercialFilterOptionsProvider =
    Provider<CommercialFilterOptions?>((ref) {
  final baseAsync = ref.watch(_commercialPaletsProvider);
  final filters = ref.watch(commercialFiltersProvider);
  final palets = baseAsync.value;
  if (palets == null) return null;
  return computeCommercialOptions(palets, filters);
});

final commercialTotalsProvider = Provider<AsyncValue<CommercialTotals>>((ref) {
  final paletsAsync = ref.watch(filteredCommercialPaletsProvider);
  return paletsAsync.whenData(computeCommercialTotals);
});
