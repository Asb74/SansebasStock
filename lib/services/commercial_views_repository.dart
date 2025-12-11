import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_service.dart';
import '../models/commercial_filters.dart';
import '../models/saved_commercial_view.dart';
import '../providers/commercial_providers.dart';

class CommercialViewsRepository {
  CommercialViewsRepository(this.ref)
      : _firestore = FirebaseFirestore.instance;

  final Ref ref;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>>? get _viewsCollection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _firestore
        .collection('UsuariosAutorizados')
        .doc(uid)
        .collection('CommercialViews');
  }

  Future<void> saveView(
    String name,
    CommercialFilters filters,
    Set<CommercialColumn> columns,
  ) async {
    final data = <String, dynamic>{
      'name': name,
      'filters': filters.toJson(),
      'columns': columns.map((c) => c.name).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final collection = _viewsCollection;
    if (collection != null) {
      await collection.add(data);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final entry = {
      'id': id,
      ...data,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    views.add(jsonEncode(entry));
    await prefs.setStringList(_prefsKey, views);
  }

  Future<List<SavedCommercialView>> listViews() async {
    final collection = _viewsCollection;
    if (collection != null) {
      final snapshot = await collection.orderBy('name').get();
      return snapshot.docs.map(SavedCommercialView.fromDoc).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final parsed = views
        .map((raw) => SavedCommercialView.fromMap(
            jsonDecode(raw) as Map<String, dynamic>))
        .toList();
    parsed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return parsed;
  }

  Future<CommercialFilters?> loadFilters(String id) async {
    final collection = _viewsCollection;
    if (collection != null) {
      final doc = await collection.doc(id).get();
      if (!doc.exists) return null;
      return SavedCommercialView.fromDoc(doc).filters;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    for (final entry in views) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      if (map['id'] == id) {
        return SavedCommercialView.fromMap(map).filters;
      }
    }
    return null;
  }

  Future<Set<CommercialColumn>?> loadColumns(String id) async {
    final collection = _viewsCollection;
    if (collection != null) {
      final doc = await collection.doc(id).get();
      if (!doc.exists) return null;
      return SavedCommercialView.fromDoc(doc).columns;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    for (final entry in views) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      if (map['id'] == id) {
        return SavedCommercialView.fromMap(map).columns;
      }
    }
    return null;
  }

  Future<void> renameView(String id, String newName) async {
    final collection = _viewsCollection;
    if (collection != null) {
      await collection.doc(id).update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final views = prefs.getStringList(_prefsKey) ?? <String>[];
    final updated = <String>[];
    for (final entry in views) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      if (map['id'] == id) {
        map['name'] = newName;
        map['updatedAt'] = DateTime.now().toIso8601String();
      }
      updated.add(jsonEncode(map));
    }
    await prefs.setStringList(_prefsKey, updated);
  }

  Future<void> deleteView(String id) async {
    final collection = _viewsCollection;
    if (collection != null) {
      await collection.doc(id).delete();
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

  static const String _prefsKey = 'commercial_views';
}

final commercialViewsRepositoryProvider =
    Provider<CommercialViewsRepository>((ref) {
  ref.watch(currentUserProvider);
  return CommercialViewsRepository(ref);
});

final savedCommercialViewsProvider =
    FutureProvider<List<SavedCommercialView>>((ref) async {
  return ref.watch(commercialViewsRepositoryProvider).listViews();
});
