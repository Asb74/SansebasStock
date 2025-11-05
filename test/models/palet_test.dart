import 'package:flutter_test/flutter_test.dart';

import 'package:sansebas_stock/models/palet.dart';

void main() {
  group('Palet.fromDoc', () {
    test('convierte correctamente los campos conocidos', () {
      final palet = Palet.fromDoc('doc123', {
        'P': 'PAL-01',
        'CAMARA': '1',
        'ESTANTERIA': '2',
        'HUECO': 'Ocupado',
        'CULTIVO': 'Tomate',
        'VARIEDAD': 'Cherry',
        'CALIBRE': 'M',
        'MARCA': 'SanSebas',
        'NETO': '120',
        'NIVEL': '3',
        'LINEA': 2,
        'POSICION': '5',
      });

      expect(palet.id, 'doc123');
      expect(palet.codigo, 'PAL-01');
      expect(palet.camara, '01');
      expect(palet.estanteria, '02');
      expect(palet.hueco, 'Ocupado');
      expect(palet.cultivo, 'Tomate');
      expect(palet.variedad, 'Cherry');
      expect(palet.calibre, 'M');
      expect(palet.marca, 'SanSebas');
      expect(palet.neto, 120);
      expect(palet.nivel, 3);
      expect(palet.linea, 2);
      expect(palet.posicion, 5);
      expect(palet.estaOcupado, isTrue);
    });

    test('usa valores por defecto cuando faltan campos', () {
      final palet = Palet.fromDoc('abc', {'CAMARA': null});

      expect(palet.codigo, 'abc');
      expect(palet.camara, '00');
      expect(palet.estanteria, '00');
      expect(palet.hueco, 'Libre');
      expect(palet.neto, 0);
    });
  });
}
