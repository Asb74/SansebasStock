import 'package:cloud_firestore/cloud_firestore.dart';

import 'commercial_filters.dart';
import '../providers/commercial_providers.dart';

class SavedCommercialView {
  const SavedCommercialView({
    required this.id,
    required this.name,
    required this.filters,
    required this.columns,
    this.updatedAt,
  });

  final String id;
  final String name;
  final CommercialFilters filters;
  final Set<CommercialColumn> columns;
  final DateTime? updatedAt;

  factory SavedCommercialView.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SavedCommercialView(
      id: doc.id,
      name: data['name']?.toString() ?? 'Sin nombre',
      filters: _filtersFrom(data['filters']),
      columns: _columnsFrom(data['columns']),
      updatedAt: _dateFrom(data['updatedAt']),
    );
  }

  factory SavedCommercialView.fromMap(Map<String, dynamic> map) {
    return SavedCommercialView(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Sin nombre',
      filters: _filtersFrom(map['filters']),
      columns: _columnsFrom(map['columns']),
      updatedAt: _dateFrom(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'filters': filters.toJson(),
      'columns': columns.map((c) => c.name).toList(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static CommercialFilters _filtersFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return CommercialFilters.fromJson(raw);
    }
    if (raw is Map) {
      return CommercialFilters.fromJson(raw.cast<String, dynamic>());
    }
    return const CommercialFilters();
  }

  static Set<CommercialColumn> _columnsFrom(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .map((value) => CommercialColumn.values.firstWhere(
                (column) => column.name == value.toString(),
                orElse: () => CommercialColumn.variedad,
              ))
          .toSet();
    }
    return {CommercialColumn.variedad};
  }

  static DateTime? _dateFrom(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
