import 'package:flutter/material.dart';

class CommercialFilters {
  const CommercialFilters({
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'cultivos': cultivos.toList(),
      'variedades': variedades.toList(),
      'calibres': calibres.toList(),
      'categorias': categorias.toList(),
      'marcas': marcas.toList(),
      'pedidos': pedidos.toList(),
      if (vidaRange != null)
        'vidaRange': {
          'start': vidaRange!.start.toIso8601String(),
          'end': vidaRange!.end.toIso8601String(),
        },
    };
  }

  factory CommercialFilters.fromJson(Map<String, dynamic> json) {
    Set<String> _asSet(String key) {
      final raw = json[key];
      if (raw is Iterable) {
        return raw.map((e) => e.toString()).toSet();
      }
      return <String>{};
    }

    DateTimeRange? _asRange(String key) {
      final raw = json[key];
      if (raw is Map<String, dynamic>) {
        final start = DateTime.tryParse(raw['start']?.toString() ?? '');
        final end = DateTime.tryParse(raw['end']?.toString() ?? '');
        if (start != null && end != null) {
          return DateTimeRange(start: start, end: end);
        }
      }
      if (raw is Map) {
        final start = DateTime.tryParse(raw['start']?.toString() ?? '');
        final end = DateTime.tryParse(raw['end']?.toString() ?? '');
        if (start != null && end != null) {
          return DateTimeRange(start: start, end: end);
        }
      }
      return null;
    }

    return CommercialFilters(
      cultivos: _asSet('cultivos'),
      variedades: _asSet('variedades'),
      calibres: _asSet('calibres'),
      categorias: _asSet('categorias'),
      marcas: _asSet('marcas'),
      pedidos: _asSet('pedidos'),
      vidaRange: _asRange('vidaRange'),
    );
  }

  CommercialFilters copyWith({
    Set<String>? cultivos,
    Set<String>? variedades,
    Set<String>? calibres,
    Set<String>? categorias,
    Set<String>? marcas,
    Set<String>? pedidos,
    DateTimeRange? vidaRange,
  }) {
    return CommercialFilters(
      cultivos: cultivos ?? this.cultivos,
      variedades: variedades ?? this.variedades,
      calibres: calibres ?? this.calibres,
      categorias: categorias ?? this.categorias,
      marcas: marcas ?? this.marcas,
      pedidos: pedidos ?? this.pedidos,
      vidaRange: vidaRange ?? this.vidaRange,
    );
  }

  CommercialFilters clear() => const CommercialFilters();
}
