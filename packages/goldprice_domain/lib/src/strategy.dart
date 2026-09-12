/// 策略引擎 —— 提醒判定。
///
/// 阈值与优先级由 10 年真实数据回测确定（见 analysis/backtest_report.md）：
///   - 核心信号：绝对目标价、单日大跌、RSI 超卖
///   - 仅提示  ：回撤、均线（历史上跑输「随便哪天买」的基准）
///   - 不上线  ：历史分位（牛市里近 3 年触发 0 次）
library;

import 'indicators.dart';

enum AlertLevel { core, hint }

String formatPct(double? v) =>
    v == null ? 'n/a' : (v * 100).toStringAsFixed(2) + '%';

class AlertConfig {
  final double? targetPrice;
  final double dailyDropPct;
  final double rsiOversold;
  final double drawdownPct;
  final int maWindow;

  const AlertConfig({
    this.targetPrice,
    this.dailyDropPct = 2.0,
    this.rsiOversold = 30.0,
    this.drawdownPct = 8.0,
    this.maWindow = 60,
  });

  factory AlertConfig.fromJson(Map<String, dynamic> json) {
    final alerts = json['alerts'] as Map<String, dynamic>? ?? const {};
    return AlertConfig(
      targetPrice: (alerts['target_price'] as num?)?.toDouble(),
      dailyDropPct: (alerts['daily_drop_pct'] as num?)?.toDouble() ?? 2.0,
      rsiOversold: (alerts['rsi_oversold'] as num?)?.toDouble() ?? 30.0,
      drawdownPct: (alerts['drawdown_pct'] as num?)?.toDouble() ?? 8.0,
      maWindow: (alerts['ma_window'] as num?)?.toInt() ?? 60,
    );
  }
}

class AlertResult {
  final String name;
  final AlertLevel level;
  final bool triggered;
  final String detail;

  const AlertResult({
    required this.name,
    required this.level,
    required this.triggered,
    required this.detail,
  });
}

List<AlertResult> evaluateAlerts(IndicatorSnapshot ind, AlertConfig cfg) {
  final results = <AlertResult>[];

  final target = cfg.targetPrice;
  if (target == null) {
    results.add(const AlertResult(
      name: '绝对目标价',
      level: AlertLevel.core,
      triggered: false,
      detail: '未设置。牛市里分位和均线都会失效，建议设一个绝对价位当锚。',
    ));
  } else {
    results.add(AlertResult(
      name: '绝对目标价 <= ' + target.toStringAsFixed(0) + ' 元/克',
      level: AlertLevel.core,
      triggered: ind.close <= target,
      detail: '现价 ' + ind.close.toStringAsFixed(2) + ' 元/克',
    ));
  }

  final drop = cfg.dailyDropPct;
  final change = ind.changePct;
  results.add(AlertResult(
    name: '单日跌幅 >= ' + drop.toStringAsFixed(1) + '%',
    level: AlertLevel.core,
    triggered: change != null && change <= -drop / 100.0,
    detail: '今日 ' + formatPct(change) + '，10 年回测 20 日收益 +1.96%',
  ));

  final oversold = cfg.rsiOversold;
  final rsi = ind.rsi;
  results.add(AlertResult(
    name: 'RSI14 < ' + oversold.toStringAsFixed(0),
    level: AlertLevel.core,
    triggered: rsi != null && rsi < oversold,
    detail: '当前 ' +
        (rsi == null ? 'n/a' : rsi.toStringAsFixed(1)) +
        '，10 年回测 20 日收益 +3.02%（最优）',
  ));

  final ddThreshold = cfg.drawdownPct;
  final dd = ind.drawdown;
  results.add(AlertResult(
    name: '距 ' +
        ind.drawdownWindow.toString() +
        ' 日高点回撤 >= ' +
        ddThreshold.toStringAsFixed(0) +
        '%',
    level: AlertLevel.hint,
    triggered: dd != null && dd <= -ddThreshold / 100.0,
    detail: '当前 ' + formatPct(dd) + '，历史上跑输基准，仅供参考',
  ));

  final maValue = ind.ma(cfg.maWindow);
  results.add(AlertResult(
    name: '收盘 < MA' + cfg.maWindow.toString(),
    level: AlertLevel.hint,
    triggered: maValue != null && ind.close < maValue,
    detail: maValue == null
        ? 'n/a'
        : 'MA' +
            cfg.maWindow.toString() +
            ' = ' +
            maValue.toStringAsFixed(2) +
            '，历史上跑输基准',
  ));

  return results;
}

int triggeredCount(List<AlertResult> results) =>
    results.where((r) => r.triggered).length;
