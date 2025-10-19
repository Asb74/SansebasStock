import 'package:cloud_firestore/cloud_firestore.dart';
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
  AuthService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<AppUser> signIn(String correo, String password) async {
    final trimmedCorreo = correo.trim();
    final querySnapshot = await _firestore
        .collection('UsuariosAutorizados')
        .where('correo', isEqualTo: trimmedCorreo)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw const AuthException('Correo o contraseña incorrectos.');
    }

    final doc = querySnapshot.docs.first;
    final data = doc.data();

    final storedPassword = data['Contraseña']?.toString();
    final isEnabled = data['Valor'] == true;

    if (storedPassword != password.trim()) {
      throw const AuthException('Correo o contraseña incorrectos.');
    }

    if (!isEnabled) {
      throw const AuthException('Usuario no habilitado.');
    }

    return AppUser(
      id: doc.id,
      nombre: data['Nombre']?.toString() ?? 'Sin nombre',
      correo: data['correo']?.toString() ?? trimmedCorreo,
      valor: isEnabled,
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
