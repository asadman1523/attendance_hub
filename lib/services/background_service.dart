import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../models/weekend_tracker.dart';

// 背景任務的唯一標識符
const clockInTaskName = "com.attendance_hub.clockInTask";
const clockOutTaskName = "com.attendance_hub.clockOutTask";
const clockInitializeTaskName = "com.attendance_hub.initializeTask";
const clockStatusCheckTaskName = "com.attendance_hub.clockStatusCheckTask";

// 特定時間點檢查任務標識符
const checkTimeTaskName = "com.attendance_hub.checkTimeTask";

// 自動打卡通知ID
const autoClockInNotificationId = 100;
const autoClockOutNotificationId = 101;
const retryClockInNotificationId = 102;
const retryClockOutNotificationId = 103;

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();

  factory BackgroundService() => _instance;

  BackgroundService._internal();

  // 初始化 AlarmManager 並註冊任務回調
  Future<void> init() async {
    await AndroidAlarmManager.initialize();

    // 啟動排程更新
    await updateSchedules();
  }

  // 重新設計的任務排程管理 - 使用 AlarmManager
  Future<void> updateSchedules() async {
    final prefs = await SharedPreferences.getInstance();

    // 取消所有現有任務
    await AndroidAlarmManager.cancel(1); // Clock In
    await AndroidAlarmManager.cancel(2); // Clock Out
    await AndroidAlarmManager.cancel(3); // Status Check
    
    // 獲取設置
    final clockInEnabled = prefs.getBool('autoClockInEnabled') ?? false;
    final clockOutEnabled = prefs.getBool('autoClockOutEnabled') ?? false;
    final clockInHour = prefs.getInt('autoClockInHour') ?? 9;
    final clockInMinute = prefs.getInt('autoClockInMinute') ?? 20;
    final clockOutHour = prefs.getInt('autoClockOutHour') ?? 18;
    final clockOutMinute = prefs.getInt('autoClockOutMinute') ?? 30;

    final now = DateTime.now();

    // 如果啟用自動打卡，安排下一次上班打卡
    if (clockInEnabled) {
      await _scheduleNextClockTask('clockIn', clockInHour, clockInMinute, now);
    }

    // 如果啟用自動打卡，安排下一次下班打卡
    if (clockOutEnabled) {
      await _scheduleNextClockTask('clockOut', clockOutHour, clockOutMinute, now);
    }

    // 安排下一次狀態檢查時間
    await _scheduleNextStatusCheck(now);
    
    debugPrint('BackgroundService: All schedules updated');
  }

  // 安排下一次打卡任務
  Future<void> _scheduleNextClockTask(String taskType, int hour, int minute, DateTime now) async {
    DateTime nextTime = DateTime(now.year, now.month, now.day, hour, minute);
    
    // 如果今天的時間已經過了，安排明天的
    if (now.isAfter(nextTime)) {
      nextTime = nextTime.add(const Duration(days: 1));
    }

    final alarmId = taskType == 'clockIn' ? 1 : 2;

    await AndroidAlarmManager.oneShotAt(
      nextTime,
      alarmId,
      alarmCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      params: {'taskType': taskType},
    );

    debugPrint('BackgroundService: Scheduled $taskType task at ${DateFormat('yyyy-MM-dd HH:mm').format(nextTime)}');
  }

  // 安排下一次狀態檢查時間 (9:25, 9:55, 13:00, 13:31, 18:31, 18:55)
  Future<void> _scheduleNextStatusCheck(DateTime now) async {
    final checkTimes = [
      {'hour': 9, 'minute': 25},   // 上班前檢查
      {'hour': 9, 'minute': 55},   // 上班後檢查
      {'hour': 13, 'minute': 0},   // 上午請假打卡
      {'hour': 13, 'minute': 31},  // 下午請假打卡
      {'hour': 18, 'minute': 31},  // 下班後檢查
      {'hour': 18, 'minute': 55},  // 晚間檢查
    ];

    DateTime? nextCheckTime;
    
    // 找到下一個檢查時間
    for (final timeMap in checkTimes) {
      final checkTime = DateTime(now.year, now.month, now.day, timeMap['hour']!, timeMap['minute']!);
      
      if (now.isBefore(checkTime)) {
        nextCheckTime = checkTime;
        break;
      }
    }

    // 如果今天沒有更多檢查時間，安排明天的第一個
    if (nextCheckTime == null) {
      nextCheckTime = DateTime(now.year, now.month, now.day + 1, checkTimes[0]['hour']!, checkTimes[0]['minute']!);
    }

    await AndroidAlarmManager.oneShotAt(
      nextCheckTime,
      3,
      alarmCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      params: {'taskType': 'statusCheck'},
    );

    debugPrint('BackgroundService: Scheduled next status check at ${DateFormat('yyyy-MM-dd HH:mm').format(nextCheckTime)}');
  }

  // 靜態方法 - 安排下一次打卡任務
  static Future<void> scheduleNextClockTaskStatic(String taskType, int hour, int minute, DateTime now) async {
    DateTime nextTime = DateTime(now.year, now.month, now.day, hour, minute);
    
    // 如果今天的時間已經過了，安排明天的
    if (now.isAfter(nextTime)) {
      nextTime = nextTime.add(const Duration(days: 1));
    }

    final alarmId = taskType == 'clockIn' ? 1 : 2;

    await AndroidAlarmManager.oneShotAt(
      nextTime,
      alarmId,
      alarmCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      params: {'taskType': taskType},
    );

    debugPrint('BackgroundTask: Scheduled $taskType task at ${DateFormat('yyyy-MM-dd HH:mm').format(nextTime)}');
  }

  // 靜態方法 - 安排下一次狀態檢查時間
  static Future<void> scheduleNextStatusCheckStatic(DateTime now) async {
    final checkTimes = [
      {'hour': 9, 'minute': 25},   // 上班前檢查
      {'hour': 9, 'minute': 55},   // 上班後檢查
      {'hour': 13, 'minute': 0},   // 上午請假打卡
      {'hour': 13, 'minute': 31},  // 下午請假打卡
      {'hour': 18, 'minute': 31},  // 下班後檢查
      {'hour': 18, 'minute': 55},  // 晚間檢查
    ];

    DateTime? nextCheckTime;
    
    // 找到下一個檢查時間
    for (final timeMap in checkTimes) {
      final checkTime = DateTime(now.year, now.month, now.day, timeMap['hour']!, timeMap['minute']!);
      
      if (now.isBefore(checkTime)) {
        nextCheckTime = checkTime;
        break;
      }
    }

    // 如果今天沒有更多檢查時間，安排明天的第一個
    nextCheckTime ??= DateTime(now.year, now.month, now.day + 1, checkTimes[0]['hour']!, checkTimes[0]['minute']!);

    await AndroidAlarmManager.oneShotAt(
      nextCheckTime,
      3,
      alarmCallback,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      wakeup: true,
      params: {'taskType': 'statusCheck'},
    );

    debugPrint('BackgroundTask: Scheduled next status check at ${DateFormat('yyyy-MM-dd HH:mm').format(nextCheckTime)}');
  }
}

