import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'medicine_reminder_channel';
  static const String _channelName = 'Medicine Reminders';
  static const String _channelDesc = 'Reminders for taking medicine';

  // অ্যাপ চালু হওয়ার সময় একবার কল হবে (main.dart থেকে, await সহ)
  static Future<void> init() async {
    await _configureLocalTimeZone();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings: settings);

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    final notifGranted = await androidPlugin?.requestNotificationsPermission();
    final exactAlarmGranted = await androidPlugin?.requestExactAlarmsPermission();
    debugPrint('Notification permission granted: $notifGranted');
    debugPrint('Exact alarm permission granted: $exactAlarmGranted');

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin?.createNotificationChannel(channel);
  }

  static Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
      debugPrint('Local timezone set to: ${timezoneInfo.identifier}');
    } catch (e) {
      debugPrint('Could not detect timezone, defaulting to Asia/Dhaka: $e');
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    }
  }

  static int safeNotificationId(String docId, int doseIndex) {
    final base = docId.hashCode & 0x7FFFFFFF;
    return (base % 1000000) + doseIndex;
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    debugPrint('Scheduling "$title" id=$id for $scheduledDate (now=$now, tz=${tz.local.name})');

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint('Successfully scheduled notification id=$id');
  }

  // 🔔 টেস্ট: instant
  static Future<void> showTestNotification() async {
    await _notificationsPlugin.show(
      id: 999,
      title: 'Test Notification 🔔',
      body: 'If you see this, notifications are working!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max, priority: Priority.high,
          playSound: true, enableVibration: true,
        ),
      ),
    );
  }

  // ⏱️ টেস্ট: 10 সেকেন্ড পর
  static Future<void> scheduleTestNotification() async {
    final scheduledTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
    debugPrint('Test scheduled for: $scheduledTime (tz=${tz.local.name})');
    await _notificationsPlugin.zonedSchedule(
      id: 998,
      title: 'Scheduled Test 🔔',
      body: 'This was scheduled 10 seconds ago!',
      scheduledDate: scheduledTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max, priority: Priority.high,
          playSound: true, enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}