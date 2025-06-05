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
- **智慧請假管理**：支援全日和半日請假功能
- 全日請假：自動跳過所有打卡操作
- 半日請假：根據請假時段智慧化處理打卡
- **即時狀態監控**：定期自動刷新出勤狀態，確保資料準確性

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

## 特別設定說明

### Android 通知配置說明

本應用使用 Flutter Local Notifications 套件 (19.2.1+) 來管理通知，由於較新版本的變更，需要一些特殊配置：

1. **Gradle 設定**：
- 使用 Java 11 兼容性 (coreLibraryDesugaringEnabled)
- `compileSdk` 設為 35
- `targetSdk` 設為 33 (Android 13) 以支援通知權限

2. **權限**：
- 通知權限 (POST_NOTIFICATIONS) - Android 13+
- 開機啟動 (RECEIVE_BOOT_COMPLETED) - 用於重啟後復原通知
- 精確鬧鐘 (SCHEDULE_EXACT_ALARM 或 USE_EXACT_ALARM)

3. **AndroidManifest.xml 設定**：
- 添加所需接收器來處理通知排程
- 配置 Activity 支持 `showWhenLocked` 和 `turnScreenOn`

4. **權限請求流程**：
- 應用啟動時會自動請求通知權限
- 對於 Android，還會在需要時請求精確鬧鐘權限

### Microsoft Teams Webhook 設置

1. 在 Microsoft Teams 中開啟「流程」(Workflows)
2. 點選「新增流程」(Add a new workflow)
3. 選擇「收到 webhook 要求時發佈在頻道中」
4. 依照指引設置，完成後複製生成的 Webhook URL
5. 在應用程式的設置頁面中貼上該 URL

## 如何使用

### 基本打卡功能

應用主頁顯示當日打卡狀態，包括：
- 當前日期與星期
- 上下班打卡時間
- 是否為工作日
- 大小週末狀態
- 通知和自動打卡設定狀態

### 提醒通知設置

可設定上下班打卡的提醒時間，系統會在指定時間發送通知。

### 自動打卡設置

可設定自動打卡時間，系統會在指定時間自動執行打卡操作。

### 大小週末設置

可手動設定當前是大週末還是小週末週期，或者讓系統自動追蹤交替週期。

### 請假管理功能

#### 全日請假
- 設定全日請假後，系統會自動跳過當日所有打卡操作
- 避免不必要的打卡提醒和自動打卡

#### 半日請假
- 支援上半日或下半日請假設定
- 系統會根據請假時段自動處理相應的打卡操作
- 智慧化判斷需要執行的打卡動作

### 狀態監控

應用會定期自動刷新出勤狀態，確保：
- 即時更新打卡記錄
- 同步請假狀態
- 維持資料準確性

## 技術實現

- **Flutter**：跨平台 UI 框架
- **SharedPreferences**：本地數據存儲
- **Flutter Local Notifications**：本地通知管理
- **Workmanager**：背景任務處理 (v0.6.0)
- **HTTP**：網絡請求處理

## 最新更新

### v1.1.0 更新內容

#### 🚀 新功能
- **智慧請假管理系統**：新增全日和半日請假功能，自動處理打卡邏輯
- **即時狀態監控**：實作定期自動刷新機制，確保出勤狀態即時更新

#### 🔧 技術改進
- **WorkManager 升級**：更新至 0.6.0 版本，提升背景任務穩定性
- **初始化優化**：改善 WorkManager 初始化流程，增強應用啟動可靠性

## 貢獻與開發

歡迎提交 Issue 和 PR 參與此專案的開發。

### 開發指南
1. Fork 此專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

## 授權

本專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 檔案

```
MIT License

Copyright (c) 2024 Attendance Hub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```