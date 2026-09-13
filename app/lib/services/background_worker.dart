import 'package:workmanager/workmanager.dart';

import 'alert_runner.dart';

const String kAlertTaskName = 'goldprice.alertCheck';
const String kAlertTaskUnique = 'goldprice.alertCheck.periodic';

/// WorkManager 后台任务入口。
///
/// 必须是**顶层函数**并且标注 vm:entry-point，否则 release 构建会被 tree-shake 掉，
/// 表现为「Debug 能跑、Release 收不到提醒」。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask(
    (String taskName, Map<String, dynamic>? inputData) async {
      try {
        await runAlertCheck(notify: true);
      } catch (_) {
        // 后台任务不要抛异常：抛出会被系统按失败处理并惩罚性降低调度频率
      }
      return true;
    },
  );
}

class BackgroundScheduler {
  static bool _initialized = false;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  /// 每 6 小时检查一次（Android WorkManager 的周期下限是 15 分钟）。
  ///
  /// 用 update 策略，重复注册不会重置计时、也不会叠加任务。
  static Future<void> enable() async {
    await _ensureInit();
    await Workmanager().registerPeriodicTask(
      kAlertTaskUnique,
      kAlertTaskName,
      frequency: const Duration(hours: 6),
      initialDelay: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> disable() async {
    await _ensureInit();
    await Workmanager().cancelByUniqueName(kAlertTaskUnique);
  }

  /// 查一下任务是否已排上（Android 有效，其它平台返回 null）。
  static Future<bool?> isScheduled() async {
    await _ensureInit();
    try {
      return await Workmanager().isScheduledByUniqueName(kAlertTaskUnique);
    } catch (_) {
      return null;
    }
  }
}
