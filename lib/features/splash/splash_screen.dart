import 'dart:async';
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
  String _status = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  void _setStatus(String msg) {
    dev.log(msg, name: 'SplashStatus');
    if (!mounted) return;
    setState(() {
      _status = msg;
    });
  }

  Future<void> _checkSession() async {
    try {
      _setStatus('Leyendo credenciales guardadas...');
      final stored = await SessionStore.read();
      _setStatus(
        stored == null
            ? 'Sin credenciales guardadas.'
            : 'Credenciales encontradas para ${stored.email}',
      );

      // Pequeña pausa para que se lea el mensaje
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      if (stored == null) {
        _setStatus('Navegando a Login...');
        _goToLogin();
        return;
      }

      // Intentar login automático
      final auth = ref.read(authServiceProvider);

      _setStatus('Intentando auto-login en Firebase...');
      final user = await auth
          .login(context, stored.email, stored.password)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      _setStatus('Login correcto. Entrando en la app...');
      ref.read(currentUserProvider.notifier).state = user;
      _goToHome();
    } on AuthException catch (e, st) {
      dev.log(
        'AuthException en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _setStatus('Error de autenticación: ${e.message}. Abriendo Login...');
      await Future.delayed(const Duration(milliseconds: 500));
      _goToLogin();
    } on TimeoutException catch (e, st) {
      dev.log(
        'Timeout en login automático',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _setStatus('Tiempo de espera agotado. Abriendo Login...');
      await Future.delayed(const Duration(milliseconds: 500));
      _goToLogin();
    } catch (e, st) {
      dev.log(
        'Error inesperado en splash',
        name: 'Splash',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _setStatus('Error inesperado: $e. Abriendo Login...');
      await Future.delayed(const Duration(milliseconds: 500));
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
    // Luego aquí podemos cambiar el loader por la animación del logo
    // como en Sansebassms. De momento mostramos loader + texto de estado.
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _status,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
