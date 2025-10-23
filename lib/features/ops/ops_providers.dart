// lib/features/ops/ops_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sansebas_stock/services/stock_service.dart';

/// Mensaje de error que se usa cuando el servicio requiere ubicación previa
const String ubicacionRequeridaMessage =
    'Primero escanea la ubicación (CÁMARA/ESTANTERÍA/NIVEL).';

/// Modelo sencillo para la ubicación escaneada
class Ubicacion {
  final String camara;
  final String estanteria;
  final int nivel;

  const Ubicacion({
    required this.camara,
    required this.estanteria,
    required this.nivel,
  });

  Map<String, dynamic> toMap() => {
        'CAMARA': camara,
        'ESTANTERIA': estanteria,
        'NIVEL': nivel,
      };

  @override
  String toString() => 'CAMARA=$camara ESTANTERIA=$estanteria NIVEL=$nivel';
}

/// Estado con la ubicación pendiente (se llena al leer QR de cámara)
final ubicacionPendienteProvider = StateProvider<Ubicacion?>((_) => null);

/// Proveedor del servicio de stock
final stockServiceProvider = Provider<StockService>((ref) {
  // Si StockService no tiene constructor con args, deja así:
  return StockService();
});
