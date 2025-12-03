import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/splash/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebaseSafely();
  runApp(const ProviderScope(child: SansebasStockApp()));
}

Future<void> _initFirebaseSafely() async {
  try {
    // Usar SIEMPRE las opciones generadas por flutterfire,
    // también en iOS. Así evitamos problemas con el plist.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    // Nunca reventar la app por un fallo de inicialización.
    dev.log(
      'Firebase init failed',
      name: 'Bootstrap',
      error: e,
      stackTrace: st,
    );
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
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
