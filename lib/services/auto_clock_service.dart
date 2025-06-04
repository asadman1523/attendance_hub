import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/weekend_tracker.dart';
import 'background_service.dart';

class AutoClockService {
  static final AutoClockService _instance = AutoClockService._internal();
  factory AutoClockService() => _instance;
  AutoClockService._internal();

  // Preference keys
  static const String autoClockInEnabledKey = 'autoClockInEnabled';
  static const String autoClockOutEnabledKey = 'autoClockOutEnabled';
  static const String autoClockInHourKey = 'autoClockInHour';
  static const String autoClockInMinuteKey = 'autoClockInMinute';
  static const String autoClockOutHourKey = 'autoClockOutHour';
  static const String autoClockOutMinuteKey = 'autoClockOutMinute';
  static const String lastCheckedDateKey = 'lastCheckedDate';

  // Default times
  static const int defaultClockInHour = 9;
  static const int defaultClockInMinute = 20;
  static const int defaultClockOutHour = 18;
  static const int defaultClockOutMinute = 30;

  // 自動打卡通知ID
  static const int autoClockInNotificationId = 200;
  static const int autoClockOutNotificationId = 201;
  
  // 通知插件
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Auto-clock timer (for in-app checking)
  Timer? _timer;
  bool _isRunning = false;
  
  // Background service for out-of-app execution
  final BackgroundService _backgroundService = BackgroundService();

  // Initialize the service
  Future<void> init() async {
    // Initialize notifications
    await _initializeNotifications();
    
    // Start the in-app timer
    _startPeriodicCheck();
    
    // Also setup the background service for when app is not running
    await _backgroundService.init();
    
    // 立即檢查一次打卡狀態（用於從背景返回時）
    _checkCurrentStatus();
  }
  
