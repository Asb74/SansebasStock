import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_listeners.dart';
import 'features/auth/auth_service.dart';
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

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    _swallowLockKeys(); // DESKTOP FIX: Avoid crashes from lock keys on desktop.
  }

  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else if (Platform.isIOS || Platform.isMacOS) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } else {
      Firebase.app();
    }
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
    Firebase.app();
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // evita que se cierre el proceso en desktop
  };
}

void main() {
  runZonedGuarded(() async {
    await _bootstrap();
    runApp(const AppBootstrapper());

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Text(
              details.exceptionAsString(),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
    };
  }, (e, st) {
    dev.log('ZoneError', error: e, stackTrace: st);
  });
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  late final ProviderContainer _container;
  AuthListenersHandle? _authListenersHandle;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer();
    _authListenersHandle = registerAuthListenersSafely(
      onAuthState: _onAuthStateChanged,
    );
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      _container.read(currentUserProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    unawaited(_authListenersHandle?.close());
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: const SansebasStockApp(),
    );
  }
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
