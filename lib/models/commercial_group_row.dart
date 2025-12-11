class CommercialGroupRow {
  const CommercialGroupRow({
    this.cultivo,
    this.variedad,
    this.calibre,
    this.categoria,
    this.marca,
    this.pedido,
    required this.countPalets,
    required this.totalNeto,
  });

  final String? cultivo;
  final String? variedad;
  final String? calibre;
  final String? categoria;
  final String? marca;
  final String? pedido;
  final int countPalets;
  final int totalNeto;
}
