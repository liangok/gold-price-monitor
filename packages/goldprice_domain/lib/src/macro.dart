/// 宏观因子与「买点评估」。
///
/// 设计原则（重要）：
///   1. **只给回测支持的东西打分。** 每个计分因子的符号与阈值都来自
///      analysis/factor_backtest.py 的实测结果，不靠直觉。
///   2. **不预测。** 没有任何模型能可靠预测短期金价。这里做的是把
///      「现在买入历史上是否相对有利」量化，帮用户决定**节奏**（要不要分批），
///      而不是替他决定「买还是不买」。
///   3. **没通过验证的因子降级为展示。** 展示项得分为 0，但仍列出原始值，
///      因为「国内比国际贵多少」这类信息本身对决策有用（是成本，不是信号）。
///
/// 回测结论（前向 60 个交易日，基准「随便哪天买」+3.49%）：
///   - 美债 2 年期近 20 日👇 大幅下行 +7.53%（+4.04pp）｜上行 −1.22pp → **单调、可用**
///   - 美元指数    走强 +1.07pp 但大幅走强 −0.55pp → **非单调，判为噪音**
///   - 国内金料价差 20 日支持、60 日反转 → **方向不一致，不可用**
library;

import 'dart:convert';

/// 盎司 → 克
const double kOunceToGram = 31.1034768;

class MacroSeries {
  final String name;
  final String date;
  final double value;

  /// 近 20 个交易日的百分比变动（汇率、指数类用它）
  final double? chg20Pct;

  /// 近 20 个交易日的**绝对**变动（收益率类用它，单位是百分点，×100 得 bp）
  final double? chg20Abs;

  final double? chg30Pct;

  const MacroSeries({
    required this.name,
    required this.date,
    required this.value,
    this.chg20Pct,
    this.chg20Abs,
    this.chg30Pct,
  });

  /// 近 20 日变动换算成基点（bp）。
  double? get chg20Bp => chg20Abs == null ? null : chg20Abs! * 100;

