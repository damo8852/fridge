// lib/services/notifications.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (kIsWeb) {
      // Not supported on web
      _ready = false;
      return;
    }

    // Init settings
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(initSettings);

    // Android 13+ permission + channel
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // v19 API
      await android?.requestNotificationsPermission();

      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'expiry', // channel id
          'Expiry Reminders', // channel name
          description: 'Reminders before groceries expire',
          importance: Importance.high,
        ),
      );
    }

    _ready = true;
  }

  Future<void> scheduleExpiryReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (kIsWeb || !_ready) return;
    if (when.isBefore(DateTime.now())) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'expiry', 'Expiry Reminders',
        channelDescription: 'Reminders before groceries expire',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    final tzWhen = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzWhen,
      details,
      // v19: use androidScheduleMode instead of androidAllowWhileIdle
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // You can keep this to ensure exact date+time match (optional)
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      // v19: DO NOT pass uiLocalNotificationDateInterpretation (removed)
    );
  }

  Future<void> cancelAll() async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancelAll();
  }
}
