import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  static const int retryClockInNotificationId = 202;
  static const int retryClockOutNotificationId = 203;
  
  // 通知插件
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Auto-clock timer (for in-app checking)
  Timer? _timer;

  // Background service for out-of-app execution
  final BackgroundService _backgroundService = BackgroundService();

  // Initialize the service
  Future<void> init() async {
    // Initialize notifications
    await _initializeNotifications();
    
    // Also setup the background service for when app is not running
    await _backgroundService.init();
    
    // 立即檢查一次打卡狀態（用於從背景返回時）
    _checkCurrentStatus();
  }
  
  // Initialize notifications
  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings, 
      iOS: iosSettings,
    );
    
    await _notificationsPlugin.initialize(initSettings);
    
    // 請求權限
    await _requestNotificationPermissions();
  }
  
  // 請求通知權限
  Future<bool> _requestNotificationPermissions() async {
    bool permissionsGranted = false;
    
    try {
      // iOS 權限
      if (Platform.isIOS) {
        permissionsGranted = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
      
      // Android 權限
      if (Platform.isAndroid) {
        final plugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
        if (plugin != null) {
          final arePermissionsGranted = await plugin.areNotificationsEnabled();
          if (!(arePermissionsGranted == true)) {
            permissionsGranted = await plugin.requestNotificationsPermission() ?? false;
          } else {
            permissionsGranted = true;
          }
        }
      }
    } catch (e) {
      debugPrint('AutoClockService: Error requesting notification permissions: $e');
      permissionsGranted = false;
    }
    
    return permissionsGranted;
  }

  // 顯示自動打卡通知
  Future<void> _showAutoClockNotification(String action, String time) async {
    // 確保有權限
    final hasPermission = await _requestNotificationPermissions();
    if (!hasPermission) {
      debugPrint('AutoClockService: No notification permission, cannot show notification');
      return;
    }
  
    // 通知設置
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'auto_clock_channel',
      '自動打卡通知',
      channelDescription: '自動打卡成功時發送的通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    
    // 根據動作類型顯示不同的通知
    if (action == 'clockIn') {
      await _notificationsPlugin.show(
        autoClockInNotificationId,
        '自動上班打卡成功',
        '系統已於 $time 自動完成上班打卡',
        notificationDetails,
      );
    } else if (action == 'clockOut') {
      await _notificationsPlugin.show(
        autoClockOutNotificationId,
        '自動下班打卡成功',
        '系統已於 $time 自動完成下班打卡',
        notificationDetails,
      );
    } else if (action == '上午請假打卡') {
      await _notificationsPlugin.show(
        autoClockInNotificationId,
        '上午請假打卡成功',
        '系統已於 $time 自動完成上午請假打卡 (13:00)',
        notificationDetails,
      );
    } else if (action == '下午請假打卡') {
      await _notificationsPlugin.show(
        autoClockOutNotificationId,
        '下午請假打卡成功',
        '系統已於 $time 自動完成下午請假打卡 (13:31)',
        notificationDetails,
      );
    }
  }

  // Stop periodic check
  void stopService() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> _triggerWebhook(String action, [String? customTimestamp]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final webhookUrl = prefs.getString('webhookUrl') ?? '';
      
      if (webhookUrl.isEmpty) {
        debugPrint('AutoClockService: No webhook URL configured, cannot trigger auto-clock');
        return false;
      }
      
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      // 構建請求體
      Map<String, dynamic> body;
      if (customTimestamp != null) {
        body = {
          'action': action,
          'timestamp': customTimestamp
        };
      } else {
        body = {
          'action': action,
          'timestamp': DateTime.now().toIso8601String()
        };
      }
      
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateFormat('HH:mm:ss').format(DateTime.now());
        
        // 更新打卡狀態
        if (action == 'clockIn') {
          await prefs.setBool('clockedIn_$today', true);
          if (customTimestamp == null) {
            await prefs.setString('clockInTime_$today', now);
          }
          
          // 顯示通知
          _showAutoClockNotification('clockIn', now);
        } else {
          await prefs.setBool('clockedOut_$today', true);
          if (customTimestamp == null) {
            await prefs.setString('clockOutTime_$today', now);
          }
          
          // 顯示通知
          _showAutoClockNotification('clockOut', now);
        }
        
        return true;
      } else {
        debugPrint('AutoClockService: Webhook call failed with status ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('AutoClockService: Error triggering webhook: $e');
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
    
    // 讀取基本設定，不再考慮半天假的狀態
    final clockInEnabled = prefs.getBool(autoClockInEnabledKey) ?? false;
    final clockOutEnabled = prefs.getBool(autoClockOutEnabledKey) ?? false;
    
    return {
      'clockInEnabled': clockInEnabled,
      'clockOutEnabled': clockOutEnabled,
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

  // Disable auto clock in (for half-day leave)
  Future<void> disableAutoClockIn() async {
    // 不再實際停用自動打卡設置
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool(autoClockInEnabledKey, false);
    debugPrint('AutoClockService: Auto clock-in will be overridden by half-day leave');
  }
  
  // Disable auto clock out (for half-day leave)
  Future<void> disableAutoClockOut() async {
    // 不再實際停用自動打卡設置
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool(autoClockOutEnabledKey, false);
    debugPrint('AutoClockService: Auto clock-out will be overridden by half-day leave');
  }

  // Check if clocking should be skipped due to half-day leave
  Future<bool> shouldSkipClockInDueToLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return prefs.getBool('morningHalfDayLeave_$today') ?? false;
  }
  
  Future<bool> shouldSkipClockOutDueToLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return prefs.getBool('afternoonHalfDayLeave_$today') ?? false;
  }
} 