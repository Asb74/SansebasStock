import 'package:flutter_test/flutter_test.dart';
import 'package:sansebas_stock/utils/stock_doc_id.dart';

void main() {
  group('buildStockDocId', () {
    test('prefija nivel 1 cuando el palet trae 10 digitos de pedido', () {
      expect(buildStockDocId('2026018836'), '12026018836');
    });

    test('conserva el id de Stock de 11 digitos', () {
      expect(buildStockDocId('12026018836'), '12026018836');
    });
  });
}
