import 'package:goldprice_domain/goldprice_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 提醒设置，存本机（不同设备可以不同），与仓库里的 config/user.json 解耦。
///
/// 默认只提醒「核心信号」（目标价 / 单日大跌 / RSI 超卖）——
/// 回测显示回撤与均线类规则在 2016-2026 样本里跑输「随便哪天买」，
/// 默认开启只会制造噪音，所以单独给一个开关，且默认关闭。
class AlertSettings {
  static const String _kEnabled = 'alerts_enabled';
  static const String _kTarget = 'alerts_target_price';
  static const String _kIncludeHint = 'alerts_include_hint';
  static const String _kDailyDrop = 'alerts_daily_drop_pct';
  static const String _kRsi = 'alerts_rsi_oversold';
  static const String _kDrawdown = 'alerts_drawdown_pct';
  static const String _kMaWindow = 'alerts_ma_window';

  final bool enabled;
  final double? targetPrice;
  final bool includeHint;
  final double dailyDropPct;
  final double rsiOversold;
  final double drawdownPct;
  final int maWindow;

  const AlertSettings({
    this.enabled = false,
    this.targetPrice,
    this.includeHint = false,
    this.dailyDropPct = 2.0,
    this.rsiOversold = 30.0,
    this.drawdownPct = 8.0,
    this.maWindow = 60,
  });

  AlertSettings copyWith({
    bool? enabled,
    double? targetPrice,
    bool clearTarget = false,
    bool? includeHint,
    double? dailyDropPct,
    double? rsiOversold,
    double? drawdownPct,
    int? maWindow,
  }) {
    return AlertSettings(
      enabled: enabled ?? this.enabled,
      targetPrice: clearTarget ? null : (targetPrice ?? this.targetPrice),
      includeHint: includeHint ?? this.includeHint,
      dailyDropPct: dailyDropPct ?? this.dailyDropPct,
      rsiOversold: rsiOversold ?? this.rsiOversold,
      drawdownPct: drawdownPct ?? this.drawdownPct,
      maWindow: maWindow ?? this.maWindow,
    );
  }

  AlertConfig toAlertConfig() {
    return AlertConfig(
      targetPrice: targetPrice,
      dailyDropPct: dailyDropPct,
      rsiOversold: rsiOversold,
      drawdownPct: drawdownPct,
      maWindow: maWindow,
    );
  }

  static Future<AlertSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AlertSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      targetPrice: prefs.getDouble(_kTarget),
      includeHint: prefs.getBool(_kIncludeHint) ?? false,
      dailyDropPct: prefs.getDouble(_kDailyDrop) ?? 2.0,
      rsiOversold: prefs.getDouble(_kRsi) ?? 30.0,
      drawdownPct: prefs.getDouble(_kDrawdown) ?? 8.0,
      maWindow: prefs.getInt(_kMaWindow) ?? 60,
    );
  }

  static Future<void> save(AlertSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setBool(_kIncludeHint, s.includeHint);
    await prefs.setDouble(_kDailyDrop, s.dailyDropPct);
    await prefs.setDouble(_kRsi, s.rsiOversold);
    await prefs.setDouble(_kDrawdown, s.drawdownPct);
    await prefs.setInt(_kMaWindow, s.maWindow);
    if (s.targetPrice == null) {
      await prefs.remove(_kTarget);
    } else {
      await prefs.setDouble(_kTarget, s.targetPrice!);
    }
  }

  /// 同一条规则在同一天只提醒一次，避免后台任务反复打扰。
  static Future<String?> lastNotified(String ruleKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('notified_' + ruleKey);
  }

  static Future<void> markNotified(String ruleKey, String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notified_' + ruleKey, date);
  }

  static Future<void> clearNotified() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((String k) => k.startsWith('notified_'));
    for (final k in keys.toList()) {
      await prefs.remove(k);
    }
  }
}
