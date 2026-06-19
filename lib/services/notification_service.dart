import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
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
