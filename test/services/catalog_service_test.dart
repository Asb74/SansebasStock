import 'package:flutter_test/flutter_test.dart';
import 'package:sansebas_stock/services/catalog_service.dart';

void main() {
  group('CatalogService', () {
    test('obtenerGrupos elimina duplicados, nulos y espacios', () async {
      final CatalogService service = CatalogService(
        dataSource: _FakeCatalogDataSource(
          confecciones: <Map<String, dynamic>>[
            <String, dynamic>{'GRUPO': 'A'},
            <String, dynamic>{'GRUPO': 'B'},
            <String, dynamic>{'GRUPO': 'A'},
            <String, dynamic>{'GRUPO': '  C '},
            <String, dynamic>{'GRUPO': ''},
            <String, dynamic>{'GRUPO': null},
          ],
        ),
      );

      expect(await service.obtenerGrupos(), <String>['A', 'B', 'C']);
    });

    test('obtenerCalibres filtra resultados según cultivo', () async {
      final CatalogService service = CatalogService(
        dataSource: _FakeCatalogDataSource(
          calibresPorCultivo: <String, List<Map<String, dynamic>>>{
            'Tomate': <Map<String, dynamic>>[
              <String, dynamic>{'CalibreU': '20'},
              <String, dynamic>{'CalibreU': ' 10'},
              <String, dynamic>{'CalibreU': '20'},
            ],
            'Naranja': <Map<String, dynamic>>[
              <String, dynamic>{'CalibreU': '1'},
            ],
          },
        ),
      );

      expect(await service.obtenerCalibres('Tomate'), <String>['10', '20']);
      expect(await service.obtenerCalibres('Naranja'), <String>['1']);
      expect(await service.obtenerCalibres('Limon'), isEmpty);
    });

    test('asegurarPedido crea el documento cuando no existe', () async {
      final _FakeCatalogDataSource dataSource = _FakeCatalogDataSource();
      final CatalogService service = CatalogService(dataSource: dataSource);

      final Map<String, dynamic> created =
          await service.asegurarPedido('PED-001');

      expect(created, containsPair('IdPedido', 'PED-001'));
      expect(dataSource.pedidos['PED-001'], isNotNull);

      final Map<String, dynamic> existing =
          await service.asegurarPedido('PED-001');

      expect(existing, equals(dataSource.pedidos['PED-001']));
    });
  });
}

class _FakeCatalogDataSource implements CatalogDataSource {
  _FakeCatalogDataSource({
    List<Map<String, dynamic>>? confecciones,
    Map<String, List<Map<String, dynamic>>>? calibresPorCultivo,
    Map<String, Map<String, dynamic>>? pedidos,
  })  : _confecciones =
            List<Map<String, dynamic>>.from(confecciones ?? <Map<String, dynamic>>[]),
        _calibresPorCultivo = Map<String, List<Map<String, dynamic>>>.from(
          calibresPorCultivo ?? <String, List<Map<String, dynamic>>>{},
        ),
        pedidos = pedidos == null
            ? <String, Map<String, dynamic>>{}
            : Map<String, Map<String, dynamic>>.from(pedidos);

  final List<Map<String, dynamic>> _confecciones;
  final Map<String, List<Map<String, dynamic>>> _calibresPorCultivo;
  final Map<String, Map<String, dynamic>> pedidos;

  @override
  Future<List<Map<String, dynamic>>> obtenerConfecciones() async =>
      List<Map<String, dynamic>>.from(_confecciones);

  @override
  Future<List<Map<String, dynamic>>> obtenerCalibres(String cultivo) async {
    final List<Map<String, dynamic>>? rows = _calibresPorCultivo[cultivo];
    return rows == null
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>?> obtenerPedido(String idPedido) async {
    final Map<String, dynamic>? row = pedidos[idPedido];
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<void> guardarPedido(String idPedido, Map<String, dynamic> data) async {
    pedidos[idPedido] = Map<String, dynamic>.from(data);
  }
}
