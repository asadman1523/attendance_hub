import 'package:flutter/material.dart';
import '../services/auto_clock_service.dart';

class AutoClockSettingsPage extends StatefulWidget {
  const AutoClockSettingsPage({super.key});

  @override
  State<AutoClockSettingsPage> createState() => _AutoClockSettingsPageState();
}

class _AutoClockSettingsPageState extends State<AutoClockSettingsPage> {
  final AutoClockService _autoClockService = AutoClockService();
  
  bool _isLoading = true;
  bool _clockInEnabled = false;
  bool _clockOutEnabled = false;
  TimeOfDay _clockInTime = const TimeOfDay(hour: 9, minute: 20);
  TimeOfDay _clockOutTime = const TimeOfDay(hour: 18, minute: 30);
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final settings = await _autoClockService.getAutoClockSettings();
    
    setState(() {
      _clockInEnabled = settings['clockInEnabled'];
      _clockOutEnabled = settings['clockOutEnabled'];
      _clockInTime = TimeOfDay(
        hour: settings['clockInHour'], 
        minute: settings['clockInMinute']
      );
      _clockOutTime = TimeOfDay(
        hour: settings['clockOutHour'], 
        minute: settings['clockOutMinute']
      );
      _isLoading = false;
    });
  }
  
  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });
    
    await _autoClockService.saveAutoClockSettings(
      clockInEnabled: _clockInEnabled,
      clockOutEnabled: _clockOutEnabled,
      clockInHour: _clockInTime.hour,
      clockInMinute: _clockInTime.minute,
      clockOutHour: _clockOutTime.hour,
      clockOutMinute: _clockOutTime.minute,
    );
    
    setState(() {
      _isLoading = false;
    });
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自動打卡設置已保存')),
      );
      Navigator.of(context).pop(true);
    }
  }
  
  Future<void> _selectClockInTime() async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: _clockInTime,
    );
    
    if (selectedTime != null) {
      setState(() {
        _clockInTime = selectedTime;
      });
    }
  }
  
  Future<void> _selectClockOutTime() async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: _clockOutTime,
    );
    
    if (selectedTime != null) {
      setState(() {
        _clockOutTime = selectedTime;
      });
    }
  }
  
  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自動打卡設置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '自動打卡設置',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '在指定時間自動發送打卡請求，即使應用程序未運行也能正常工作',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  
                  // 上班打卡設置
                  const Text(
                    '上班打卡',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('啟用自動上班打卡'),
                            value: _clockInEnabled,
                            onChanged: (value) {
                              setState(() {
                                _clockInEnabled = value;
                              });
                            },
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('上班打卡時間'),
                            trailing: Text(
                              _formatTimeOfDay(_clockInTime),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: _selectClockInTime,
                            enabled: _clockInEnabled,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 下班打卡設置
                  const Text(
                    '下班打卡',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('啟用自動下班打卡'),
                            value: _clockOutEnabled,
                            onChanged: (value) {
                              setState(() {
                                _clockOutEnabled = value;
                              });
                            },
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('下班打卡時間'),
                            trailing: Text(
                              _formatTimeOfDay(_clockOutTime),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: _selectClockOutTime,
                            enabled: _clockOutEnabled,
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
                            '注意事項:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text('• 自動打卡只會在工作日運行'),
                          const Text('• 需要設定正確的Webhook URL才能成功打卡'),
                          const Text('• 如果該時間點已經手動打過卡，系統將不會重複打卡'),
                          const Text('• 現在支持在後台運行，即使應用程序未開啟也能打卡'),
                          const Text('• 若清除今天的打卡記錄，到達設定時間時系統會重新自動打卡'),
                          const Text('• 自動打卡成功後會自動標記為今日已打卡，並發送通知提醒'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline, 
                                  color: Colors.blue, 
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '在某些裝置上，系統省電模式可能會限制後台任務。若要確保功能正常運行，請考慮將本應用加入電池優化白名單。',
                                    style: TextStyle(color: Colors.blue),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('保存設置'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 