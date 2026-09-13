import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:goldprice_domain/goldprice_domain.dart';

import '../config.dart';
import 'alert_settings.dart';
import 'notification_service.dart';

/// 通知 id 必须稳定（不能用 hashCode，跨进程会变），否则会重复弹通知。
const Map<String, int> kNotificationIds = <String, int>{
  'target_price': 1001,
  'daily_drop': 1002,
  'rsi': 1003,
  'drawdown': 1004,
  'ma': 1005,
};

class AlertCheckResult {
  final bool skipped;
  final String? skipReason;
  final double? close;
  final String? dataDate;
  final List<AlertResult> alerts;
  final List<String> notified;

  const AlertCheckResult({
    this.skipped = false,
    this.skipReason,
    this.close,
    this.dataDate,
    this.alerts = const <AlertResult>[],
    this.notified = const <String>[],
  });

  factory AlertCheckResult.skipped(String reason) =>
      AlertCheckResult(skipped: true, skipReason: reason);

  int get triggeredCount => alerts.where((AlertResult a) => a.triggered).length;
}

/// 用纯 HTTP 拉取，**刻意不使用离线快照**。
///
/// 提醒必须基于真实最新行情；如果拿打包快照去判定，可能因为数据陈旧而误报。
Future<String> _fetchText(List<String> urls) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  Object? lastError;
  try {
    for (final url in urls) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response =
            await request.close().timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          lastError = 'HTTP ' + response.statusCode.toString();
          continue;
        }
        return await response.transform(utf8.decoder).join();
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('拉取行情失败：' + lastError.toString());
}

/// 拉取行情 → 判定策略 →（可选）发通知。
///
/// [notify] 为 true 时会读设置、发通知并记录「今日已提醒」；
/// 为 false 时只是预览结果，不发通知、不改状态（供界面「立即检查」用）。
Future<AlertCheckResult> runAlertCheck({required bool notify}) async {
  final settings = await AlertSettings.load();
  if (notify && !settings.enabled) {
    return AlertCheckResult.skipped('提醒未开启');
  }

  final latest = LatestSnapshot.decode(
      await _fetchText(appRepoConfig.latestUrls));

  // 数据新鲜度保护：如果采集端已经好几天没更新（Actions 挂了、仓库没推），
  // 基于陈旧行情发提醒会误导用户，直接跳过。
  final generatedAt = DateTime.tryParse(latest.generatedAt);
  if (generatedAt != null) {
    final ageHours = DateTime.now().difference(generatedAt).inHours;
    if (ageHours > 72) {
      return AlertCheckResult.skipped(
          '数据已 ' + ageHours.toString() + ' 小时未更新，跳过提醒');
    }
  }

  final history = BenchmarkHistory.decode(
      await _fetchText(appRepoConfig.benchmarkHistoryUrls));

  final snapshot = computeLatest(history.closes, history.dates);
  if (snapshot == null) {
    return AlertCheckResult.skipped('历史数据不足，无法判定');
  }

  final alerts = evaluateAlerts(snapshot, settings.toAlertConfig());
  final fired = <String>[];

  for (final alert in alerts) {
    if (!alert.triggered) continue;
    // 回撤 / 均线属于「仅提示」，默认不发通知（回测里跑输基准，噪音大）
    if (alert.level == AlertLevel.hint && !settings.includeHint) continue;

    final today = snapshot.date;
    if (notify) {
      final last = await AlertSettings.lastNotified(alert.key);
      if (last == today) continue; // 同一规则同一天只提醒一次
      await NotificationService.show(
        id: kNotificationIds[alert.key] ?? 1099,
        title: '金价提醒 · ' + alert.name,
        body: alert.detail +
            '　大盘 ' +
            snapshot.close.toStringAsFixed(2) +
            ' 元/克',
      );
      await AlertSettings.markNotified(alert.key, today);
    }
    fired.add(alert.key);
  }

  return AlertCheckResult(
    close: snapshot.close,
    dataDate: snapshot.date,
    alerts: alerts,
    notified: fired,
  );
}
