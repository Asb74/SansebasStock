import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<AppUser> signIn(String correo, String password) async {
    final normalizedCorreo = correo.trim().toLowerCase();
    final trimmedPassword = password.trim();

    try {
      final currentUser = _firebaseAuth.currentUser;
      final currentEmail = currentUser?.email?.toLowerCase();

      if (currentEmail != null && currentEmail != normalizedCorreo) {
        await _firebaseAuth.signOut();
      }

      await _firebaseAuth.signInWithEmailAndPassword(
        email: normalizedCorreo,
        password: trimmedPassword,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-disabled') {
        throw const AuthException('Usuario no habilitado.');
      }
      throw const AuthException('Correo o contraseña incorrectos.');
    }

    try {
      debugPrint(
        'Consultando UsuariosAutorizados con correo: $normalizedCorreo',
      );

      final querySnapshot = await _firestore
          .collection('UsuariosAutorizados')
          .where('correo', isEqualTo: normalizedCorreo)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        await _firebaseAuth.signOut();
        throw const AuthException('Correo o contraseña incorrectos.');
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();

      final storedPassword = data['Contraseña']?.toString();
      final isEnabled = data['Valor'] == true;

      if (storedPassword != null &&
          storedPassword.isNotEmpty &&
          storedPassword != trimmedPassword) {
        await _firebaseAuth.signOut();
        throw const AuthException('Correo o contraseña incorrectos.');
      }

      if (!isEnabled) {
        await _firebaseAuth.signOut();
        throw const AuthException('Usuario no habilitado.');
      }

      final firestoreCorreo = data['correo']?.toString();
      final appUserCorreo =
          firestoreCorreo != null ? firestoreCorreo.toLowerCase() : normalizedCorreo;

      return AppUser(
        id: doc.id,
        nombre: data['Nombre']?.toString() ?? 'Sin nombre',
        correo: appUserCorreo,
        valor: isEnabled,
      );
    } on FirebaseException catch (error) {
      await _firebaseAuth.signOut();
      if (error.code == 'permission-denied') {
        throw const AuthException('No tienes permisos para iniciar sesión.');
      }
      throw const AuthException('Ha ocurrido un error inesperado.');
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<AppUser> signInWithCollection(String correo, String password) {
    return signIn(correo, password);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
