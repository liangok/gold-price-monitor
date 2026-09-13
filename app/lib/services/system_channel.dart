import 'package:flutter/services.dart';

/// 与原生 MainActivity 的 MethodChannel 通信。
///
/// 只做三件事：查电池优化状态、打开应用详情页、打开自启动管理页。
/// 这是小米 HyperOS 上通知能否真正按时弹出的关键。
class SystemChannel {
  static const MethodChannel _channel =
      MethodChannel('com.liangaokai.goldprice/system');

  /// 是否已加入电池优化白名单。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final bool? value =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开本应用的系统详情页。
  static Future<bool> openAppSettings() => _invoke('openAppSettings');

  /// 请求忽略电池优化（会弹系统对话框）。
  static Future<bool> openBatteryOptimizationSettings() =>
      _invoke('openBatteryOptimizationSettings');

  /// 打开「自启动管理」页（各家 ROM 的私有页面）。
  static Future<bool> openAutostartSettings() => _invoke('openAutostartSettings');

  static Future<bool> _invoke(String method) async {
    try {
      final bool? value = await _channel.invokeMethod<bool>(method);
      return value ?? false;
    } catch (_) {
      return false;
    }
  }
}
