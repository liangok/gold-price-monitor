/// 宏观因子与「买点评估」。
///
/// 设计原则（重要）：
///   1. **纯数值、无 AI、无黑箱。** 每条依据都展示原始值、判断阈值与得分。
///   2. **不预测。** 没有任何模型能可靠预测短期金价。这里做的是把
///      「现在贵不贵 / 顺风还是逆风」量化，帮用户决定**节奏**（要不要分批），
///      而不是替他决定「买还是不买」。
///   3. **只给回测支持的东西加分。** 回撤、均线在 2016-2026 都跑输基准，
///      因此不参与得分，只作为提示展示。
library;

import 'dart:convert';

/// 盎司 → 克
const double kOunceToGram = 31.1034768;

class MacroSeries {
  final String name;
  final String date;
  final double value;
  final double? chg20Pct;
  final double? chg30Pct;

  const MacroSeries({
    required this.name,
    required this.date,
    required this.value,
    this.chg20Pct,
    this.chg30Pct,
  });

  factory MacroSeries.fromJson(Map<String, dynamic> json) {
    return MacroSeries(
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      chg20Pct: (json['chg20_pct'] as num?)?.toDouble(),
      chg30Pct: (json['chg30_pct'] as num?)?.toDouble(),
    );
  }
}

/// data/macro.json
class MacroSnapshot {
  final String updatedAt;
  final Map<String, MacroSeries> series;

  const MacroSnapshot({required this.updatedAt, required this.series});

  MacroSeries? get goldSpot => series['gold_spot'];
  MacroSeries? get dxy => series['dxy'];
  MacroSeries? get usdcny => series['usdcny'];

  factory MacroSnapshot.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['series'];
    final Map<String, MacroSeries> parsed = <String, MacroSeries>{};
    if (raw is Map<String, dynamic>) {
      raw.forEach((String key, Object? value) {
        if (value is Map<String, dynamic>) {
          parsed[key] = MacroSeries.fromJson(value);
        }
      });
    }
    return MacroSnapshot(
      updatedAt: json['updated_at'] as String? ?? '',
      series: parsed,
    );
  }

  static MacroSnapshot decode(String source) {
    return MacroSnapshot.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}

/// 一条判断依据。分数为正表示「对买家更有利」。
class BuyFactor {
  final String name;
  final String valueText;
  final int score;
  final String reason;

  const BuyFactor({
    required this.name,
    required this.valueText,
    required this.score,
    required this.reason,
  });
}

class BuyAssessment {
  final List<BuyFactor> factors;
  final String verdict;
  final String advice;

  const BuyAssessment({
    required this.factors,
    required this.verdict,
    required this.advice,
  });

  int get total {
    int sum = 0;
    for (final BuyFactor f in factors) {
      sum += f.score;
    }
    return sum;
  }
}

/// 国际金价（伦敦金现）换算成人民币元/克。
double? internationalGoldInCny(MacroSnapshot? macro) {
  final MacroSeries? spot = macro?.goldSpot;
  final MacroSeries? fx = macro?.usdcny;
  if (spot == null || fx == null) return null;
  if (spot.value <= 0 || fx.value <= 0) return null;
  return spot.value * fx.value / kOunceToGram;
}