  factory MacroSeries.fromJson(Map<String, dynamic> json) {
    return MacroSeries(
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      chg20Pct: (json['chg20_pct'] as num?)?.toDouble(),
      chg20Abs: (json['chg20_abs'] as num?)?.toDouble(),
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
  MacroSeries? get us2y => series['us2y'];
  MacroSeries? get us10y => series['us10y'];

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

/// 一条判断依据。
///
/// [score] 为正表示「**现在买入**历史上相对更有利」。
/// [scored] 为 false 表示该项只展示、不计分（未通过回测）。
class BuyFactor {
  final String name;
  final String valueText;
  final int score;
  final String reason;
  final bool scored;

  const BuyFactor({
    required this.name,
    required this.valueText,
    required this.score,
    required this.reason,
    this.scored = true,
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

  /// 只累加**计分项**。
  int get total {
    int sum = 0;
    for (final BuyFactor f in factors) {
      if (f.scored) sum += f.score;
    }
    return sum;
  }

  int get scoredCount => factors.where((BuyFactor f) => f.scored).length;
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
BuyAssessment assessBuyPoint({
  required MacroSnapshot? macro,
  required double benchmarkClose,
  double? rsi,
  double? changePct,
  double? drawdown,
}) {
  final List<BuyFactor> factors = <BuyFactor>[];

  // ══════════════════════════════════════════════════════════════════
  // 计分因子（有回测支持）
  // ══════════════════════════════════════════════════════════════════

  // ── 1. 美债 2 年期近 20 日变动：唯一有明确、单调信号的宏观因子。
  //      收益率下行（降息预期）→ 金价前向收益显著高于基准。
  final double? y2Bp = macro?.us2y?.chg20Bp;
  if (y2Bp != null) {
    int score;
    String reason;
    if (y2Bp < -25) {
      score = 2;
      reason = '降息预期升温。回测中这种状态下金价前向 60 日 +7.53%（基准 +3.49%）';
    } else if (y2Bp < -8) {
      score = 1;
      reason = '收益率小幅下行，回测中略优于基准';
    } else if (y2Bp <= 8) {
      score = 0;
      reason = '收益率基本走平，回测中略差于基准但差异不大';
    } else if (y2Bp <= 25) {
      score = -1;
      reason = '加息预期升温，回测中前向收益低于基准';
    } else {
      score = -2;
      reason = '加息预期明显升温。回测中这种状态下金价前向 60 日仅 +2.79%（基准 +3.49%）';
    }
    factors.add(BuyFactor(
      name: '美债2年期（近20日）',
      valueText: (y2Bp >= 0 ? '+' : '') + y2Bp.toStringAsFixed(0) + 'bp',
      score: score,
      reason: reason,
    ));
  }

  // ── 2. 稀有恐慌信号：回测里另一类跑赢基准的情形
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

  // ══════════════════════════════════════════════════════════════════
  // 展示项（未通过回测，只给信息、不计分）
  // ══════════════════════════════════════════════════════════════════

  // ── 国内金料价差：是**成本**不是信号
  final double? intlCny = internationalGoldInCny(macro);
  if (intlCny != null && intlCny > 0) {
    final double diff = benchmarkClose - intlCny;
    factors.add(BuyFactor(
      name: '国内金料价差',
      valueText: (diff >= 0 ? '+' : '') + diff.toStringAsFixed(1) + ' 元/克',
      score: 0,
      scored: false,
      reason: diff >= 0
          ? '你现在为每克多付 ' +
              diff.toStringAsFixed(1) +
              ' 元（成本，非择时信号）'
          : '你现在比国际价每克少付 ' +
              (-diff).toStringAsFixed(1) +
              ' 元（成本，非择时信号）',
    ));
  }

  // ── 美元指数：回测非单调，判为噪音
  final double? dxyChg = macro?.dxy?.chg20Pct;
  if (dxyChg != null) {
    factors.add(BuyFactor(
      name: '美元指数（近20日）',
      valueText:
          (dxyChg >= 0 ? '+' : '') + (dxyChg * 100).toStringAsFixed(2) + '%',
      score: 0,
      scored: false,
      reason: '回测中信号非单调（走强 +1.07pp、大幅走强 −0.55pp），判为噪音，不计分',
    ));
  }

  // ── 人民币汇率：同样未通过验证
  final double? fxChg = macro?.usdcny?.chg20Pct;
  if (fxChg != null) {
    factors.add(BuyFactor(
      name: '人民币汇率（近20日）',
      valueText:
          (fxChg >= 0 ? '+' : '') + (fxChg * 100).toStringAsFixed(2) + '%',
      score: 0,
      scored: false,
      reason: '未单独验证，仅作背景（它主要通过换算影响国内金价）',
    ));
  }

  // ── 距 90 日高点：回撤类规则在回测中跑输基准
  if (drawdown != null) {
    factors.add(BuyFactor(
      name: '距90日高点',
      valueText: (drawdown * 100).toStringAsFixed(2) + '%',
      score: 0,
      scored: false,
      reason: '仅记录：回撤类规则在回测中跑输「随便哪天买」，不计分',
    ));
  }

  final int total = factors
      .where((BuyFactor f) => f.scored)
      .fold<int>(0, (int a, BuyFactor f) => a + f.score);

  String verdict;
  String advice;
  if (total >= 4) {
    verdict = '偏顺风';
    advice = '计分因子明显偏向买家。可按计划推进，但仍建议分批 —— 事件日波动会放大。';
  } else if (total >= 1) {
    verdict = '略偏顺风';
    advice = '计分因子略偏有利。按原计划分批买入即可，不必刻意等待。';
  } else if (total == 0) {
    verdict = '中性';
    advice = '没有明显信号。这种时候「等」和「买」的历史期望差别不大，按婚期节奏走就好。';
  } else if (total >= -3) {
    verdict = '略偏逆风';
    advice = '短期偏逆风（通常是加息预期升温）。婚期还早可以放慢节奏、多分几批；'
        '婚期临近则时间约束优先，别为了等而耽误事。';
  } else {
    verdict = '偏逆风';
    advice = '计分因子明显偏逆风。若时间允许可放缓节奏；但记住真正省钱的是渠道'
        '（水贝 / 金条打金），不是等价格。';
  }

  return BuyAssessment(factors: factors, verdict: verdict, advice: advice);
}
