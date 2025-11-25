import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/session_store.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  Future<void> _checkSession() async {
    try {
      // 1) Leer credenciales guardadas
      final stored = await SessionStore.read();

      if (!mounted) return;

      if (stored == null) {
        dev.log('Sin credenciales → login', name: 'Splash');
        _goToLogin();
        return;
      }

      // 2) Intentar login automático
      final auth = ref.read(authServiceProvider);

      dev.log(
        'Intentando auto-login',
        name: 'Splash',
        error: {'email': stored.email},
      );

      final user =
          await auth.login(context, stored.email, stored.password);

      if (!mounted) return;

      // 3) Guardar usuario global
      ref.read(currentUserProvider.notifier).state = user;

      dev.log('Auto-login OK → home', name: 'Splash');
      _goToHome();
    } on AuthException catch (e, st) {
      dev.log(
        'AuthException en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _goToLogin();
    } catch (e, st) {
      dev.log(
        'Error inesperado en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _goToLogin();
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Aquí luego se pondrá la animación del logo (como en Sansebassms).
    // De momento solo mostramos un loader para asegurar el flujo.
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
