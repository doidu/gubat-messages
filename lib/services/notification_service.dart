import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<NotificationResponse> notificationResponseStream =
      StreamController<NotificationResponse>.broadcast();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTapped,
    );

    _isInitialized = true;
  }

  /// Handle notification tap in foreground
  void _onNotificationTapped(NotificationResponse response) {
    notificationResponseStream.add(response);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    debugPrint('Background notification tapped: ${response.payload}');
  }

  /// Show a Ham notification
  Future<void> showHamNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'ham_channel',
      'Ham Messages',
      channelDescription: 'Notifications for legitimate messages',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF4CAF50), // Green color for Ham
      icon: '@mipmap/launcher_icon',
      ticker: 'Ham message received',
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload ?? 'ham',
    );
  }

  /// Show a Spam notification
  Future<void> showSpamNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'spam_channel',
      'Spam Messages',
      channelDescription: 'Notifications for spam messages',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFF44336), // Red color for Spam
      icon: '@mipmap/launcher_icon',
      ticker: 'Spam message detected',
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload ?? 'spam',
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notificationsPlugin.pendingNotificationRequests();
  }

  /// Dispose the service
  void dispose() {
    notificationResponseStream.close();
  }
}
