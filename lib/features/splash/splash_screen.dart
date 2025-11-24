import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_store.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _debugMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDebugStartup();
    });
  }

  Future<void> _runDebugStartup() async {
    try {
      // 1) Probar lectura de SessionStore
      _setDebug('Leyendo credenciales guardadas...');
      final stored = await SessionStore.read();
      _setDebug('Credenciales leídas: ${stored?.email ?? "NINGUNA"}');

      // 2) Esperar un poco para ver el mensaje
      await Future.delayed(const Duration(seconds: 1));

      // 3) Probar navegación sencilla a /login (sin hacer login automático)
      if (!mounted) return;
      _setDebug('Navegando a /login ...');
      context.go('/login');
    } catch (e, st) {
      dev.log('Error en Splash debug', name: 'SplashDebug', error: e, stackTrace: st);
      if (!mounted) return;
      _setDebug('ERROR en Splash:\n$e');
    }
  }

  void _setDebug(String msg) {
    dev.log(msg, name: 'SplashDebug');
    setState(() {
      _debugMessage = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _debugMessage == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _debugMessage!,
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}