// 顯示自動打卡通知
Future<void> _showAutoClockNotification(String action, String time) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 初始化設置
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();
  final InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

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
    await flutterLocalNotificationsPlugin.show(
      autoClockInNotificationId,
      '自動上班打卡成功',
      '系統已於 $time 自動完成上班打卡',
      notificationDetails,
    );
  } else {
    await flutterLocalNotificationsPlugin.show(
      autoClockOutNotificationId,
      '自動下班打卡成功',
      '系統已於 $time 自動完成下班打卡',
      notificationDetails,
    );
  }
}

// 顯示補救打卡通知
Future<void> _showRetryClockNotification(String action, String time) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 初始化設置
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();
  final InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // 通知設置
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'retry_clock_channel',
    '補救打卡通知',
    channelDescription: '補救打卡成功時發送的通知',
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
    await flutterLocalNotificationsPlugin.show(
      retryClockInNotificationId,
      '補救上班打卡成功',
      '系統已於 $time 自動完成補救上班打卡',
      notificationDetails,
    );
  } else {
    await flutterLocalNotificationsPlugin.show(
      retryClockOutNotificationId,
      '補救下班打卡成功',
      '系統已於 $time 自動完成補救下班打卡',
      notificationDetails,
    );
  }
}

// 執行每分鐘狀態檢查 (全局函數)
Future<bool> _performStatusCheck(String today, SharedPreferences prefs, [bool skipClocking = false]) async {
  try {
    final now = DateTime.now();

    // 檢查是否為工作日
    final isWorkday = await WeekendTracker.isWorkday();
    if (!isWorkday) {
      debugPrint(
          'BackgroundTask: Today is not a workday, skipping status check.');
      return true;
    }

    // 檢查是否啟用了整天請假
    final fullDayLeave = prefs.getBool('fullDayLeave_$today') ?? false;
    if (fullDayLeave) {
      debugPrint(
          'BackgroundTask: Full-day leave enabled, skipping status check.');
      return true;
    }

    // 獲取設置
    final autoClockInEnabled = prefs.getBool('autoClockInEnabled') ?? false;
    final autoClockOutEnabled = prefs.getBool('autoClockOutEnabled') ?? false;
    final clockInHour = prefs.getInt('autoClockInHour') ?? 9;
    final clockInMinute = prefs.getInt('autoClockInMinute') ?? 20;
    final clockOutHour = prefs.getInt('autoClockOutHour') ?? 18;
    final clockOutMinute = prefs.getInt('autoClockOutMinute') ?? 30;

    final currentHour = now.hour;
    final currentMinute = now.minute;

    // 檢查半天假設定
    final morningHalfDayLeave =
        prefs.getBool('morningHalfDayLeave_$today') ?? false;
    final afternoonHalfDayLeave =
        prefs.getBool('afternoonHalfDayLeave_$today') ?? false;

    // 處理上午請假的自動打卡 (13:00)
    if (morningHalfDayLeave &&
        currentHour == 13 &&
        currentMinute == 0 &&
        !(prefs.getBool('clockedIn_$today') ?? false)) {
      debugPrint('BackgroundTask: 執行上午請假自動打卡 (13:00)');
      await _performMorningHalfDayClocking(today, prefs);
      return true;
    }

    // 處理下午請假的自動打卡 (13:31)
    if (afternoonHalfDayLeave &&
        currentHour == 13 &&
        currentMinute == 31 &&
        !(prefs.getBool('clockedOut_$today') ?? false)) {
      debugPrint('BackgroundTask: 執行下午請假自動打卡 (13:31)');
      await _performAfternoonHalfDayClocking(today, prefs);
      return true;
    }

    // 獲取 webhook URL
    final webhookUrl = prefs.getString('webhookUrl');
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint('BackgroundTask: Webhook URL not configured');
      return true; // 不是錯誤，只是沒配置
    }

    // 如果需要跳過打卡檢查，直接返回
    if (skipClocking) {
      debugPrint('BackgroundTask: Skipping clocking checks in status check');
      return true;
    }

    // 檢查正常的上班打卡時間
    if (autoClockInEnabled &&
        currentHour == clockInHour &&
        currentMinute == clockInMinute &&
        !morningHalfDayLeave &&
        !(prefs.getBool('clockedIn_$today') ?? false)) {
      debugPrint('BackgroundTask: 執行定時上班打卡');
      await _performClocking(webhookUrl, 'clockIn', today, prefs);
      return true;
    }

    // 檢查正常的下班打卡時間
    if (autoClockOutEnabled &&
        currentHour == clockOutHour &&
        currentMinute == clockOutMinute &&
        !afternoonHalfDayLeave &&
        !(prefs.getBool('clockedOut_$today') ?? false)) {
      debugPrint('BackgroundTask: 執行定時下班打卡');
      await _performClocking(webhookUrl, 'clockOut', today, prefs);
      return true;
    }

    // 檢查是否需要補打卡
    await _checkAndPerformMissedClocking(
        webhookUrl,
        today,
        prefs,
        now,
        autoClockInEnabled,
        autoClockOutEnabled,
        clockInHour,
        clockInMinute,
        clockOutHour,
        clockOutMinute,
        morningHalfDayLeave,
        afternoonHalfDayLeave);

    return true;
  } catch (e) {
    debugPrint('BackgroundTask: Error in status check: $e');
    return false;
  }
}

