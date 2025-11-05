import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_service.dart';
import '../models/palet_filters.dart';

class SavedPaletView {
  SavedPaletView({
    required this.id,
    required this.name,
    required this.filters,
    this.updatedAt,
  });

  final String id;
  final String name;
  final PaletFilters filters;
  final DateTime? updatedAt;
}

class PaletViewsRepository {
  PaletViewsRepository(this.ref)
      : _firestore = FirebaseFirestore.instance;

  final Ref ref;
  final FirebaseFirestore _firestore;

  AppUser? get _currentUser => ref.read(currentUserProvider);

  CollectionReference<Map<String, dynamic>>? get _viewsCollection {
    final user = _currentUser;
    if (user == null) return null;
    return _firestore
        .collection('UsuariosAutorizados')
        .doc(user.id)
        .collection('Vistas');
  }

  Future<String> saveView(String name, PaletFilters filters) async {
    final userCollection = _viewsCollection;
    final data = <String, dynamic>{
      'name': name,
      'filters': filters.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (userCollection != null) {
      final doc = await userCollection.add(data);
      return doc.id;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final entry = {
      'id': id,
      'name': name,
      'filters': filters.toJson(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    views.add(jsonEncode(entry));
    await prefs.setStringList(_prefsKey, views);
    return id;
  }

  Future<void> renameView(String id, String newName) async {
    final userCollection = _viewsCollection;
    if (userCollection != null) {
      await userCollection.doc(id).update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final updated = <String>[];
    for (final item in views) {
      final map = jsonDecode(item) as Map<String, dynamic>;
      if (map['id'] == id) {
        map['name'] = newName;
        map['updatedAt'] = DateTime.now().toIso8601String();
      }
      updated.add(jsonEncode(map));
    }
    await prefs.setStringList(_prefsKey, updated);
  }

  Future<void> deleteView(String id) async {
    final userCollection = _viewsCollection;
    if (userCollection != null) {
      await userCollection.doc(id).delete();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    views.removeWhere((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return map['id'] == id;
    });
    await prefs.setStringList(_prefsKey, views);
  }

  Future<PaletFilters?> loadView(String id) async {
    final userCollection = _viewsCollection;
    if (userCollection != null) {
      final doc = await userCollection.doc(id).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final filters = data['filters'];
      if (filters is Map<String, dynamic>) {
        return PaletFilters.fromJson(filters);
      }
      if (filters is Map) {
        return PaletFilters.fromJson(filters.cast<String, dynamic>());
      }
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    for (final entry in views) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      if (map['id'] == id) {
        final filters = map['filters'];
        if (filters is Map<String, dynamic>) {
          return PaletFilters.fromJson(filters);
        }
        if (filters is Map) {
          return PaletFilters.fromJson(filters.cast<String, dynamic>());
        }
      }
    }
    return null;
  }

  Future<List<SavedPaletView>> listViews() async {
    final userCollection = _viewsCollection;
    if (userCollection != null) {
      final snapshot = await userCollection.orderBy('name').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final filters = data['filters'];
        PaletFilters parsedFilters;
        if (filters is Map<String, dynamic>) {
          parsedFilters = PaletFilters.fromJson(filters);
        } else if (filters is Map) {
          parsedFilters = PaletFilters.fromJson(filters.cast<String, dynamic>());
        } else {
          parsedFilters = const PaletFilters();
        }
        DateTime? updatedAt;
        final ts = data['updatedAt'];
        if (ts is Timestamp) {
          updatedAt = ts.toDate();
        } else if (ts is String) {
          updatedAt = DateTime.tryParse(ts);
        }
        return SavedPaletView(
          id: doc.id,
          name: data['name']?.toString() ?? 'Sin nombre',
          filters: parsedFilters,
          updatedAt: updatedAt,
        );
      }).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final parsedViews = views.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      DateTime? updatedAt;
      final rawDate = map['updatedAt'];
      if (rawDate is String) {
        updatedAt = DateTime.tryParse(rawDate);
      }
      final filters = map['filters'];
      PaletFilters parsedFilters;
      if (filters is Map<String, dynamic>) {
        parsedFilters = PaletFilters.fromJson(filters);
      } else if (filters is Map) {
        parsedFilters = PaletFilters.fromJson(filters.cast<String, dynamic>());
      } else {
        parsedFilters = const PaletFilters();
      }
      return SavedPaletView(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Sin nombre',
        filters: parsedFilters,
        updatedAt: updatedAt,
      );
    }).toList();

    parsedViews.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return parsedViews;
  }

  static const String _prefsKey = 'palet_views';
}

final paletViewsRepositoryProvider = Provider<PaletViewsRepository>((ref) {
  ref.watch(currentUserProvider);
  return PaletViewsRepository(ref);
});

final savedPaletViewsProvider =
    FutureProvider<List<SavedPaletView>>((ref) async {
  return ref.watch(paletViewsRepositoryProvider).listViews();
});
