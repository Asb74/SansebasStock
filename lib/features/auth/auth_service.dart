import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final currentUserProvider = StateProvider<AppUser?>((ref) => null);

class AppUser {
  const AppUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.valor,
  });

  final String id;
  final String nombre;
  final String correo;
  final bool valor;
}

class AuthService {
  AuthService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  Future<AppUser> login(
    BuildContext context,
    String correo,
    String password,
  ) async {
    try {
      // Asegurarse de que Firebase está inicializado.
      try {
        Firebase.app();
      } on FirebaseException catch (e, st) {
        if (e.code == 'no-app') {
          dev.log(
            'Firebase no inicializado, inicializando en login...',
            name: 'Auth',
            error: e,
            stackTrace: st,
          );
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } else {
          dev.log(
            'FirebaseException inesperada al comprobar Firebase.app()',
            name: 'Auth',
            error: e,
            stackTrace: st,
          );
          rethrow;
        }
      } catch (e, st) {
        dev.log(
          'Error inesperado al comprobar Firebase.app()',
          name: 'Auth',
          error: e,
          stackTrace: st,
        );
      }

      final trimmedCorreo = correo.trim().toLowerCase();
      final trimmedPassword = password.trim();

      dev.log('SignIn start', name: 'Auth', error: {'email': trimmedCorreo});
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: trimmedCorreo,
        password: trimmedPassword,
      );
      dev.log('SignIn OK', name: 'Auth', error: {'uid': credential.user?.uid});

      final user = credential.user;
      if (user == null) {
        throw const AuthException('No se pudo iniciar sesión.');
      }

      DocumentSnapshot<Map<String, dynamic>>? snapshot;
      try {
        snapshot = await _firestore
            .collection('UsuariosAutorizados')
            .doc(user.uid)
            .get();
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
      }

      if (snapshot == null || !snapshot.exists) {
        snapshot = await _findAuthorizedUserByEmail(trimmedCorreo);
      }

      if (snapshot == null || !snapshot.exists) {
        await _firebaseAuth.signOut();
        throw const AuthException('Usuario no encontrado en Firestore.');
      }

      final data = snapshot.data()!;
      final storedPassword = data['Contraseña']?.toString();
      final isEnabled = data['Valor'] == true;

      if (storedPassword != null &&
          storedPassword.isNotEmpty &&
          storedPassword != trimmedPassword) {
        await _firebaseAuth.signOut();
        throw const AuthException('Contraseña incorrecta.');
      }

      if (!isEnabled) {
        await _firebaseAuth.signOut();
        throw const AuthException('Usuario no habilitado.');
      }

      return AppUser(
        id: snapshot.id,
        nombre: data['Nombre']?.toString() ?? 'Sin nombre',
        correo: data['correo']?.toString() ?? trimmedCorreo,
        valor: isEnabled,
      );
    } on FirebaseAuthException catch (e, st) {
      dev.log('FirebaseAuthException',
          name: 'Auth',
          error: {'code': e.code, 'message': e.message},
          stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth error: ${e.code} - ${e.message}')),
      );
      throw AuthException('Auth error: ${e.code} - ${e.message}');
    } on FirebaseException catch (e) {
      throw AuthException('Error en Firestore: ${e.message}');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      dev.log('UnknownSignInError', name: 'Auth', error: e, stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unknown error: $e')),
      );
      throw AuthException('Unknown error: $e');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findAuthorizedUserByEmail(
    String correo,
  ) async {
    final collection = _firestore.collection('UsuariosAutorizados');

    try {
      final docByEmail = await collection.doc(correo).get();
      if (docByEmail.exists) {
        return docByEmail;
      }

      final lowerQuery =
          await collection.where('correo', isEqualTo: correo).limit(1).get();
      if (lowerQuery.docs.isNotEmpty) {
        return lowerQuery.docs.first;
      }

      final capitalizedQuery =
          await collection.where('Correo', isEqualTo: correo).limit(1).get();
      if (capitalizedQuery.docs.isNotEmpty) {
        return capitalizedQuery.docs.first;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }

    return null;
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<AppUser> signInWithCollection(
    BuildContext context,
    String correo,
    String password,
  ) {
    return login(context, correo, password);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

// Para desplegar las reglas en Firebase:
// firebase deploy --only firestore:rules