// 執行上午請假打卡 (13:00) - 全局函數
Future<void> _performMorningHalfDayClocking(
    String today, SharedPreferences prefs) async {
  try {
    final webhookUrl = prefs.getString('webhookUrl');
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint(
          'BackgroundTask: Webhook URL not configured for morning half-day leave');
      return;
    }

    final response = await http.post(
      Uri.parse(webhookUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'clockIn',
        'timestamp': '$today 13:00:00',
        'source': 'morning_half_day_leave_status_check'
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await prefs.setBool('clockedIn_$today', true);
      await prefs.setString('clockInTime_$today', '13:00:00');
      debugPrint(
          'BackgroundTask: Morning half-day leave clock-in successful at 13:00:00');

      // 顯示通知
      await _showAutoClockNotification('clockIn', '13:00:00');
    }
  } catch (e) {
    debugPrint('BackgroundTask: Error in morning half-day leave clocking: $e');
  }
}

// 執行下午請假打卡 (13:31) - 全局函數
Future<void> _performAfternoonHalfDayClocking(
    String today, SharedPreferences prefs) async {
  try {
    final webhookUrl = prefs.getString('webhookUrl');
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint(
          'BackgroundTask: Webhook URL not configured for afternoon half-day leave');
      return;
    }

    final response = await http.post(
      Uri.parse(webhookUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'clockOut',
        'timestamp': '$today 13:31:00',
        'source': 'afternoon_half_day_leave_status_check'
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await prefs.setBool('clockedOut_$today', true);
      await prefs.setString('clockOutTime_$today', '13:31:00');
      debugPrint(
          'BackgroundTask: Afternoon half-day leave clock-out successful at 13:31:00');

      // 顯示通知
      await _showAutoClockNotification('clockOut', '13:31:00');
    }
  } catch (e) {
    debugPrint(
        'BackgroundTask: Error in afternoon half-day leave clocking: $e');
  }
}

