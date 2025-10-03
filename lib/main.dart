import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'screens/auth_gate.dart';
import 'services/notifications.dart';

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

  runApp(const FridgeApp());
}


class FridgeApp extends StatelessWidget {
  const FridgeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const AuthGate(), // <-- use the gate
    );
  }
}

