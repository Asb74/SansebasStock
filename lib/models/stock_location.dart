class StockLocation {
  const StockLocation({
    required this.camara,
    required this.estanteria,
    required this.nivel,
    this.posicion,
  });

  final String camara;
  final String estanteria;
  final int nivel;
  final int? posicion;

  Map<String, dynamic> toMap() => {
        'CAMARA': camara,
        'ESTANTERIA': estanteria,
        'NIVEL': nivel,
        if (posicion != null) 'POSICION': posicion,
      };
}
