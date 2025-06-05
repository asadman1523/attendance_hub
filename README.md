# 打卡神器 (Attendance Hub)

一款專為上下班打卡而設計的 Flutter 行動應用程式，支援自動打卡提醒、自動打卡功能，並可與 Microsoft Teams 整合。

## 主要功能

- **打卡記錄**：記錄每日上下班打卡時間
- **Microsoft Teams 整合**：透過 Webhook 將打卡記錄發送至 Teams 頻道
- **提醒通知**：設定上下班打卡提醒時間
- **自動打卡**：設定自動打卡功能，無須手動操作
- **大小週末追蹤**：支援大小週末交替的班表設定，自動計算休息日
  - 大週末：週一、二休息
  - 小週末：僅週一休息

## 系統需求

- iOS 12.0+ / Android 6.0+
- Flutter 3.0.0+
- Dart 2.17.0+

## 安裝與設置

1. 確保已安裝 Flutter 開發環境
2. 複製本專案
   ```
   git clone https://your-repository-url/attendance_hub.git
   ```
3. 安裝依賴套件
   ```
   flutter pub get
   ```
4. 執行專案
   ```
   flutter run
   ```

## 如何使用

### 基本打卡功能

應用主頁顯示當日打卡狀態，包括：
- 當前日期與星期
- 上下班打卡時間
- 是否為工作日
- 大小週末狀態

### Microsoft Teams Webhook 設置

1. 在 Microsoft Teams 中開啟「流程」(Workflows)
2. 點選「新增流程」(Add a new workflow)
3. 選擇「收到 webhook 要求時發佈在頻道中」
4. 依照指引設置，完成後複製生成的 Webhook URL
5. 在應用程式的設置頁面中貼上該 URL

### 提醒通知設置

可設定上下班打卡的提醒時間，系統會在指定時間發送通知。

### 自動打卡設置

可設定自動打卡時間，系統會在指定時間自動執行打卡操作。

### 大小週末設置

可手動設定當前是大週末還是小週末週期，或者讓系統自動追蹤交替週期。

## 技術實現

- **Flutter**：跨平台 UI 框架
- **SharedPreferences**：本地數據存儲
- **Flutter Local Notifications**：本地通知管理
- **Workmanager**：背景任務處理
- **HTTP**：網絡請求處理

## 貢獻與開發

歡迎提交 Issue 和 PR 參與此專案的開發。

## 授權

[添加您的授權資訊]
