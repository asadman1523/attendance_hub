# 保留圖像資源，特別是通知圖標
-keep class **.R$drawable {*;}
-keep class **.R$mipmap {*;}
-keep class **.R$raw {*;}

# 保持通知通道 ID 和相關常數
-keepclassmembers class ** {
    public static final String CHANNEL_ID;
    public static final int REQUEST_CODE;
    public static final int NOTIFICATION_ID;
}

# flutter_local_notifications 所需
-keep class com.dexterous.** { *; } 