// 檢查並執行補打卡 - 全局函數
Future<void> _checkAndPerformMissedClocking(
  String webhookUrl,
  String today,
  SharedPreferences prefs,
  DateTime now,
  bool autoClockInEnabled,
  bool autoClockOutEnabled,
  int clockInHour,
  int clockInMinute,
  int clockOutHour,
  int clockOutMinute,
  bool morningHalfDayLeave,
  bool afternoonHalfDayLeave,
) async {
  try {
    // 計算原定打卡時間
    final scheduledClockIn =
        DateTime(now.year, now.month, now.day, clockInHour, clockInMinute);
    final scheduledClockOut =
        DateTime(now.year, now.month, now.day, clockOutHour, clockOutMinute);

    // 檢查上班補打卡
    if (autoClockInEnabled &&
        !morningHalfDayLeave &&
        !(prefs.getBool('clockedIn_$today') ?? false) &&
        now.isAfter(scheduledClockIn)) {
      final timeDiff = now.difference(scheduledClockIn);
      if (timeDiff.inHours <= 3) {
        debugPrint('BackgroundTask: 檢測到錯過上班打卡，執行補打卡');
        final success =
            await _performClocking(webhookUrl, 'clockIn', today, prefs);
        if (success) {
          final formattedTime = DateFormat('HH:mm:ss').format(now);
          await _showRetryClockNotification('clockIn', formattedTime);
        }
      }
    }

    // 檢查下班補打卡
    if (autoClockOutEnabled &&
        !afternoonHalfDayLeave &&
        !(prefs.getBool('clockedOut_$today') ?? false) &&
        now.isAfter(scheduledClockOut)) {
      final timeDiff = now.difference(scheduledClockOut);
      if (timeDiff.inHours <= 3) {
        debugPrint('BackgroundTask: 檢測到錯過下班打卡，執行補打卡');
        final success =
            await _performClocking(webhookUrl, 'clockOut', today, prefs);
        if (success) {
          final formattedTime = DateFormat('HH:mm:ss').format(now);
          await _showRetryClockNotification('clockOut', formattedTime);
        }
      }
    }
  } catch (e) {
    debugPrint('BackgroundTask: Error in missed clocking check: $e');
  }
}

