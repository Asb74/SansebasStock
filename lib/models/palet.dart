import 'package:equatable/equatable.dart';

/// Modelo inmutable que representa un palet almacenado en Firestore.
class Palet extends Equatable {
  const Palet({
    required this.id,
    required this.codigo,
    required this.camara,
    required this.estanteria,
    required this.hueco,
    required this.cultivo,
    required this.variedad,
    required this.calibre,
    required this.marca,
    required this.neto,
    required this.nivel,
    required this.linea,
    required this.posicion,
    this.cajas,
    this.categoria,
    this.confeccion,
    this.pedido,
    this.vida,
    this.rawData = const {},
  });

  final String id;
  final String codigo;
  final String camara;
  final String estanteria;
  final String hueco;
  final String cultivo;
  final String variedad;
  final String calibre;
  final String marca;
  final int neto;
  final int nivel;
  final int linea;
  final int posicion;
  final int? cajas;
  final String? categoria;
  final String? confeccion;
  final String? pedido;
  final String? vida;
  final Map<String, dynamic> rawData;

  bool get estaOcupado => hueco.toLowerCase() == 'ocupado';

  /// Crea una instancia de [Palet] a partir de un documento de Firestore.
  factory Palet.fromDoc(String id, Map<String, dynamic> data) {
    int _asInt(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String _asString(String key) {
      final raw = data[key];
      if (raw == null) {
        return '';
      }
      if (raw is String) {
        return raw.trim();
      }
      return raw.toString();
    }

    return Palet(
      id: id,
      codigo: _asString('P').isNotEmpty ? _asString('P') : id,
      camara: _asString('CAMARA').padLeft(2, '0'),
      estanteria: _asString('ESTANTERIA').padLeft(2, '0'),
      hueco: _asString('HUECO').isEmpty ? 'Libre' : _asString('HUECO'),
      cultivo: _asString('CULTIVO'),
      variedad: _asString('VARIEDAD'),
      calibre: _asString('CALIBRE'),
      marca: _asString('MARCA'),
      neto: _asInt(data['NETO']),
      nivel: _asInt(data['NIVEL']),
      linea: _asInt(data['LINEA']),
      posicion: _asInt(data['POSICION']),
      cajas: _asInt(data['CAJAS']),
      categoria: _asString('CATEGORIA'),
      confeccion: _asString('CONFECCION'),
      pedido: _asString('PEDIDO'),
      vida: _asString('VIDA'),
      rawData: Map<String, dynamic>.unmodifiable(data),
    );
  }

  Palet copyWith({
    String? id,
    String? codigo,
    String? camara,
    String? estanteria,
    String? hueco,
    String? cultivo,
    String? variedad,
    String? calibre,
    String? marca,
    int? neto,
    int? nivel,
    int? linea,
    int? posicion,
    int? cajas,
    String? categoria,
    String? confeccion,
    String? pedido,
    String? vida,
    Map<String, dynamic>? rawData,
  }) {
    return Palet(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      camara: camara ?? this.camara,
      estanteria: estanteria ?? this.estanteria,
      hueco: hueco ?? this.hueco,
      cultivo: cultivo ?? this.cultivo,
      variedad: variedad ?? this.variedad,
      calibre: calibre ?? this.calibre,
      marca: marca ?? this.marca,
      neto: neto ?? this.neto,
      nivel: nivel ?? this.nivel,
      linea: linea ?? this.linea,
      posicion: posicion ?? this.posicion,
      cajas: cajas ?? this.cajas,
      categoria: categoria ?? this.categoria,
      confeccion: confeccion ?? this.confeccion,
      pedido: pedido ?? this.pedido,
      vida: vida ?? this.vida,
      rawData: rawData ?? this.rawData,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'P': codigo,
      'CAMARA': camara,
      'ESTANTERIA': estanteria,
      'HUECO': hueco,
      'CULTIVO': cultivo,
      'VARIEDAD': variedad,
      'CALIBRE': calibre,
      'MARCA': marca,
      'NETO': neto,
      'NIVEL': nivel,
      'LINEA': linea,
      'POSICION': posicion,
      if (cajas != null) 'CAJAS': cajas,
      if (categoria != null) 'CATEGORIA': categoria,
      if (confeccion != null) 'CONFECCION': confeccion,
      if (pedido != null) 'PEDIDO': pedido,
      if (vida != null) 'VIDA': vida,
    };
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        codigo,
        camara,
        estanteria,
        hueco,
        cultivo,
        variedad,
        calibre,
        marca,
        neto,
        nivel,
        linea,
        posicion,
        cajas,
        categoria,
        confeccion,
        pedido,
        vida,
      ];
}
