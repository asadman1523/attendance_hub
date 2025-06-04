import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../models/weekend_tracker.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification IDs
  static const int clockInNotificationId = 1;
  static const int clockOutNotificationId = 2;

  // Preference keys
  static const String clockInHourKey = 'clockInHour';
  static const String clockInMinuteKey = 'clockInMinute';
  static const String clockOutHourKey = 'clockOutHour';
  static const String clockOutMinuteKey = 'clockOutMinute';

  // Default notification times
  static const int defaultClockInHour = 9;
  static const int defaultClockInMinute = 20;
  static const int defaultClockOutHour = 18;
  static const int defaultClockOutMinute = 30;

  // Action IDs
  static const String clockInActionId = 'clock_in';
  static const String clockOutActionId = 'clock_out';

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: (int id, String? title, String? body, String? payload) async {},
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    
    // Request permission on iOS
    if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // Request permission on Android
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> _onNotificationTap(NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;
    
    if (payload == clockInActionId) {
      // Handle clock in action
      debugPrint('User tapped clock in notification');
      await _triggerWebhook('clockIn');
    } else if (payload == clockOutActionId) {
      // Handle clock out action
      debugPrint('User tapped clock out notification');
      await _triggerWebhook('clockOut');
    }
  }

  Future<void> _triggerWebhook(String action) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final webhookUrl = prefs.getString('webhookUrl');
    
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint('Webhook URL not configured');
      return;
    }

    // Check if already clocked in/out today
    if (action == 'clockIn' && (prefs.getBool('clockedIn_$today') ?? false)) {
      debugPrint('Already clocked in today');
      return;
    }
    if (action == 'clockOut' && (prefs.getBool('clockedOut_$today') ?? false)) {
      debugPrint('Already clocked out today');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'timestamp': DateTime.now().toIso8601String()
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateFormat('HH:mm:ss').format(DateTime.now());
        if (action == 'clockIn') {
          await prefs.setBool('clockedIn_$today', true);
          await prefs.setString('clockInTime_$today', now);
        } else {
          await prefs.setBool('clockedOut_$today', true);
          await prefs.setString('clockOutTime_$today', now);
        }
      } else {
        debugPrint('Webhook failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error triggering webhook: $e');
    }
  }

  Future<void> scheduleNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get notification times from preferences or use defaults
    final clockInHour = prefs.getInt(clockInHourKey) ?? defaultClockInHour;
    final clockInMinute = prefs.getInt(clockInMinuteKey) ?? defaultClockInMinute;
    final clockOutHour = prefs.getInt(clockOutHourKey) ?? defaultClockOutHour;
    final clockOutMinute = prefs.getInt(clockOutMinuteKey) ?? defaultClockOutMinute;

    // Get next work day
    final nextWorkDay = await _getNextWorkDay();
    if (nextWorkDay == null) {
      debugPrint('No suitable workday found for scheduling notifications');
      return;
    }

    // Schedule clock in notification
    await _scheduleClockInNotification(nextWorkDay, clockInHour, clockInMinute);
    
    // Schedule clock out notification
    await _scheduleClockOutNotification(nextWorkDay, clockOutHour, clockOutMinute);
    
    debugPrint(
      'Scheduled notifications for ${DateFormat('yyyy-MM-dd').format(nextWorkDay)}: ' +
      'Clock in at $clockInHour:$clockInMinute, Clock out at $clockOutHour:$clockOutMinute'
    );
  }

  Future<void> _scheduleClockInNotification(
      DateTime date, int hour, int minute) async {
    final scheduledDate = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
    
    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint('Clock-in time is in the past, not scheduling');
      return;
    }
    
    final tzDateTime = tz.TZDateTime.from(scheduledDate, tz.local);
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'clock_in_channel',
      '上班打卡提醒',
      channelDescription: '提醒您上班打卡',
      importance: Importance.high,
      priority: Priority.high,
    );

    // For iOS
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'attendance_hub',
      subtitle: '今天記得打卡',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      clockInNotificationId,
      '上班打卡提醒',
      '現在時間 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}，請記得打卡！點擊此通知立即打卡',
      tzDateTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: clockInActionId,
    );
  }

  Future<void> _scheduleClockOutNotification(
      DateTime date, int hour, int minute) async {
    final scheduledDate = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint('Clock-out time is in the past, not scheduling');
      return;
    }
    
    final tzDateTime = tz.TZDateTime.from(scheduledDate, tz.local);
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'clock_out_channel',
      '下班打卡提醒',
      channelDescription: '提醒您下班打卡',
      importance: Importance.high,
      priority: Priority.high,
    );

    // For iOS
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'attendance_hub',
      subtitle: '別忘了打下班卡',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      clockOutNotificationId,
      '下班打卡提醒',
      '現在時間 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}，請記得打卡！點擊此通知立即打卡',
      tzDateTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: clockOutActionId,
    );
  }

  // Logic to determine the next work day based on the alternating weekend schedule
  Future<DateTime?> _getNextWorkDay() async {
    final now = DateTime.now();
    
    // Check if today is a workday
    if (await WeekendTracker.isWorkday()) {
      return now;
    }
    
    // If today isn't a workday, find the next one
    return _findNextWorkDay(now);
  }

  Future<DateTime> _findNextWorkDay(DateTime startDate) async {
    DateTime date = startDate;
    bool isWorkday = false;
    
    // Keep looking forward one day at a time until we find a workday
    while (!isWorkday) {
      date = date.add(const Duration(days: 1));
      isWorkday = await WeekendTracker.isWorkday();
    }
    
    return date;
  }

  // Update alternating weekend pattern
  // Should be called at the end of each big weekend to mark the date
  Future<void> markBigWeekend() async {
    await WeekendTracker.markBigWeekend();
  }

  // Save notification time settings
  Future<void> saveNotificationTimes({
    required int clockInHour, 
    required int clockInMinute,
    required int clockOutHour,
    required int clockOutMinute,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(clockInHourKey, clockInHour);
    await prefs.setInt(clockInMinuteKey, clockInMinute);
    await prefs.setInt(clockOutHourKey, clockOutHour);
    await prefs.setInt(clockOutMinuteKey, clockOutMinute);
    
    // Reschedule notifications with new times
    await scheduleNotifications();
  }

  // Get notification time settings
  Future<Map<String, int>> getNotificationTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'clockInHour': prefs.getInt(clockInHourKey) ?? defaultClockInHour,
      'clockInMinute': prefs.getInt(clockInMinuteKey) ?? defaultClockInMinute,
      'clockOutHour': prefs.getInt(clockOutHourKey) ?? defaultClockOutHour,
      'clockOutMinute': prefs.getInt(clockOutMinuteKey) ?? defaultClockOutMinute,
    };
  }
} 