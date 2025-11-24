import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/splash_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/home_screen.dart';

/// Configuración principal de rutas para SansebasStock.
/// De momento definimos solo las rutas básicas para evitar pantallas en blanco.
/// Más adelante se pueden añadir /qr, /map, /informe-stock, etc.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: true, // loggea rutas en consola (útil para depurar)
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (BuildContext context, GoRouterState state) =>
          const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (BuildContext context, GoRouterState state) =>
          const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      name: 'home',
      builder: (BuildContext context, GoRouterState state) =>
          const HomeScreen(),
    ),
  ],
  errorBuilder: (BuildContext context, GoRouterState state) {
    // Si hay algún error de navegación, que se vea algo en pantalla
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error de navegación'),
      ),
      body: Center(
        child: Text(
          'Ha ocurrido un error de rutas:\n${state.error}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  },
);
