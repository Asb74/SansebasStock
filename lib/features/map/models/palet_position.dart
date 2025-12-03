class PaletPosition {
  PaletPosition({
    required this.stockDocId,
    required this.palletNumber,
    required this.camara,
    required this.estanteria,
    required this.posicion,
    required this.nivel,
  });

  final String stockDocId;
  final String palletNumber;
  final String camara;
  final String estanteria;
  final int posicion;
  final int nivel;
}
