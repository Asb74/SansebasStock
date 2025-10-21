import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/session_store.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_attemptAutoLogin);
  }

  Future<void> _attemptAutoLogin() async {
    final credentials = await SessionStore.read();

    if (!mounted) {
      return;
    }

    if (credentials == null) {
      context.go('/login');
      return;
    }

    final authService = ref.read(authServiceProvider);

    try {
      final user = await authService.signInWithCollection(
        credentials.email,
        credentials.password,
      );

      ref.read(currentUserProvider.notifier).state = user;

      if (!mounted) {
        return;
      }

      context.go('/', extra: user);
    } on AuthException {
      await SessionStore.clear();
      if (mounted) {
        context.go('/login');
      }
    } catch (_) {
      await SessionStore.clear();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
