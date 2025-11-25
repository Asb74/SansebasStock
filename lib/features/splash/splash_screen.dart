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
        dev.log('Sin credenciales → /login', name: 'Splash');
        context.go('/login');
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

      // 3) Guardar usuario en provider global
      ref.read(currentUserProvider.notifier).state = user;

      dev.log('Auto-login OK → /', name: 'Splash');
      context.go('/');
    } on AuthException catch (e, st) {
      dev.log(
        'AuthException en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      context.go('/login');
    } catch (e, st) {
      dev.log(
        'Error inesperado en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aquí podemos poner la animación tipo Sansebassms más adelante.
    // De momento mostramos un loader para asegurar el flujo.
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