// 全局函數，作為 AlarmManager 的入口點
@pragma('vm:entry-point')
Future<void> alarmCallback(int alarmId, Map<String, dynamic> params) async {
  try {
    final taskType = params['taskType'] as String? ?? '';
    Logger().d('BackgroundTask: Alarm triggered with ID: $alarmId, type: $taskType');
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 檢查是否為工作日
    final isWorkday = await WeekendTracker.isWorkday();
    if (!isWorkday) {
      debugPrint('BackgroundTask: Today is not a workday, skipping auto-clock.');

      // 仍然需要重新排程下一天的打卡
      final taskType = params['taskType'] as String? ?? '';
      if (taskType == 'clockIn') {
        await BackgroundService.scheduleNextClockTaskStatic('clockIn',
            prefs.getInt('autoClockInHour') ?? 9,
            prefs.getInt('autoClockInMinute') ?? 20,
            DateTime.now());
      } else if (taskType == 'clockOut') {
        await BackgroundService.scheduleNextClockTaskStatic('clockOut',
            prefs.getInt('autoClockOutHour') ?? 18,
            prefs.getInt('autoClockOutMinute') ?? 30,
            DateTime.now());
      }
      return;
    }

    // 檢查是否啟用了整天請假
    final fullDayLeave = prefs.getBool('fullDayLeave_$today') ?? false;
    if (fullDayLeave) {
      debugPrint('BackgroundTask: Full-day leave enabled, skipping auto-clock.');
      
      // 仍然需要重新排程下一天的打卡
      final taskType = params['taskType'] as String? ?? '';
      if (taskType == 'clockIn') {
        await BackgroundService.scheduleNextClockTaskStatic('clockIn', 
          prefs.getInt('autoClockInHour') ?? 9, 
          prefs.getInt('autoClockInMinute') ?? 20, 
          DateTime.now());
      } else if (taskType == 'clockOut') {
        await BackgroundService.scheduleNextClockTaskStatic('clockOut', 
          prefs.getInt('autoClockOutHour') ?? 18, 
          prefs.getInt('autoClockOutMinute') ?? 30, 
          DateTime.now());
      }
      
      return;
    }

    // 獲取 webhook URL
    final webhookUrl = prefs.getString('webhookUrl');
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint('BackgroundTask: Webhook URL not configured');
      return;
    }

    // 根據任務類型執行相應操作
    switch (taskType) {
      case 'clockIn':
        // 檢查今天是否已經打卡
        if (prefs.getBool('clockedIn_$today') ?? false) {
          debugPrint('BackgroundTask: Already clocked in today');
        } else {
          // 執行上班打卡
          final success = await _performClocking(webhookUrl, 'clockIn', today, prefs);
          if (success) {
            debugPrint('BackgroundTask: clocked in success');
            // 設置一個標記，表示剛剛執行了打卡
            await prefs.setString('lastClockAction_$today', 'clockIn_${DateTime.now().millisecondsSinceEpoch}');
          }
        }
        
        // 無論成功與否，都安排下一次打卡
        await BackgroundService.scheduleNextClockTaskStatic('clockIn', 
          prefs.getInt('autoClockInHour') ?? 9, 
          prefs.getInt('autoClockInMinute') ?? 20, 
          DateTime.now());
        break;

      case 'clockOut':
        // 檢查今天是否已經打卡
        if (prefs.getBool('clockedOut_$today') ?? false) {
          debugPrint('BackgroundTask: Already clocked out today');
        } else {
          // 執行下班打卡
          final success = await _performClocking(
              webhookUrl, 'clockOut', today, prefs);
          if (success) {
            debugPrint('BackgroundTask: clocked out success');
            // 設置一個標記，表示剛剛執行了打卡
            await prefs.setString('lastClockAction_$today', 'clockOut_${DateTime
                .now()
                .millisecondsSinceEpoch}');
          }
        }

        // 無論成功與否，都安排下一次打卡
        await BackgroundService.scheduleNextClockTaskStatic('clockOut', 
          prefs.getInt('autoClockOutHour') ?? 18, 
          prefs.getInt('autoClockOutMinute') ?? 30, 
          DateTime.now());
        break;

      case 'statusCheck':
        // 檢查是否剛剛執行過打卡動作（防止重複打卡）
        final lastClockAction = prefs.getString('lastClockAction_$today') ?? '';
        final now = DateTime.now();
        
        // 如果在 2 分鐘內剛執行過打卡，跳過 status check 的打卡檢查
        bool skipClockingInStatusCheck = false;
        if (lastClockAction.isNotEmpty) {
          try {
            final actionParts = lastClockAction.split('_');
            if (actionParts.length >= 2) {
              final timestamp = int.parse(actionParts[1]);
              final timeDiff = now.millisecondsSinceEpoch - timestamp;
              if (timeDiff < 120000) { // 2 分鐘內
                skipClockingInStatusCheck = true;
                debugPrint('BackgroundTask: Skipping status check clocking - recent clock action detected');
                await BackgroundService.scheduleNextStatusCheckStatic(DateTime.now());
              }
            }
          } catch (e) {
            debugPrint('BackgroundTask: Error parsing last clock action: $e');
          }
        }
        
        final success = await _performStatusCheck(today, prefs, skipClockingInStatusCheck);
        
        // 檢查是否為當天最後一次檢查（18:55），如果是則關閉整天請假開關
        if (now.hour == 18 && now.minute == 55) {
          final fullDayLeave = prefs.getBool('fullDayLeave_$today') ?? false;
          if (fullDayLeave) {
            await prefs.setBool('fullDayLeave_$today', false);
            debugPrint('BackgroundTask: Auto-disabled full-day leave at end of day');
          }
        }
        
        // 安排下一次狀態檢查
        await BackgroundService.scheduleNextStatusCheckStatic(DateTime.now());
        break;

      default:
        debugPrint('BackgroundTask: Unknown task type: $taskType');
    }
  } catch (e) {
    debugPrint('BackgroundTask: Error executing alarm: $e');
  }
}

