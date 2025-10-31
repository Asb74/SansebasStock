import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Abstraction layer that allows the [CatalogService] logic to be tested without
/// depending on Firestore, while still providing a concrete implementation that
/// talks to the database in production code.
abstract class CatalogDataSource {
  Future<List<Map<String, dynamic>>> obtenerConfecciones();

  Future<List<Map<String, dynamic>>> obtenerCalibres(String cultivo);

  Future<Map<String, dynamic>?> obtenerPedido(String idPedido);

  Future<void> guardarPedido(String idPedido, Map<String, dynamic> data);
}

/// Firestore powered implementation of [CatalogDataSource].
class FirestoreCatalogDataSource implements CatalogDataSource {
  FirestoreCatalogDataSource({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<List<Map<String, dynamic>>> obtenerConfecciones() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _db.collection('MConfecciones').get();
    return snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      return doc.data();
    }).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerCalibres(String cultivo) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
        .collection('MCalibre')
        .where('CULTIVO', isEqualTo: cultivo)
        .get();
    return snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      return doc.data();
    }).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>?> obtenerPedido(String idPedido) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _db.collection('DPrecioO').doc(idPedido).get();
    if (!snapshot.exists) {
      return null;
    }
    final Map<String, dynamic>? data = snapshot.data();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  @override
  Future<void> guardarPedido(String idPedido, Map<String, dynamic> data) {
    return _db
        .collection('DPrecioO')
        .doc(idPedido)
        .set(data, SetOptions(merge: true));
  }
}

/// Service that mimics the behaviour of the legacy Visual Basic form load
/// routine. It exposes helpers to obtain the available groups, the calibres
/// for the currently selected crop and to ensure that an order document exists
/// in Firestore.
class CatalogService {
  CatalogService({CatalogDataSource? dataSource})
      : _dataSource = dataSource ?? FirestoreCatalogDataSource();

  final CatalogDataSource _dataSource;

  /// Returns the list of available groups (``GRUPO`` field in
  /// `MConfecciones`).
  ///
  /// The original implementation executed the following SQL query:
  ///
  /// ```sql
  /// SELECT GRUPO
  /// FROM MConfecciones
  /// WHERE GRUPO IS NOT NULL
  /// GROUP BY GRUPO;
  /// ```
  ///
  /// Firestore does not support `GROUP BY`, therefore the method retrieves the
  /// whole collection and performs the distinct filtering client side. Empty
  /// or null values are ignored and the resulting list is sorted alphabetically
  /// to provide deterministic ordering in the UI.
  Future<List<String>> obtenerGrupos() async {
    final List<Map<String, dynamic>> rows =
        await _dataSource.obtenerConfecciones();
    return _filtrarValores(rows, 'GRUPO');
  }

  /// Returns the available calibres for the supplied crop (``CULTIVO`` field
  /// in the `MCalibre` collection).
  ///
  /// The Visual Basic form executed the following SQL statement:
  ///
  /// ```sql
  /// SELECT CalibreU
  /// FROM MCalibre
  /// WHERE CULTIVO = '{cultivo}'
  /// GROUP BY CalibreU;
  /// ```
  ///
  /// Again, Firestore lacks aggregation queries, so we fetch the filtered
  /// documents and deduplicate them on the client. The resulting list is sorted
  /// alphabetically.
  Future<List<String>> obtenerCalibres(String cultivo) async {
    final List<Map<String, dynamic>> rows =
        await _dataSource.obtenerCalibres(cultivo);
    return _filtrarValores(rows, 'CalibreU');
  }

  /// Ensures that a document exists within the `DPrecioO` collection for the
  /// provided [idPedido]. If it does not exist, the document is created with a
  /// single ``IdPedido`` field that mirrors the behaviour of the legacy DAO
  /// code that inserted a new row when the query returned no records. The
  /// resulting map contains at least the ``IdPedido`` entry and any additional
  /// persisted information.
  Future<Map<String, dynamic>> asegurarPedido(String idPedido) async {
    final Map<String, dynamic>? existing =
        await _dataSource.obtenerPedido(idPedido);
    if (existing != null) {
      return existing;
    }

    await _dataSource.guardarPedido(idPedido, <String, dynamic>{
      'IdPedido': idPedido,
    });

    return (await _dataSource.obtenerPedido(idPedido)) ??
        <String, dynamic>{'IdPedido': idPedido};
  }

  @visibleForTesting
  List<String> filtrarValoresDebug(
    List<Map<String, dynamic>> rows,
    String fieldName,
  ) =>
      _filtrarValores(rows, fieldName);

  List<String> _filtrarValores(
    List<Map<String, dynamic>> rows,
    String fieldName,
  ) {
    final Set<String> values = <String>{};
    for (final Map<String, dynamic> row in rows) {
      final String? value = _cleanString(row[fieldName]);
      if (value != null) {
        values.add(value);
      }
    }

    final List<String> ordered = values.toList()..sort();
    return ordered;
  }

  String? _cleanString(dynamic value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.toString().trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