  // Initialize notifications
  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    final InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notificationsPlugin.initialize(initSettings);
  }

  // 顯示自動打卡通知
  Future<void> _showAutoClockNotification(String action, String time) async {
    // 通知設置
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'auto_clock_channel',
      '自動打卡通知',
      channelDescription: '自動打卡成功時發送的通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // 根據動作類型顯示不同的通知
    if (action == 'clockIn') {
      await _notificationsPlugin.show(
        autoClockInNotificationId,
        '自動上班打卡成功',
        '系統已於 $time 自動完成上班打卡',
        notificationDetails,
      );
    } else {
      await _notificationsPlugin.show(
        autoClockOutNotificationId,
        '自動下班打卡成功',
        '系統已於 $time 自動完成下班打卡',
        notificationDetails,
      );
    }
  }

  // Start periodic check (every minute) - this runs when app is open
  void _startPeriodicCheck() {
    // Cancel any existing timer
    _timer?.cancel();
    _isRunning = true;

    // Start a new timer that checks every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _checkAndClock();
    });

    // Immediately run an initial check
    _checkAndClock();
  }

  // Stop periodic check
  void stopService() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  // Check if it's time to clock in/out and do so if needed
  Future<void> _checkAndClock() async {
    if (!_isRunning) return;

    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final prefs = await SharedPreferences.getInstance();
    
    // Check if today is a workday
    final isWorkday = await WeekendTracker.isWorkday();
    if (!isWorkday) {
      debugPrint('AutoClockService: Today is not a workday, skipping auto-clock.');
      await prefs.setString(lastCheckedDateKey, today);
      return;
    }

    final autoClockInEnabled = prefs.getBool(autoClockInEnabledKey) ?? false;
    final autoClockOutEnabled = prefs.getBool(autoClockOutEnabledKey) ?? false;
    final clockInHour = prefs.getInt(autoClockInHourKey) ?? defaultClockInHour;
    final clockInMinute = prefs.getInt(autoClockInMinuteKey) ?? defaultClockInMinute;
    final clockOutHour = prefs.getInt(autoClockOutHourKey) ?? defaultClockOutHour;
    final clockOutMinute = prefs.getInt(autoClockOutMinuteKey) ?? defaultClockOutMinute;

    final currentHour = now.hour;
    final currentMinute = now.minute;

    // Check if it's time to clock in
    if (autoClockInEnabled && 
        currentHour == clockInHour && 
        currentMinute == clockInMinute &&
        !(prefs.getBool('clockedIn_$today') ?? false)) {
      final success = await _triggerWebhook('clockIn');
      if (success) {
        debugPrint('AutoClockService: Auto clock-in triggered and marked at $clockInHour:$clockInMinute');
      }
    }

    // Check if it's time to clock out
    if (autoClockOutEnabled && 
        currentHour == clockOutHour && 
        currentMinute == clockOutMinute &&
        !(prefs.getBool('clockedOut_$today') ?? false)) {
      final success = await _triggerWebhook('clockOut');
      if (success) {
        debugPrint('AutoClockService: Auto clock-out triggered and marked at $clockOutHour:$clockOutMinute');
      }
    }
  }

  Future<bool> _triggerWebhook(String action) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final webhookUrl = prefs.getString('webhookUrl');
    
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint('AutoClockService: Webhook URL not configured');
      return false;
    }

    // Check if already clocked in/out today
    if (action == 'clockIn' && (prefs.getBool('clockedIn_$today') ?? false)) {
      debugPrint('AutoClockService: Already clocked in today');
      return false;
    }
    if (action == 'clockOut' && (prefs.getBool('clockedOut_$today') ?? false)) {
      debugPrint('AutoClockService: Already clocked out today');
      return false;
    }

    try {
      final now = DateTime.now();
      final formattedTime = DateFormat('HH:mm:ss').format(now);
      
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'timestamp': now.toIso8601String(),
          'source': 'auto_clock_service'
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 成功打卡後設置標記
        if (action == 'clockIn') {
          // 標記今天已經上班打卡
          await prefs.setBool('clockedIn_$today', true);
          await prefs.setString('clockInTime_$today', formattedTime);
          
          // 顯示通知
          await _showAutoClockNotification('clockIn', formattedTime);
          debugPrint('AutoClockService: ✅ Clock-in successful and marked at $formattedTime');
        } else {
          // 標記今天已經下班打卡
          await prefs.setBool('clockedOut_$today', true);
          await prefs.setString('clockOutTime_$today', formattedTime);
          
          // 顯示通知
          await _showAutoClockNotification('clockOut', formattedTime);
          debugPrint('AutoClockService: ✅ Clock-out successful and marked at $formattedTime');
        }
        return true;
      } else {
        debugPrint('AutoClockService: ❌ Webhook failed: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('AutoClockService: ❌ Error triggering webhook: $e');
      return false;
    }
  }

  // Save automatic clock time settings
  Future<void> saveAutoClockSettings({
    required bool clockInEnabled,
    required bool clockOutEnabled,
    required int clockInHour, 
    required int clockInMinute,
    required int clockOutHour,
    required int clockOutMinute,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoClockInEnabledKey, clockInEnabled);
    await prefs.setBool(autoClockOutEnabledKey, clockOutEnabled);
    await prefs.setInt(autoClockInHourKey, clockInHour);
    await prefs.setInt(autoClockInMinuteKey, clockInMinute);
    await prefs.setInt(autoClockOutHourKey, clockOutHour);
    await prefs.setInt(autoClockOutMinuteKey, clockOutMinute);
    
    debugPrint('AutoClockService: Settings saved - Clock-in ${clockInEnabled ? 'enabled' : 'disabled'} at $clockInHour:$clockInMinute, Clock-out ${clockOutEnabled ? 'enabled' : 'disabled'} at $clockOutHour:$clockOutMinute');
    
    // 更新背景任務的排程
    await _backgroundService.updateSchedules();
  }

  // Get automatic clock time settings
  Future<Map<String, dynamic>> getAutoClockSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'clockInEnabled': prefs.getBool(autoClockInEnabledKey) ?? false,
      'clockOutEnabled': prefs.getBool(autoClockOutEnabledKey) ?? false,
      'clockInHour': prefs.getInt(autoClockInHourKey) ?? defaultClockInHour,
      'clockInMinute': prefs.getInt(autoClockInMinuteKey) ?? defaultClockInMinute,
      'clockOutHour': prefs.getInt(autoClockOutHourKey) ?? defaultClockOutHour,
      'clockOutMinute': prefs.getInt(autoClockOutMinuteKey) ?? defaultClockOutMinute,
    };
  }
  
  // Force trigger auto-clock now (for testing or manual triggering)
  Future<void> forceClockNow(String action) async {
    if (action != 'clockIn' && action != 'clockOut') {
      debugPrint('AutoClockService: Invalid action: $action');
      return;
    }
    
    final success = await _triggerWebhook(action);
    if (success) {
      debugPrint('AutoClockService: Force $action triggered successfully');
    }
  }

  // 檢查目前的打卡狀態
  Future<void> _checkCurrentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    final clockedInToday = prefs.getBool('clockedIn_$today') ?? false;
    final clockedOutToday = prefs.getBool('clockedOut_$today') ?? false;
    final clockInTime = prefs.getString('clockInTime_$today');
    final clockOutTime = prefs.getString('clockOutTime_$today');
    
    debugPrint('AutoClockService: 檢查今日狀態 - 上班打卡: $clockedInToday (${clockInTime ?? '無時間'}), 下班打卡: $clockedOutToday (${clockOutTime ?? '無時間'})');
  }
} 