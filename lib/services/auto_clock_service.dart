import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Auto-clock timer (for in-app checking)
  Timer? _timer;
  bool _isRunning = false;
  
  // Background service for out-of-app execution
  final BackgroundService _backgroundService = BackgroundService();

  // Initialize the service
  Future<void> init() async {
    // Start the in-app timer
    _startPeriodicCheck();
    
    // Also setup the background service for when app is not running
    await _backgroundService.init();
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
    final lastCheckedDate = prefs.getString(lastCheckedDateKey) ?? '';

    // Check if we already processed today's clock events
    if (lastCheckedDate == today) {
      return;
    }

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
      await _triggerWebhook('clockIn');
      debugPrint('AutoClockService: Auto clock-in triggered at $clockInHour:$clockInMinute');
    }

    // Check if it's time to clock out
    if (autoClockOutEnabled && 
        currentHour == clockOutHour && 
        currentMinute == clockOutMinute &&
        !(prefs.getBool('clockedOut_$today') ?? false)) {
      await _triggerWebhook('clockOut');
      debugPrint('AutoClockService: Auto clock-out triggered at $clockOutHour:$clockOutMinute');
    }

    // Update the last checked date if both times have passed for today
    final bothTimesPassed = (currentHour > clockOutHour || 
                          (currentHour == clockOutHour && currentMinute >= clockOutMinute));
    if (bothTimesPassed) {
      await prefs.setString(lastCheckedDateKey, today);
    }
  }

  Future<void> _triggerWebhook(String action) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final webhookUrl = prefs.getString('webhookUrl');
    
    if (webhookUrl == null || webhookUrl.isEmpty) {
      debugPrint('AutoClockService: Webhook URL not configured');
      return;
    }

    // Check if already clocked in/out today
    if (action == 'clockIn' && (prefs.getBool('clockedIn_$today') ?? false)) {
      debugPrint('AutoClockService: Already clocked in today');
      return;
    }
    if (action == 'clockOut' && (prefs.getBool('clockedOut_$today') ?? false)) {
      debugPrint('AutoClockService: Already clocked out today');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'auto_clock_service'
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateFormat('HH:mm:ss').format(DateTime.now());
        if (action == 'clockIn') {
          await prefs.setBool('clockedIn_$today', true);
          await prefs.setString('clockInTime_$today', now);
          debugPrint('AutoClockService: Clock-in successful');
        } else {
          await prefs.setBool('clockedOut_$today', true);
          await prefs.setString('clockOutTime_$today', now);
          debugPrint('AutoClockService: Clock-out successful');
        }
      } else {
        debugPrint('AutoClockService: Webhook failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('AutoClockService: Error triggering webhook: $e');
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
    
    await _triggerWebhook(action);
  }
} 