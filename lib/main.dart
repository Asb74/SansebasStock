import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    print("🔥 Firebase INIT OK 🔥");
  } catch (e, st) {
    runApp(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: Text('Error Firebase')),
          body: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Error inicializando Firebase:\n$e',
              style: TextStyle(fontSize: 17),
            ),
          ),
        ),
      ),
    );
    print("🔥 Firebase INIT ERROR: $e");
    print(st);
    return;
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    ),
  );
}
