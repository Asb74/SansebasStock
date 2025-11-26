import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'features/splash/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebaseSafely();
  runApp(const ProviderScope(child: SansebasStockApp()));
}

Future<void> _initFirebaseSafely() async {
  try {
    // Si ya hay una app inicializada (por ejemplo, desde iOS nativo),
    // simplemente la usamos. Si no, la creamos con las opciones generadas.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
  } catch (e, st) {
    // Nunca reventar la app por un error de inicialización.
    dev.log('Firebase init failed', error: e, stackTrace: st);
  }
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
