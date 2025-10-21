import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug/error_screen.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

final StringBuffer _errorLog = StringBuffer();

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        final stackTrace = details.stack ?? StackTrace.current;
        _handleError(
          details.exception,
          stackTrace,
          prefix: 'FlutterError capturado:',
        );
      };

      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        runApp(const ProviderScope(child: SansebasStockApp()));
      } catch (error, stackTrace) {
        _handleError(
          error,
          stackTrace,
          prefix:
              'Error inicializando Firebase. Verifica google-services.json o firebase_options.dart',
        );
      }
    },
    (error, stackTrace) {
      _handleError(
        error,
        stackTrace,
        prefix: 'Excepción no controlada capturada por runZonedGuarded:',
      );
    },
  );
}

void _handleError(Object error, StackTrace? stackTrace, {String? prefix}) {
  final buffer = StringBuffer();
  if (prefix != null && prefix.isNotEmpty) {
    buffer.writeln(prefix);
  }
  buffer.writeln(error);
  if (stackTrace != null) {
    buffer.writeln(stackTrace);
  }
  _appendLog(buffer.toString().trim());
  _presentErrorScreen();
}

void _appendLog(String message) {
  final timestamp = DateTime.now().toIso8601String();
  final entry = '[$timestamp] $message';
  debugPrint(entry);
  _errorLog
    ..writeln(entry)
    ..writeln();
}

void _presentErrorScreen() {
  final logMessage = _errorLog.toString().trim();
  final displayMessage =
      logMessage.isEmpty ? 'Se produjo un error inesperado.' : logMessage;

  runApp(
    MaterialApp(
      title: 'Sansebas Stock - Error',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: ErrorScreen(message: displayMessage),
    ),
  );
}

class SansebasStockApp extends ConsumerWidget {
  const SansebasStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Sansebas Stock',
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