Future<bool> _performClocking(String webhookUrl, String action, String today,
    SharedPreferences prefs) async {
  try {
    final now = DateTime.now();

    // 檢查半天假設定
    final morningHalfDayLeave =
        prefs.getBool('morningHalfDayLeave_$today') ?? false;
    final afternoonHalfDayLeave =
        prefs.getBool('afternoonHalfDayLeave_$today') ?? false;

    // 如果是上班打卡且設置了上午請假，則跳過
    if (action == 'clockIn' && morningHalfDayLeave) {
      debugPrint(
          'BackgroundTask: Morning half-day leave enabled, skipping auto clock-in.');
      return true; // 返回成功，但不執行打卡
    }

    // 如果是下班打卡且設置了下午請假，則跳過
    if (action == 'clockOut' && afternoonHalfDayLeave) {
      debugPrint(
          'BackgroundTask: Afternoon half-day leave enabled, skipping auto clock-out.');
      return true; // 返回成功，但不執行打卡
    }

    final formattedTime = DateFormat('HH:mm:ss').format(now);

    final response = await http.post(
      Uri.parse(webhookUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'timestamp': now.toIso8601String(),
        'source': 'background_service'
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 成功打卡，設置標記
      if (action == 'clockIn') {
        // 標記今天已經上班打卡
        await prefs.setBool('clockedIn_$today', true);
        await prefs.setString('clockInTime_$today', formattedTime);
        debugPrint('BackgroundTask: Clock-in successful at $formattedTime');

        // 初始化通知插件
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();

        // 初始化設置
        const AndroidInitializationSettings androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        final DarwinInitializationSettings iosSettings =
            DarwinInitializationSettings();
        final InitializationSettings initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );

        await flutterLocalNotificationsPlugin.initialize(initSettings);

        // 顯示通知
        await _showAutoClockNotification(action, formattedTime);
      } else {
        // 標記今天已經下班打卡
        await prefs.setBool('clockedOut_$today', true);
        await prefs.setString('clockOutTime_$today', formattedTime);
        debugPrint('BackgroundTask: Clock-out successful at $formattedTime');

        // 初始化通知插件
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();

        // 初始化設置
        const AndroidInitializationSettings androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        final DarwinInitializationSettings iosSettings =
            DarwinInitializationSettings();
        final InitializationSettings initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );

        await flutterLocalNotificationsPlugin.initialize(initSettings);

        // 顯示通知
        await _showAutoClockNotification(action, formattedTime);
      }
      return true;
    } else {
      debugPrint('BackgroundTask: Webhook failed: ${response.body}');
      return false;
    }
  } catch (e) {
    debugPrint('BackgroundTask: Error triggering webhook: $e');
    return false;
  }
}
