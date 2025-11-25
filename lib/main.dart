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

Future<void> main() async {
  await _bootstrap();

  runApp(const ProviderScope(child: SansebasStockApp()));
}

class SansebasStockApp extends ConsumerWidget {
  const SansebasStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    late Future<FirebaseApp> init;

    if (kIsWeb) {
      // Web siempre necesita options explícitas
      init = Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else if (Platform.isIOS) {
      // En iOS usamos el GoogleService-Info.plist que ya está en ios/Runner
      init = Firebase.initializeApp();
    } else {
      // Android y demás plataformas usan firebase_options.dart
      init = Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Evitar bloqueos eternos
    await init.timeout(const Duration(seconds: 15));
  } on FirebaseException catch (error, stack) {
    dev.log('FirebaseInitError', error: error, stackTrace: stack);
    // No relanzamos la excepción para que la app pueda seguir
  } on TimeoutException catch (error, stack) {
    dev.log('FirebaseInitTimeout', error: error, stackTrace: stack);
  } catch (error, stack) {
    dev.log('FirebaseInitUnknown', error: error, stackTrace: stack);
  }
}
