import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  SessionStore._();

  static const _emailKey = 'session_email';
  static const _passwordKey = 'session_password';

  /// Guarda correo y contraseña en SharedPreferences.
  static Future<void> save(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim());
    await prefs.setString(_passwordKey, password.trim());
  }

  /// Devuelve credenciales guardadas o null si no hay datos válidos.
  static Future<StoredCredentials?> read() async {
    final prefs = await SharedPreferences.getInstance();

    final email = prefs.getString(_emailKey);
    final password = prefs.getString(_passwordKey);

    if (email == null ||
        password == null ||
        email.trim().isEmpty ||
        password.trim().isEmpty) {
      return null;
    }

    return StoredCredentials(
      email: email,
      password: password,
    );
  }

  /// Borra las credenciales guardadas.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_passwordKey);
  }
}

class StoredCredentials {
  const StoredCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}
