import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知栏提醒服务。
///
/// 注意：Android 13 (API 33) 起，发通知需要运行时授权 POST_NOTIFICATIONS，
/// 必须先调用 [requestPermission]。
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'goldprice_alerts',
    '金价提醒',
    channelDescription: '策略触发时的买入提示',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        // 用单色矢量图，不能用彩色启动图标（否则状态栏会出现白方块）
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    _ready = true;
  }

  /// 请求通知权限（Android 13+）。返回是否已授权。
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<bool> hasPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled();
    return enabled ?? true;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}
