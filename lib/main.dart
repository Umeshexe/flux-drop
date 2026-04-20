import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

// TODO: Run `flutterfire configure` to generate firebase_options.dart, then:
// 1. Uncomment the import below
// 2. Replace Firebase.initializeApp() with Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
// import 'firebase_options.dart';

/// Background FCM handler — MUST be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppTheme.initialize();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  AppTheme.applySystemUi();

  // Initialize Firebase with generated config
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!Platform.isIOS) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(FluxDropApp());
}

class FluxDropApp extends StatelessWidget {
  const FluxDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FluxThemeMode>(
      valueListenable: AppTheme.modeNotifier,
      builder: (context, mode, _) {
        AppTheme.applySystemUi();
        return MaterialApp(
          title: 'FluxDrop',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.materialTheme,
          builder: (context, child) {
            return GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: child,
            );
          },
          home: SplashScreen(),
        );
      },
    );
  }
}
