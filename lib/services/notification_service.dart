import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../repositories/app_repositories.dart';
import '../navigation/session_navigation.dart';

@pragma('pragma vm:entry-point')
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Do nothing or log if needed
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // 0. Initialize timezone data
    tz_data.initializeTimeZones();

    // 1. Request Permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Set up local notifications settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response.payload);
      },
    );

    // 3. Set up Android Notification Channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'autiease_high_channel',
      'High Importance Notifications',
      description: 'Used for important messages and emergencies.',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 4. Register FCM Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null) {
        String payloadString = '';
        if (message.data.isNotEmpty) {
          payloadString = message.data['route'] ?? '';
        }

        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            ),
          ),
          payload: payloadString,
        );
      }
    });

    // 6. Handle Message Taps (when app is in background or terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data['route']);
    });

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage.data['route']);
    }

    // 7. Get and save FCM Token
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await AppRepositories.support.saveFcmToken(token);
      }
    } catch (_) {
      // Catch exceptions for environments without FCM setup (e.g. windows desktop run)
    }

    _fcm.onTokenRefresh.listen((newToken) async {
      try {
        await AppRepositories.support.saveFcmToken(newToken);
      } catch (_) {}
    });

    _initialized = true;
  }

  /// Schedule a local notification 1 hour before [sessionTime].
  /// [notificationId] should be unique per session (e.g. hash of session doc ID).
  Future<void> scheduleSessionReminder({
    required int notificationId,
    required DateTime sessionTime,
    required String therapistName,
  }) async {
    final fireAt = sessionTime.subtract(const Duration(hours: 1));
    if (fireAt.isBefore(DateTime.now())) return; // Already past

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'autiease_session_channel',
        'Session Reminders',
        channelDescription: 'Reminders sent 1 hour before a booked therapy session.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.zonedSchedule(
      notificationId,
      'Session in 1 hour',
      'Your session with $therapistName starts at ${_fmt(sessionTime)}. Get ready!',
      tz.TZDateTime.from(fireAt, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'session_reminder',
    );
  }

  /// Cancel a previously scheduled session reminder by [notificationId].
  Future<void> cancelSessionReminder(int notificationId) async {
    await _localNotifications.cancel(notificationId);
  }

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $amPm';
  }

  void _handleNotificationTap(String? route) {
    if (route == null || route.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route == 'chat') {
        // Direct route to notifications inbox or chat home screen
        navigatorKey.currentState?.pushNamed('/professional_support');
      } else if (route == 'reviews') {
        navigatorKey.currentState?.pushNamed('/reviews');
      } else if (route == 'verification') {
        navigatorKey.currentState?.pushNamed('/profile_status');
      } else {
        navigatorKey.currentState?.pushNamed('/notifications_inbox');
      }
    });
  }
}
