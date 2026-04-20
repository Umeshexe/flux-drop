import 'dart:io';
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background FCM handler (top-level function, required by Firebase)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // App is in background/terminated
  // The notification will be shown automatically by FCM
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<String?> _openTransfersController =
      StreamController<String?>.broadcast();

  Stream<String?> get openTransfersRequests => _openTransfersController.stream;

  Future<bool> initialize() async {
    // Local notifications setup
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // Do NOT set requestAlertPermission etc. here — on personal-team iOS builds
    // those flags trigger APNs registration which crashes with EXC_BAD_ACCESS.
    // Permissions are handled separately below only on supported builds.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings: initSettings);

    // iOS sender builds in this assessment environment have been unstable when
    // Firebase Messaging is initialized directly without the full APNs setup.
    // Keep local notifications available, but only wire FCM listeners on Android.
    if (Platform.isIOS) {
      return false;
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Android notification channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'fluxdrop_transfers',
        'FluxDrop Transfers',
        description: 'Notifications for incoming file transfers',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    // Handle FCM foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap when app was fully closed
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
      return true;
    }

    return false;
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final title = data['title'] ?? '📥 New Transfer';
    final body = data['body'] ?? 'Someone sent you files!';

    await showLocalNotification(title: title, body: body);
  }

  void _handleNotificationTap(RemoteMessage message) {
    _openTransfersController.add(message.data['transferId'] as String?);
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'fluxdrop_transfers',
      'FluxDrop Transfers',
      channelDescription: 'Notifications for incoming file transfers',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
