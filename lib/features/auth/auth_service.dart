import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return const AuthService();
});

final currentUserProvider = StateProvider<AppUser?>((ref) => null);

class AuthService {
  const AuthService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<AppUser> signIn(String email, String password) async {
    final trimmedEmail = email.trim();
    final querySnapshot = await _firestore
        .collection('UsuariosAutorizados')
        .where('correo', isEqualTo: trimmedEmail)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw const AuthException('Correo o contraseña incorrectos.');
    }

    final doc = querySnapshot.docs.first;
    final data = doc.data();

    final storedPassword = data['Contraseña'] as String?;
    final isEnabled = data['Valor'] as bool? ?? false;

    if (storedPassword == null || storedPassword != password.trim()) {
      throw const AuthException('Correo o contraseña incorrectos.');
    }

    if (!isEnabled) {
      throw const AuthException('Usuario no habilitado.');
    }

    final name = data['Nombre'] as String? ?? '';

    final user = AppUser(
      id: doc.id,
      email: trimmedEmail,
      name: name,
      enabled: isEnabled,
    );

    return user;
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.enabled,
  });

  final String id;
  final String email;
  final String name;
  final bool enabled;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
