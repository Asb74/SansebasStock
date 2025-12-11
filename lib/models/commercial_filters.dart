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
