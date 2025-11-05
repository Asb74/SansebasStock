import 'package:flutter_test/flutter_test.dart';

import 'package:sansebas_stock/models/palet.dart';
import 'package:sansebas_stock/providers/palets_providers.dart';

void main() {
  group('computePaletsTotals', () {
    test('suma palets y neto correctamente', () {
      const palets = <Palet>[
        Palet(
          id: '1',
          codigo: 'P1',
          camara: '01',
          estanteria: '01',
          hueco: 'Ocupado',
          cultivo: 'Tomate',
          variedad: 'Cherry',
          calibre: 'M',
          marca: 'SanSebas',
          neto: 100,
          nivel: 1,
          linea: 1,
          posicion: 1,
        ),
        Palet(
          id: '2',
          codigo: 'P2',
          camara: '01',
          estanteria: '02',
          hueco: 'Libre',
          cultivo: 'Tomate',
          variedad: 'Cherry',
          calibre: 'M',
          marca: 'SanSebas',
          neto: 150,
          nivel: 1,
          linea: 1,
          posicion: 2,
        ),
      ];

      final totals = computePaletsTotals(palets);
      expect(totals.totalPalets, 2);
      expect(totals.totalNeto, 250);
    });
  });

  group('groupPaletsPorUbicacion', () {
    test('agrupa por cámara, estantería y hueco', () {
      const palets = <Palet>[
        Palet(
          id: '1',
          codigo: 'P1',
          camara: '01',
          estanteria: '01',
          hueco: 'Ocupado',
          cultivo: 'Tomate',
          variedad: 'Cherry',
          calibre: 'M',
          marca: 'SanSebas',
          neto: 100,
          nivel: 1,
          linea: 1,
          posicion: 1,
        ),
        Palet(
          id: '2',
          codigo: 'P2',
          camara: '01',
          estanteria: '01',
          hueco: 'Ocupado',
          cultivo: 'Tomate',
          variedad: 'Cherry',
          calibre: 'M',
          marca: 'SanSebas',
          neto: 150,
          nivel: 1,
          linea: 1,
          posicion: 2,
        ),
        Palet(
          id: '3',
          codigo: 'P3',
          camara: '01',
          estanteria: '02',
          hueco: 'Libre',
          cultivo: 'Tomate',
          variedad: 'Cherry',
          calibre: 'M',
          marca: 'SanSebas',
          neto: 80,
          nivel: 1,
          linea: 1,
          posicion: 3,
        ),
      ];

      final grouped = groupPaletsPorUbicacion(palets);
      expect(grouped.length, 2);
      expect(grouped['C01-E01-HOcupado']!.length, 2);
      expect(grouped['C01-E02-HLibre']!.single.codigo, 'P3');
    });
  });
}
