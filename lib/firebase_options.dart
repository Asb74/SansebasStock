// Placeholder temporal: reemplazar por el generado por `flutterfire configure`.
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const FirebaseOptions(
          apiKey: "REEMPLAZAR",
          appId: "REEMPLAZAR",
          messagingSenderId: "REEMPLAZAR",
          projectId: "REEMPLAZAR",
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const FirebaseOptions(
          apiKey: "REEMPLAZAR",
          appId: "REEMPLAZAR",
          messagingSenderId: "REEMPLAZAR",
          projectId: "REEMPLAZAR",
        );
    }
  }
}
