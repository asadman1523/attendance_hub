import 'dart:convert';

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
  late Future<void> _initFuture;
  final NotificationService _notificationService = NotificationService();
  bool _isWorkday = true;
  bool _isBigWeekend = false;

  @override
  void initState() {
    super.initState();
    // 註冊應用生命週期觀察者
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _initAttendanceStatus();

    // Schedule notifications when the app starts
    _scheduleNotifications();
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
      setState(() {
        // 使用新的Future更新_initFuture
        _initFuture = _initAttendanceStatus();
      });
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
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    await _checkWorkdayStatus();

    setState(() {
      _clockedInToday = prefs.getBool('clockedIn_$today') ?? false;
      _clockedOutToday = prefs.getBool('clockedOut_$today') ?? false;
      _clockInTime = prefs.getString('clockInTime_$today');
      _clockOutTime = prefs.getString('clockOutTime_$today');
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
                ).then((_) => _scheduleNotifications());
              } else if (value == 'auto_clock') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AutoClockSettingsPage()),
                );
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
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snapshot) {
          // 當正在加載時顯示加載指示器，但保持UI結構
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Stack(
              children: [
                // 顯示上次加載的數據（如有）
                _buildMainContent(),
                // 半透明加載層
                Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              ],
            );
          }

          return _buildMainContent();
        },
      ),
    );
  }

  // 提取主內容為可重用的方法
  Widget _buildMainContent() {
    return Padding(
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
                  Text(
                    '今天：${DateFormat('yyyy年MM月dd日').format(DateTime.now())}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 32),
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
            // const Divider(),
            // const SizedBox(height: 8),
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            //   children: [
            //     if (_clockedInToday)
            //       ElevatedButton.icon(
            //         onPressed: _clearClockInRecord,
            //         icon: const Icon(Icons.delete),
            //         label: const Text('清除上班打卡'),
            //         style: ElevatedButton.styleFrom(
            //           backgroundColor: Colors.red.shade50,
            //           foregroundColor: Colors.red,
            //         ),
            //       ),
            //     if (_clockedOutToday)
            //       ElevatedButton.icon(
            //         onPressed: _clearClockOutRecord,
            //         icon: const Icon(Icons.delete),
            //         label: const Text('清除下班打卡'),
            //         style: ElevatedButton.styleFrom(
            //           backgroundColor: Colors.red.shade50,
            //           foregroundColor: Colors.red,
            //         ),
            //       ),
            //   ],
            // ),
          ]
        ],
      ),
    );
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
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhookUrl', _webhookController.text.trim());

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Webhook URL 設置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  ElevatedButton(
                    onPressed: _saveSettings,
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
    );
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }
}
