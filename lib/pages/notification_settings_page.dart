import 'package:flutter/material.dart';

import '../models/weekend_tracker.dart';
import '../services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;
  bool _isBigWeekend = false;
  
  late int _clockInHour;
  late int _clockInMinute;
  late int _clockOutHour;
  late int _clockOutMinute;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _notificationService.getNotificationTimes();
    final isBigWeekend = await WeekendTracker.isBigWeekendWeek();
    
    setState(() {
      _clockInHour = settings['clockInHour']!;
      _clockInMinute = settings['clockInMinute']!;
      _clockOutHour = settings['clockOutHour']!;
      _clockOutMinute = settings['clockOutMinute']!;
      _isBigWeekend = isBigWeekend;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    await _notificationService.saveNotificationTimes(
      clockInHour: _clockInHour,
      clockInMinute: _clockInMinute,
      clockOutHour: _clockOutHour,
      clockOutMinute: _clockOutMinute,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知設置已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectClockInTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _clockInHour, minute: _clockInMinute),
    );
    if (picked != null) {
      setState(() {
        _clockInHour = picked.hour;
        _clockInMinute = picked.minute;
      });
    }
  }

  Future<void> _selectClockOutTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _clockOutHour, minute: _clockOutMinute),
    );
    if (picked != null) {
      setState(() {
        _clockOutHour = picked.hour;
        _clockOutMinute = picked.minute;
      });
    }
  }
  
  Future<void> _markBigWeekend() async {
    await WeekendTracker.markBigWeekend();
    await _loadSettings();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已將目前設置為大週末週期起點')),
    );
  }
  
  Future<void> _resetWeekendTracking() async {
    await WeekendTracker.resetWeekendTracking();
    await _loadSettings();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已重置週末追蹤設置')),
    );
  }

  Future<void> _setBigWeekend() async {
    await WeekendTracker.setManualWeekendMode(true);
    await _loadSettings();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已將本週設為大週末（週一、二休息）')),
    );
  }
  
  Future<void> _setSmallWeekend() async {
    await WeekendTracker.setManualWeekendMode(false);
    await _loadSettings();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已將本週設為小週末（僅週一休息）')),
    );
  }

  String _formatTime(int hour, int minute) {
    final hourString = hour.toString().padLeft(2, '0');
    final minuteString = minute.toString().padLeft(2, '0');
    return '$hourString:$minuteString';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設置'),
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
                      '提醒時間設置',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '設定上下班打卡提醒的時間',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.login),
                              title: const Text('上班提醒時間'),
                              subtitle: Text(_formatTime(_clockInHour, _clockInMinute)),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: _selectClockInTime,
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.logout),
                              title: const Text('下班提醒時間'),
                              subtitle: Text(_formatTime(_clockOutHour, _clockOutMinute)),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: _selectClockOutTime,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '週末設置',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('目前為${_isBigWeekend ? '大' : '小'}週末週期 (${_isBigWeekend ? '週一、二休息' : '僅週一休息'})'),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _setBigWeekend,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isBigWeekend ? Colors.blue.shade800 : null,
                                    foregroundColor: _isBigWeekend ? Colors.white : null,
                                  ),
                                  child: const Text('大週末'),
                                ),
                                ElevatedButton(
                                  onPressed: _setSmallWeekend,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: !_isBigWeekend ? Colors.blue.shade800 : null,
                                    foregroundColor: !_isBigWeekend ? Colors.white : null,
                                  ),
                                  child: const Text('小週末'),
                                ),
                                TextButton(
                                  onPressed: _resetWeekendTracking,
                                  child: const Text('重置週末設置'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '注意事項',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text('• 星期一永遠是休息日，不會發送提醒'),
                            Text('• 大周末時，星期一和星期二都是休息日'),
                            Text('• 小周末時，只有星期一是休息日'),
                            Text('• 大小周末交替進行'),
                          ],
                        ),
                      ),
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
            ),
    );
  }
} 