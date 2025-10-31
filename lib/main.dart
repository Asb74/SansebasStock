import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

// DESKTOP FIX: Intercept problematic lock key events on desktop platforms.
void _swallowLockKeys() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final prev = dispatcher.onKeyData;
  dispatcher.onKeyData = (KeyData data) {
    const lockKeys = <int>{
      0x100000104, // Caps Lock
      0x100000107, // Num Lock
      0x100000106, // Scroll Lock
    };
    if (lockKeys.contains(data.logical)) {
      return true; // DESKTOP FIX: Suppress lock keys causing asserts.
    }
    return prev?.call(data) ?? false;
  };
}

// DESKTOP FIX: Surface uncaught Flutter and platform dispatcher errors.
void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    debugPrintStack(stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers(); // DESKTOP FIX: Capture unhandled errors early.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    _swallowLockKeys(); // DESKTOP FIX: Avoid crashes from lock keys on desktop.
  }
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
    Firebase.app();
  }

  runApp(const ProviderScope(child: SansebasStockApp()));
}

class SansebasStockApp extends StatelessWidget {
  const SansebasStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sansebas Stock',
      theme: buildTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
