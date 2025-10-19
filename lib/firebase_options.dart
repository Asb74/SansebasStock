// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: '1:000000000000:web:example',
    messagingSenderId: '000000000000',
    projectId: 'sansebas-stock',
    authDomain: 'sansebas-stock.firebaseapp.com',
    storageBucket: 'sansebas-stock.appspot.com',
    measurementId: 'G-EXAMPLE',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: '1:000000000000:android:example',
    messagingSenderId: '000000000000',
    projectId: 'sansebas-stock',
    storageBucket: 'sansebas-stock.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:000000000000:ios:example',
    messagingSenderId: '000000000000',
    projectId: 'sansebas-stock',
    storageBucket: 'sansebas-stock.appspot.com',
    iosBundleId: 'com.sansebas.stock',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: '1:000000000000:ios:example',
    messagingSenderId: '000000000000',
    projectId: 'sansebas-stock',
    storageBucket: 'sansebas-stock.appspot.com',
    iosBundleId: 'com.sansebas.stock',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'YOUR_WINDOWS_API_KEY',
    appId: '1:000000000000:web:example',
    messagingSenderId: '000000000000',
    projectId: 'sansebas-stock',
    storageBucket: 'sansebas-stock.appspot.com',
  );
}
