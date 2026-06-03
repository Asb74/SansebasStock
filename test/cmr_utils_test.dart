import 'package:flutter_test/flutter_test.dart';

import 'package:sansebas_stock/features/cmr/cmr_utils.dart';

void main() {
  group('parseStockPaletIdFromQr', () {
    test('conserva NIVEL para construir el id de Stock de 11 digitos', () {
      expect(
        parseStockPaletIdFromQr('NIVEL=1;P=2026018833'),
        '12026018833',
      );
    });

    test('conserva Q para construir el id de Stock de 11 digitos', () {
      expect(
        parseStockPaletIdFromQr('P=2026018833;Q=1'),
        '12026018833',
      );
    });

    test('devuelve P cuando ya tiene 11 digitos', () {
      expect(
        parseStockPaletIdFromQr('P=12026018833;NIVEL=1'),
        '12026018833',
      );
    });

    test('usa P como fallback cuando no hay NIVEL ni Q', () {
      expect(parseStockPaletIdFromQr('P=2026018833'), '2026018833');
    });
  });
}
