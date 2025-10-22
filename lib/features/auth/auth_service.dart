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

  Future<AppUser> login(String correo, String password) async {
    try {
      final trimmedCorreo = correo.trim().toLowerCase();
      final trimmedPassword = password.trim();

      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: trimmedCorreo,
        password: trimmedPassword,
      );

      final uid = credential.user!.uid;
      final snapshot =
          await _firestore.collection('UsuariosAutorizados').doc(uid).get();

      if (!snapshot.exists) {
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
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Error de autenticación.');
    } on FirebaseException catch (e) {
      throw AuthException('Error en Firestore: ${e.message}');
    } catch (e) {
      throw AuthException('Error inesperado: $e');
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<AppUser> signInWithCollection(String correo, String password) {
    return login(correo, password);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

// Para desplegar las reglas en Firebase:
// firebase deploy --only firestore:rules --rules firebase/firestore.rules.prod
