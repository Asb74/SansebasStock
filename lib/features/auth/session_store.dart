import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  SessionStore._();

  static const _emailKey = 'session_email';
  static const _passwordKey = 'session_password';

  static Future<void> save(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim());
    await prefs.setString(_passwordKey, password.trim());
  }

  static Future<StoredCredentials?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    final password = prefs.getString(_passwordKey);

    if (email == null || email.isEmpty || password == null || password.isEmpty) {
      return null;
    }

    return StoredCredentials(email: email, password: password);
  }

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
