import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_service.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/map/camera_map_screen.dart';
import '../features/map/map_cameras_screen.dart';
import '../features/ops/qr_scan_screen.dart';
import '../features/splash/splash_screen.dart';
import '../models/camera_model.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: <GoRoute>[
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is AppUser) {
          final container = ProviderScope.containerOf(context, listen: false);
          container.read(currentUserProvider.notifier).state = extra;
        }
        return const HomeScreen();
      },
    ),
    GoRoute(
      path: '/qr',
      builder: (context, state) => const QrScanScreen(),
    ),
    GoRoute(
      path: '/map',
      builder: (context, state) => const MapCamerasScreen(),
    ),
    GoRoute(
      path: '/map/:camaraId',
      builder: (context, state) {
        final numero = state.pathParameters['camaraId'] ?? '01';
        final extra = state.extra;
        if (extra is CameraModel) {
          return CameraMapScreen.fromCamera(extra);
        }
        return CameraMapScreen(numero: numero);
      },
    ),
  ],
);
