import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'features/auth/auth_service.dart';
import 'features/splash/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() {
  runZonedGuarded(() async {
    await _bootstrap();
    runApp(const ProviderScope(child: SansebasStockApp()));
  }, (error, stack) {
    dev.log('ZoneError', error: error, stackTrace: stack);
  });
}

class SansebasStockApp extends StatelessWidget {
  const SansebasStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sansebas Stock',
      theme: buildTheme(),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Versión segura de splash: si algo falla, se queda en UI con mensaje.
class SafeSplashScreen extends StatelessWidget {
  const SafeSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _runStartupLogic(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error al iniciar')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Se ha producido un error al iniciar la aplicación:\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        // Si todo va bien, mostramos el SplashScreen real de la app.
        return const SplashScreen();
      },
    );
  }

  Future<void> _runStartupLogic(BuildContext context) async {
    // Aquí puedes ir añadiendo poco a poco la lógica de sesión
    // usando AuthService, SharedPreferences, etc.
    // De momento, no hacemos nada para que no se caiga.
    return;
  }
}
