import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'screens/auth_gate.dart';
import 'services/notifications.dart';
import 'services/theme_service.dart';
import 'services/config_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Timezone (for scheduled notifs)
  tz.initializeTimeZones();
  // If you want device-detected tz later, use flutter_native_timezone.
  tz.setLocalLocation(tz.getLocation('America/Denver'));

  // Local notifications
  await NotificationsService.instance.init(); // creates channel, requests permissions on iOS/Android 13+

  // Initialize theme service
  await ThemeService().init();

  // Initialize configuration service with default API key
  await ConfigService().initializeWithDefaultKey();

  runApp(const EcoPantryApp());
}


class EcoPantryApp extends StatelessWidget {
  const EcoPantryApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoPantry',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF27AE60)),
        useMaterial3: true,
      ),
      home: const AuthGate(), // <-- use the gate
    );
  }
}