/// 评估当前买点。
///
/// [benchmarkClose] 上海金 Au99.99（元/克）；其余为技术指标。
BuyAssessment assessBuyPoint({
  required MacroSnapshot? macro,
  required double benchmarkClose,
  double? rsi,
  double? changePct,
  double? drawdown,
}) {
  final List<BuyFactor> factors = <BuyFactor>[];

  // ── 1. 国内金料价差：最贴近「现在买国内金，相对国际贵了多少」
  final double? intlCny = internationalGoldInCny(macro);
  if (intlCny != null && intlCny > 0) {
    final double diff = benchmarkClose - intlCny;
    int score;
    String reason;
    if (diff > 12) {
      score = -2;
      reason = '国内明显贵于国际，追高风险偏大';
    } else if (diff > 4) {
      score = -1;
      reason = '国内略贵于国际';
    } else if (diff >= -4) {
      score = 0;
      reason = '内外盘价格基本持平';
    } else if (diff >= -12) {
      score = 1;
      reason = '国内略低于国际，相对划算';
    } else {
      score = 2;
      reason = '国内明显低于国际';
    }
    factors.add(BuyFactor(
      name: '国内金料价差',
      valueText: (diff >= 0 ? '+' : '') + diff.toStringAsFixed(1) + ' 元/克',
      score: score,
      reason: reason,
    ));
  }

  // ── 2. 美元指数近 20 日：美元走强通常压制金价，对买家有利
  final double? dxyChg = macro?.dxy?.chg20Pct;
  if (dxyChg != null) {
    int score;
    String reason;
    if (dxyChg > 0.02) {
      score = 2;
      reason = '美元明显走强，历史上压制金价';
    } else if (dxyChg > 0.005) {
      score = 1;
      reason = '美元小幅走强';
    } else if (dxyChg >= -0.005) {
      score = 0;
      reason = '美元基本走平';
    } else if (dxyChg >= -0.02) {
      score = -1;
      reason = '美元小幅走弱，对金价偏支撑';
    } else {
      score = -2;
      reason = '美元明显走弱，金价易涨';
    }
    factors.add(BuyFactor(
      name: '美元指数（近20日）',
      valueText:
          (dxyChg >= 0 ? '+' : '') + (dxyChg * 100).toStringAsFixed(2) + '%',
      score: score,
      reason: reason,
    ));
  }

  // ── 3. 人民币近 20 日：人民币升值会让国内金价被动下降
  final double? fxChg = macro?.usdcny?.chg20Pct;
  if (fxChg != null) {
    int score;
    String reason;
    if (fxChg < -0.01) {
      score = 2;
      reason = '人民币明显升值，国内金价被动走低';
    } else if (fxChg < -0.003) {
      score = 1;
      reason = '人民币小幅升值';
    } else if (fxChg <= 0.003) {
      score = 0;
      reason = '汇率基本稳定';
    } else if (fxChg <= 0.01) {
      score = -1;
      reason = '人民币小幅贬值，推高国内金价';
    } else {
      score = -2;
      reason = '人民币明显贬值，国内金价被动上涨';
    }
    factors.add(BuyFactor(
      name: '人民币汇率（近20日）',
      valueText:
          (fxChg >= 0 ? '+' : '') + (fxChg * 100).toStringAsFixed(2) + '%',
      score: score,
      reason: reason,
    ));
  }

  // ── 4. 稀有恐慌信号：回测里**唯一**跑赢基准的两类
  int panicScore = 0;
  final List<String> panicNotes = <String>[];
  if (rsi != null && rsi < 30) {
    panicScore += 2;
    panicNotes.add('RSI ' + rsi.toStringAsFixed(1) + ' 超卖');
  }
  if (changePct != null && changePct <= -0.02) {
    panicScore += 2;
    panicNotes.add('单日跌 ' + (changePct * 100).toStringAsFixed(2) + '%');
  }
  factors.add(BuyFactor(
    name: '恐慌信号',
    valueText: panicNotes.isEmpty ? '无' : panicNotes.join('、'),
    score: panicScore,
    reason: panicNotes.isEmpty
        ? '未出现稀有买点信号（这是常态）'
        : '历史上这两类信号出现后 20 日收益跑赢基准',
  ));

  // ── 5. 回撤：只展示、不加分（回测跑输基准）
  if (drawdown != null) {
    factors.add(BuyFactor(
      name: '距90日高点',
      valueText: (drawdown * 100).toStringAsFixed(2) + '%',
      score: 0,
      reason: '仅记录：回撤类规则在回测中跑输「随便哪天买」，不计入得分',
    ));
  }

  final int total = factors.fold<int>(0, (int a, BuyFactor f) => a + f.score);
  String verdict;
  String advice;
  if (total >= 4) {
    verdict = '偏顺风';
    advice = '几个因子都偏向买家。可按计划推进，但仍建议分批 —— 遇到议息、CPI 这类事件日波动会明显放大。';
  } else if (total >= 1) {
    verdict = '略偏顺风';
    advice = '整体略偏有利。按原计划分批买入即可，不必刻意等待。';
  } else if (total == 0) {
    verdict = '中性';
    advice = '没有明显信号。这种时候「等」和「买」的期望差别不大，按婚期节奏走就好。';
  } else if (total >= -3) {
    verdict = '略偏逆风';
    advice = '短期偏贵或逆风。婚期还早可以放慢节奏；婚期临近则时间约束优先，别为了等而耽误事。';
  } else {
    verdict = '偏逆风';
    advice = '多个因子偏贵。若时间允许可放缓；但记住真正省钱的是渠道（水贝/金条打金），不是等价格。';
  }

  return BuyAssessment(factors: factors, verdict: verdict, advice: advice);
}
