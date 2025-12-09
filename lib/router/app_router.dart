import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/tools/compare_loteado_stock_screen.dart';
import '../features/tools/assign_storage/assign_storage_cameras_screen.dart';
import '../features/tools/assign_storage/assign_storage_rows_screen.dart';
import '../features/tools/tools_screen.dart';

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
    GoRoute(
      path: '/tools',
      name: 'tools',
      builder: (BuildContext context, GoRouterState state) =>
          const ToolsScreen(),
      routes: [
        GoRoute(
          path: 'compare',
          name: 'tools-compare',
          builder: (BuildContext context, GoRouterState state) =>
              const CompareLoteadoStockScreen(),
        ),
        GoRoute(
          path: 'assign-storage',
          name: 'tools-assign-storage',
          builder: (BuildContext context, GoRouterState state) =>
              const AssignStorageCamerasScreen(),
          routes: [
            GoRoute(
              path: ':cameraId',
              name: 'tools-assign-storage-camera',
              builder: (BuildContext context, GoRouterState state) {
                final cameraId = state.pathParameters['cameraId'] ?? '';
                return AssignStorageRowsScreen(cameraId: cameraId);
              },
            ),
          ],
        ),
      ],
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
