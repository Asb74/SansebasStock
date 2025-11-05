import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Handle returned by [registerAuthListenersSafely] to control the lifecycle of
/// the registered listeners.
class AuthListenersHandle {
  AuthListenersHandle._(this._close);

  final Future<void> Function() _close;
  bool _isClosed = false;

  /// Cancels all the listeners registered by [registerAuthListenersSafely].
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _close();
  }
}

/// Registra de forma segura los listeners de FirebaseAuth en el hilo de plataforma.
/// En Windows (y por seguridad en desktop), difiere el alta hasta el primer frame.
AuthListenersHandle registerAuthListenersSafely({
  void Function(User?)? onAuthState,
  void Function(User?)? onIdToken,
  void Function(User?)? onUserChanges,
}) {
  final subscriptions = <StreamSubscription<User?>>[];
  var closed = false;

  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    subscriptions.clear();
  }

  void start() {
    if (closed) {
      return;
    }

    if (onAuthState != null) {
      subscriptions.add(FirebaseAuth.instance
          .authStateChanges()
          .listen(onAuthState));
    }
    if (onIdToken != null) {
      subscriptions
          .add(FirebaseAuth.instance.idTokenChanges().listen(onIdToken));
    }
    if (onUserChanges != null) {
      subscriptions
          .add(FirebaseAuth.instance.userChanges().listen(onUserChanges));
    }
  }

  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  } else {
    start();
  }

  return AuthListenersHandle._(close);
}
