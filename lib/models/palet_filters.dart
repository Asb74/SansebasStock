import 'package:equatable/equatable.dart';

/// Filtros combinables para consultas de palets.
class PaletFilters extends Equatable {
  const PaletFilters({
    this.camara,
    this.estanteria,
    this.hueco,
    this.cultivo,
    this.variedad,
    this.calibre,
    this.marca,
    this.categoria,
    this.pedido,
    this.vida,
    this.confeccion,
    this.netoMin,
    this.netoMax,
  });

  final String? camara;
  final String? estanteria;
  final String? hueco;
  final String? cultivo;
  final String? variedad;
  final String? calibre;
  final String? marca;
  final String? categoria;
  final String? pedido;
  final String? vida;
  final String? confeccion;
  final int? netoMin;
  final int? netoMax;

  PaletFilters copyWith({
    String? camara,
    String? estanteria,
    String? hueco,
    String? cultivo,
    String? variedad,
    String? calibre,
    String? marca,
    String? categoria,
    String? pedido,
    String? vida,
    String? confeccion,
    int? netoMin,
    int? netoMax,
    bool resetCamara = false,
    bool resetEstanteria = false,
    bool resetHueco = false,
    bool resetCultivo = false,
    bool resetVariedad = false,
    bool resetCalibre = false,
    bool resetMarca = false,
    bool resetCategoria = false,
    bool resetPedido = false,
    bool resetVida = false,
    bool resetConfeccion = false,
    bool resetNetoMin = false,
    bool resetNetoMax = false,
  }) {
    return PaletFilters(
      camara: resetCamara ? null : camara ?? this.camara,
      estanteria: resetEstanteria ? null : estanteria ?? this.estanteria,
      hueco: resetHueco ? null : hueco ?? this.hueco,
      cultivo: resetCultivo ? null : cultivo ?? this.cultivo,
      variedad: resetVariedad ? null : variedad ?? this.variedad,
      calibre: resetCalibre ? null : calibre ?? this.calibre,
      marca: resetMarca ? null : marca ?? this.marca,
      categoria: resetCategoria ? null : categoria ?? this.categoria,
      pedido: resetPedido ? null : pedido ?? this.pedido,
      vida: resetVida ? null : vida ?? this.vida,
      confeccion: resetConfeccion ? null : confeccion ?? this.confeccion,
      netoMin: resetNetoMin ? null : netoMin ?? this.netoMin,
      netoMax: resetNetoMax ? null : netoMax ?? this.netoMax,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (camara != null) 'camara': camara,
      if (estanteria != null) 'estanteria': estanteria,
      if (hueco != null) 'hueco': hueco,
      if (cultivo != null) 'cultivo': cultivo,
      if (variedad != null) 'variedad': variedad,
      if (calibre != null) 'calibre': calibre,
      if (marca != null) 'marca': marca,
      if (categoria != null) 'categoria': categoria,
      if (pedido != null) 'pedido': pedido,
      if (vida != null) 'vida': vida,
      if (confeccion != null) 'confeccion': confeccion,
      if (netoMin != null) 'netoMin': netoMin,
      if (netoMax != null) 'netoMax': netoMax,
    };
  }

  factory PaletFilters.fromJson(Map<String, dynamic> json) {
    int? _asInt(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    String? _asString(String key) {
      final raw = json[key];
      if (raw == null) return null;
      final value = raw.toString().trim();
      if (value.isEmpty) return null;
      return value;
    }

    return PaletFilters(
      camara: _asString('camara'),
      estanteria: _asString('estanteria'),
      hueco: _asString('hueco'),
      cultivo: _asString('cultivo'),
      variedad: _asString('variedad'),
      calibre: _asString('calibre'),
      marca: _asString('marca'),
      categoria: _asString('categoria'),
      pedido: _asString('pedido'),
      vida: _asString('vida'),
      confeccion: _asString('confeccion'),
      netoMin: _asInt('netoMin'),
      netoMax: _asInt('netoMax'),
    );
  }

  bool get isEmpty =>
      camara == null &&
      estanteria == null &&
      hueco == null &&
      cultivo == null &&
      variedad == null &&
      calibre == null &&
      marca == null &&
      categoria == null &&
      pedido == null &&
      vida == null &&
      confeccion == null &&
      netoMin == null &&
      netoMax == null;

  @override
  List<Object?> get props => <Object?>[
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
      ];
}
