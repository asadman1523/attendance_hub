import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/weekend_tracker.dart';
import 'pages/auto_clock_settings_page.dart';
import 'pages/notification_settings_page.dart';
import 'services/auto_clock_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service
  await NotificationService().init();

  // Initialize auto clock service (which also initializes background service)
  await AutoClockService().init();

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '打卡神器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _clockedInToday = false;
  bool _clockedOutToday = false;
  String? _clockInTime;
  String? _clockOutTime;
  final NotificationService _notificationService = NotificationService();
  bool _isWorkday = true;
  bool _isBigWeekend = false;
  bool _autoClockInEnabled = false;
  bool _autoClockOutEnabled = false;
  String _weekday = '';
  bool _hasWebhook = false;
  String? _notificationInTime;
  String? _notificationOutTime;
  // Half-day leave state variables
  bool _morningHalfDayLeaveEnabled = false;
  bool _afternoonHalfDayLeaveEnabled = false;
  // 整天請假狀態
  bool _fullDayLeaveEnabled = false;

  @override
  void initState() {
    super.initState();
    // 註冊應用生命週期觀察者
    WidgetsBinding.instance.addObserver(this);
    
    // 直接調用初始化，不使用 Future
    _initAttendanceStatus();

    // Schedule notifications when the app starts
    _scheduleNotifications();
    
    // 添加定期刷新機制
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    
    // 取消註冊應用生命週期觀察者
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 當應用從背景返回前台時重新加載狀態
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed from background, reloading attendance status');
      
      // 重新載入打卡狀態
      _initAttendanceStatus();

    } else if (state == AppLifecycleState.paused) {
      debugPrint('App paused, stopping refresh timer');
    }
  }

  Future<void> _scheduleNotifications() async {
    await _notificationService.scheduleNotifications();
    _checkWorkdayStatus();
  }

  Future<void> _checkWorkdayStatus() async {
    final isWorkday = await WeekendTracker.isWorkday();
    final isBigWeekend = await WeekendTracker.isBigWeekendWeek();

    if (mounted) {
      setState(() {
        _isWorkday = isWorkday;
        _isBigWeekend = isBigWeekend;
      });
    }
  }

  Future<void> _initAttendanceStatus() async {
    // 嘗試重新加載 SharedPreferences
    final prefs = await SharedPreferences.getInstance()..reload();
    
    // 在某些平台上，我們需要強制重新載入數據
    try {
      // 檢查是否有 reload 方法可用（較新版本的 shared_preferences 支持）
      if (prefs.toString().contains('reload')) {
        // 使用反射調用 reload 方法，強制重新從存儲讀取
        await (prefs as dynamic).reload();
      }
    } catch (e) {
      debugPrint('無法重新載入 SharedPreferences: $e');
    }
    
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    
    // Get weekday information
    _setWeekday(now);

    await _checkWorkdayStatus();

    // Get auto-clock settings
    final autoClockSettings = await AutoClockService().getAutoClockSettings();
    
    // Get notification settings
    final notificationSettings = await _notificationService.getNotificationTimes();
    
    // Check webhook configuration
    final webhookUrl = prefs.getString('webhookUrl') ?? '';
    
    // Get half-day leave settings
    final morningHalfDayLeave = prefs.getBool('morningHalfDayLeave_$today') ?? false;
    final afternoonHalfDayLeave = prefs.getBool('afternoonHalfDayLeave_$today') ?? false;
    // 獲取整天請假設定
    final fullDayLeave = prefs.getBool('fullDayLeave_$today') ?? false;
    
    setState(() {
      _clockedInToday = prefs.getBool('clockedIn_$today') ?? false;
      _clockedOutToday = prefs.getBool('clockedOut_$today') ?? false;
      _clockInTime = prefs.getString('clockInTime_$today');
      _clockOutTime = prefs.getString('clockOutTime_$today');
      _autoClockInEnabled = autoClockSettings['clockInEnabled'];
      _autoClockOutEnabled = autoClockSettings['clockOutEnabled'];
      _hasWebhook = webhookUrl.isNotEmpty;
      _notificationInTime = '${notificationSettings['clockInHour'].toString().padLeft(2, '0')}:${notificationSettings['clockInMinute'].toString().padLeft(2, '0')}';
      _notificationOutTime = '${notificationSettings['clockOutHour'].toString().padLeft(2, '0')}:${notificationSettings['clockOutMinute'].toString().padLeft(2, '0')}';
      _morningHalfDayLeaveEnabled = morningHalfDayLeave;
      _afternoonHalfDayLeaveEnabled = afternoonHalfDayLeave;
      _fullDayLeaveEnabled = fullDayLeave;
    });
  }
  
  void _setWeekday(DateTime now) {
    const List<String> weekdays = ['週日', '週一', '週二', '週三', '週四', '週五', '週六'];
    setState(() {
      _weekday = weekdays[now.weekday % 7]; // weekday is 1-7, where 1 is Monday
    });
  }

  Future<void> _clockIn() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (_clockedInToday) {
      _showMessage('您今天已經打過上班卡了');
      return;
    }

    try {
      final webhookUrl = prefs.getString('webhookUrl') ?? '';
      if (webhookUrl.isEmpty) {
        _showMessage('請先在設置中配置打卡的 Webhook URL');
        return;
      }

      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'clockIn',
          'timestamp': DateTime.now().toIso8601String()
        }),
      );

      debugPrint('打卡請求：${response.request?.url}');
      debugPrint('打卡 statusCode：${response.statusCode}');
      debugPrint('打卡回應：${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateFormat('HH:mm:ss').format(DateTime.now());
        await prefs.setBool('clockedIn_$today', true);
        await prefs.setString('clockInTime_$today', now);

        setState(() {
          _clockedInToday = true;
          _clockInTime = now;
        });

        _showMessage('上班打卡成功');
      } else {
        debugPrint('打卡失敗：${response.body}');
        _showErrorDialog('上班打卡失敗', response.body);
      }
    } catch (e) {
      debugPrint('異常錯誤：$e');
      _showMessage('發生錯誤：$e');
    }
  }

  Future<void> _clockOut() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (_clockedOutToday) {
      _showMessage('您今天已經打過下班卡了');
      return;
    }

    try {
      final webhookUrl = prefs.getString('webhookUrl') ?? '';
      if (webhookUrl.isEmpty) {
        _showMessage('請先在設置中配置打卡的 Webhook URL');
        return;
      }

      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'clockOut',
          'timestamp': DateTime.now().toIso8601String()
        }),
      );

      debugPrint('打卡請求：${response.request?.url}');
      debugPrint('打卡 statusCode：${response.statusCode}');
      debugPrint('打卡回應：${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateFormat('HH:mm:ss').format(DateTime.now());
        await prefs.setBool('clockedOut_$today', true);
        await prefs.setString('clockOutTime_$today', now);

        setState(() {
          _clockedOutToday = true;
          _clockOutTime = now;
        });

        _showMessage('下班打卡成功');
      } else {
        debugPrint('打卡失敗：${response.body}');
        _showErrorDialog('下班打卡失敗', response.body);
      }
    } catch (e) {
      debugPrint('異常錯誤：$e');
      _showMessage('發生錯誤：$e');
    }
  }

  // 清除上班打卡記錄
  Future<void> _clearClockInRecord() async {
    // 顯示確認對話框
    final shouldClear = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清除上班打卡記錄'),
            content: const Text('確定要清除今天的上班打卡記錄嗎？此操作不可撤銷。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('清除'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 清除上班打卡記錄
    await prefs.remove('clockedIn_$today');
    await prefs.remove('clockInTime_$today');

    // 更新狀態
    setState(() {
      _clockedInToday = false;
      _clockInTime = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上班打卡記錄已清除')),
      );
    }
  }

  // 清除下班打卡記錄
  Future<void> _clearClockOutRecord() async {
    // 顯示確認對話框
    final shouldClear = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清除下班打卡記錄'),
            content: const Text('確定要清除今天的下班打卡記錄嗎？此操作不可撤銷。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('清除'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 清除下班打卡記錄
    await prefs.remove('clockedOut_$today');
    await prefs.remove('clockOutTime_$today');

    // 更新狀態
    setState(() {
      _clockedOutToday = false;
      _clockOutTime = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下班打卡記錄已清除')),
      );
    }
  }

  // Toggle full-day leave
  Future<void> _toggleFullDayLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // 檢查是否已啟用半天假
    if (!_fullDayLeaveEnabled && (_morningHalfDayLeaveEnabled || _afternoonHalfDayLeaveEnabled)) {
      _showMessage('不能同時啟用整天假和半天假');
      return;
    }
    
    final newValue = !_fullDayLeaveEnabled;
    
    // 提示用戶
    if (newValue) {
      _showMessage('已設定整天請假。今天所有自動打卡將暫停');
    } else {
      _showMessage('已取消整天請假設定');
    }
    
    await prefs.setBool('fullDayLeave_$today', newValue);
    
    setState(() {
      _fullDayLeaveEnabled = newValue;
    });
  }
  
  // Toggle morning half-day leave
  Future<void> _toggleMorningHalfDayLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now();
    
    // 檢查時間，只有在13:00前才能啟用上午請假
    if (now.hour >= 13 && !_morningHalfDayLeaveEnabled) {
      _showMessage('已超過上午請假的時間限制（限13:00前啟用）');
      return;
    }
    
    // 檢查是否已啟用整天假
    if (_fullDayLeaveEnabled && !_morningHalfDayLeaveEnabled) {
      _showMessage('不能同時啟用半天假和整天假');
      return;
    }
    
    // Cannot enable both types of half-day leave simultaneously
    if (_afternoonHalfDayLeaveEnabled && !_morningHalfDayLeaveEnabled) {
      _showMessage('不能同時啟用上午和下午請假');
      return;
    }
    
    final newValue = !_morningHalfDayLeaveEnabled;
    
    // 不再實際停用自動打卡，只顯示提示訊息
    if (newValue) {
      _showMessage('已設定上午請假（13:00打卡）。注意：上午請假當天，自動上班打卡將暫時失效');
    } else {
      _showMessage('已取消上午請假設定');
    }
    
    await prefs.setBool('morningHalfDayLeave_$today', newValue);
    
    setState(() {
      _morningHalfDayLeaveEnabled = newValue;
    });
  }
  
  // Toggle afternoon half-day leave
  Future<void> _toggleAfternoonHalfDayLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now();
    
    // 檢查時間，只有在13:31前才能啟用下午請假
    if ((now.hour > 13 || (now.hour == 13 && now.minute >= 31)) && !_afternoonHalfDayLeaveEnabled) {
      _showMessage('已超過下午請假的時間限制（限13:31前啟用）');
      return;
    }
    
    // 檢查是否已啟用整天假
    if (_fullDayLeaveEnabled && !_afternoonHalfDayLeaveEnabled) {
      _showMessage('不能同時啟用半天假和整天假');
      return;
    }
    
    // Cannot enable both types of half-day leave simultaneously
    if (_morningHalfDayLeaveEnabled && !_afternoonHalfDayLeaveEnabled) {
      _showMessage('不能同時啟用上午和下午請假');
      return;
    }
    
    final newValue = !_afternoonHalfDayLeaveEnabled;
    
    // 不再實際停用自動打卡，只顯示提示訊息
    if (newValue) {
      _showMessage('已設定下午請假（13:31打卡）。注意：下午請假當天，自動下班打卡將暫時失效');
    } else {
      _showMessage('已取消下午請假設定');
    }
    
    await prefs.setBool('afternoonHalfDayLeave_$today', newValue);
    
    setState(() {
      _afternoonHalfDayLeaveEnabled = newValue;
    });
  }
  

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showErrorDialog(String title, String errorDetails) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('發生以下錯誤:'),
                const SizedBox(height: 10),
                Text(errorDetails,
                    style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('關閉'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡神器'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                ).then((_) => _initAttendanceStatus());
              } else if (value == 'notifications') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const NotificationSettingsPage()),
                ).then((_) {
                  _scheduleNotifications();
                  _initAttendanceStatus(); // Refresh all status info
                });
              } else if (value == 'auto_clock') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AutoClockSettingsPage()),
                ).then((result) {
                  if (result == true) {
                    _initAttendanceStatus(); // 僅在設置變更時重新加載
                  }
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Webhook 設置'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'notifications',
                child: ListTile(
                  leading: Icon(Icons.notifications),
                  title: Text('提醒設置'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'auto_clock',
                child: ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('自動打卡設置'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  // 提取主內容為可重用的方法
  Widget _buildMainContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '今天：${DateFormat('yyyy年MM月dd日').format(DateTime.now())}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _weekday,
                          style: const TextStyle(
                            fontSize: 18, 
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _isWorkday ? Icons.work : Icons.weekend,
                          color: _isWorkday ? Colors.blue : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isWorkday ? '今天是工作日' : '今天是休息日',
                          style: TextStyle(
                            color: _isWorkday ? Colors.blue : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '本週為${_isBigWeekend ? '大' : '小'}週末 (${_isBigWeekend ? '週一、二休息' : '僅週一休息'})',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    // 自動打卡狀態資訊
                    Row(
                      children: [
                        Icon(
                          Icons.auto_mode,
                          color: (_autoClockInEnabled || _autoClockOutEnabled) 
                              ? Colors.green 
                              : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '自動打卡：${_getAutoClockStatusText()}',
                          style: TextStyle(
                            color: (_autoClockInEnabled || _autoClockOutEnabled) 
                                ? Colors.green 
                                : Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // 半天假打卡狀態資訊
                    Row(
                      children: [
                        Icon(
                          Icons.time_to_leave,
                          color: (_morningHalfDayLeaveEnabled || _afternoonHalfDayLeaveEnabled) 
                              ? Colors.orange 
                              : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '半天假：${_getHalfDayLeaveStatusText()}',
                          style: TextStyle(
                            color: (_morningHalfDayLeaveEnabled || _afternoonHalfDayLeaveEnabled) 
                                ? Colors.orange 
                                : Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // 提醒設置資訊
                    Row(
                      children: [
                        Icon(
                          Icons.notifications,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '提醒：上班 $_notificationInTime / 下班 $_notificationOutTime',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Webhook 狀態資訊
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          color: _hasWebhook ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Webhook：${_hasWebhook ? '已配置' : '未配置'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: _hasWebhook ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('上班打卡: ${_clockInTime ?? '尚未打卡'}'),
                        Row(
                          children: [
                            if (_clockedInToday)
                              GestureDetector(
                                onTap: _clearClockInRecord,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                ),
                              ),
                            const SizedBox(width: 4),
                            _clockedInToday
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : const Icon(Icons.pending, color: Colors.orange),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('下班打卡: ${_clockOutTime ?? '尚未打卡'}'),
                        Row(
                          children: [
                            if (_clockedOutToday)
                              GestureDetector(
                                onTap: _clearClockOutRecord,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                ),
                              ),
                            const SizedBox(width: 4),
                            _clockedOutToday
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : const Icon(Icons.pending, color: Colors.orange),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // 半天假設定區域
            if (_isWorkday) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '請假設定',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '啟用後將自動在特定時間打卡，且優先於一般自動打卡設定',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      if (_morningHalfDayLeaveEnabled || _afternoonHalfDayLeaveEnabled || _fullDayLeaveEnabled) ...[
                        const SizedBox(height: 6),
                        Text(
                          _fullDayLeaveEnabled 
                              ? '今天已設定整天請假，自動打卡已暫停' 
                              : (_morningHalfDayLeaveEnabled 
                                  ? '今天上班將於 13:00 自動打卡'
                                  : '今天下班將於 13:31 自動打卡'),
                          style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                      const SizedBox(height: 16),
                      
                      // 整天請假選項
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('整天請假', style: TextStyle(fontWeight: FontWeight.bold)),
                              Switch(
                                value: _fullDayLeaveEnabled,
                                onChanged: (_) => _toggleFullDayLeave(),
                                activeColor: Colors.red,
                              ),
                            ],
                          ),
                          const Text('暫停今天所有自動打卡', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          const Divider(),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      const Text(
                        '半天請假設定',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // 上午請假開關
                          Column(
                            children: [
                              const Text('上午請假'),
                              const SizedBox(height: 4),
                              Switch(
                                value: _morningHalfDayLeaveEnabled,
                                onChanged: _fullDayLeaveEnabled ? null : (_) => _toggleMorningHalfDayLeave(),
                                activeColor: Colors.orange,
                              ),
                              Text('13:00打卡', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          // 下午請假開關
                          Column(
                            children: [
                              const Text('下午請假'),
                              const SizedBox(height: 4),
                              Switch(
                                value: _afternoonHalfDayLeaveEnabled,
                                onChanged: _fullDayLeaveEnabled ? null : (_) => _toggleAfternoonHalfDayLeave(),
                                activeColor: Colors.orange,
                              ),
                              Text('13:31打卡', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            ElevatedButton.icon(
              onPressed: !_isWorkday || _clockedInToday ? null : _clockIn,
              icon: const Icon(Icons.login),
              label: const Text('上班打卡'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: !_isWorkday || _clockedOutToday ? null : _clockOut,
              icon: const Icon(Icons.logout),
              label: const Text('下班打卡'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
            // 添加清除按鈕區域
            if (_clockedInToday || _clockedOutToday) ...[
              const SizedBox(height: 24),
            ]
          ],
        ),
      ),
    );
  }
  
  // 取得自動打卡狀態文字
  String _getAutoClockStatusText() {
    String status = '';
    
    // 如果整天請假已啟用，直接返回相應信息
    if (_fullDayLeaveEnabled) {
      return '已暫停（整天請假）';
    }
    
    if (_autoClockInEnabled && _autoClockOutEnabled) {
      status = '上、下班均已啟用';
    } else if (_autoClockInEnabled) {
      status = '上班已啟用';
    } else if (_autoClockOutEnabled) {
      status = '下班已啟用';
    } else {
      status = '未啟用';
    }
    
    // 如果有半天假設定，附加提示訊息
    if (_morningHalfDayLeaveEnabled && _autoClockInEnabled) {
      status += ' (上班請假模式打卡)';
    } else if (_afternoonHalfDayLeaveEnabled && _autoClockOutEnabled) {
      status += ' (下班請假模式打卡)';
    }
    
    return status;
  }
  
  // 取得半天假狀態文字
  String _getHalfDayLeaveStatusText() {
    if (_fullDayLeaveEnabled) {
      return '整天請假';
    } else if (_morningHalfDayLeaveEnabled) {
      return '上午請假 (13:00打卡)';
    } else if (_afternoonHalfDayLeaveEnabled) {
      return '下午請假 (13:31打卡)';
    } else {
      return '未啟用';
    }
  }

  // 移除定期刷新，依賴 WorkManager 背景服務和手動刷新
  void _startPeriodicRefresh() {
    // 不再啟動定期刷新，改為依賴背景服務
    debugPrint('定期刷新已移除，依賴 WorkManager 背景服務');
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _webhookController = TextEditingController();
  bool _isLoading = true;
  String _originalWebhookUrl = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final webhookUrl = prefs.getString('webhookUrl') ?? '';
    setState(() {
      _webhookController.text = webhookUrl;
      _originalWebhookUrl = webhookUrl; // Store original URL
      _isLoading = false;
    });
  }

  // Modified _saveSettings to not pop navigator
  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final newWebhookUrl = _webhookController.text.trim();
    await prefs.setString('webhookUrl', newWebhookUrl);

    // Update original URL to new saved value
    _originalWebhookUrl = newWebhookUrl;

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設置已保存')),
      );
    }
  }

  // Handle back button press
  Future<bool> _onWillPop() async {
    final hasChanged = _webhookController.text.trim() != _originalWebhookUrl;
    if (!hasChanged) {
      return true; // Allow pop if no changes
    }

    // If there are changes, show a confirmation dialog
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的更動'),
        content: const Text('您的 Webhook URL 已被修改，是否要儲存變更？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // No
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Yes
            child: const Text('是'),
          ),
        ],
      ),
    );

    // If user dismissed the dialog, don't pop
    if (shouldSave == null) {
      return false;
    }

    if (shouldSave) {
      await _saveSettings();
    }

    return true; // Allow pop (either after saving or if user chose not to save)
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('設置'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Webhook URL 設置',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '請輸入用於打卡的 webhook URL',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _webhookController,
                        decoration: const InputDecoration(
                          labelText: 'Webhook URL',
                          border: OutlineInputBorder(),
                          hintText: 'https://example.com/webhook',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Microsoft Teams Webhook 設置說明',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              SizedBox(height: 12),
                              Text('1. 在 Microsoft Teams 中開啟「流程」(Workflows)'),
                              Text('2. 點選「新增流程」(Add a new workflow)'),
                              Text('3. 選擇「收到 webhook 要求時發佈在頻道中」'),
                              Text('4. 依照指引設置，完成後複製生成的 Webhook URL'),
                              Text('5. 將 URL 貼到上方輸入欄'),
                              SizedBox(height: 8),
                              Text(
                                '注意：打卡資訊將會發送到你設定的 Teams 頻道中',
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          await _saveSettings();
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('保存設置'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }
}
