import 'package:flutter/material.dart';

import '../models/weekend_tracker.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _isLoading = true;
  bool _isBigWeekend = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final isBigWeekend = await WeekendTracker.isBigWeekendWeek();

    setState(() {
      _isBigWeekend = isBigWeekend;
      _isLoading = false;
    });
  }

  Future<void> _resetWeekendTracking() async {
    await WeekendTracker.resetWeekendTracking();
    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置週末追蹤設置')),
      );
    }
  }

  Future<void> _setBigWeekend() async {
    await WeekendTracker.setManualWeekendMode(true);
    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已將本週設為大週末（週一、二休息）')),
      );
    }
  }

  Future<void> _setSmallWeekend() async {
    await WeekendTracker.setManualWeekendMode(false);
    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已將本週設為小週末（僅週一休息）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('週末設置'),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
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
                ],
              ),
            ),
          ),
    );
  }
}
