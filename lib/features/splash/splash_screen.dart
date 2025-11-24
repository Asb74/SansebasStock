import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/session_store.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Ejecutamos la lógica después del primer frame para evitar errores de contexto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  Future<void> _checkSession() async {
    try {
      // Leer credenciales guardadas
      final stored = await SessionStore.read();

      if (!mounted) return;

      if (stored == null) {
        dev.log('No stored credentials → go /login', name: 'Splash');
        context.go('/login');
        return;
      }

      // Intentar login automático
      final auth = ref.read(authServiceProvider);

      dev.log(
        'Trying auto-login...',
        name: 'Splash',
        error: {'email': stored.email},
      );

      final user =
          await auth.login(context, stored.email, stored.password);

      if (!mounted) return;

      // Guardar usuario global
      ref.read(currentUserProvider.notifier).state = user;

      dev.log('Auto-login OK → go /', name: 'Splash');
      context.go('/');
    } on AuthException catch (e, st) {
      dev.log('AuthException in splash', name: 'Splash', error: e, stackTrace: st);
      if (!mounted) return;
      context.go('/login');
    } catch (e, st) {
      dev.log('Unexpected splash error', name: 'Splash', error: e, stackTrace: st);
      if (!mounted) return;
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla durante la espera
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
