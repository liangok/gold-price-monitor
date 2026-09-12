/// 渠道对比与预算计算 —— 本项目的第一价值。
///
/// 回测结论：择时收益只有几个百分点，而「品牌店 vs 水贝 / 银行金条打金」
/// 的差价约 40%。所以首页必须先展示渠道差异，再展示提醒。
library;

class ChannelAssumption {
  final double benchmarkMarkup;
  final double laborPerGram;

  const ChannelAssumption({
    this.benchmarkMarkup = 0,
    this.laborPerGram = 0,
  });

  factory ChannelAssumption.fromJson(Map<String, dynamic> json) {
    return ChannelAssumption(
      benchmarkMarkup: (json['benchmark_markup'] as num?)?.toDouble() ?? 0,
      laborPerGram: (json['labor_per_gram'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ChannelConfig {
  final double budgetCny;
  final double targetGrams;
  final ChannelAssumption brandStore;
  final ChannelAssumption shuibei;
  final ChannelAssumption bankBarDiy;

  const ChannelConfig({
    required this.budgetCny,
    required this.targetGrams,
    required this.brandStore,
    required this.shuibei,
    required this.bankBarDiy,
  });

  factory ChannelConfig.fromJson(Map<String, dynamic> json) {
    final ch = json['channel_assumptions'] as Map<String, dynamic>? ?? const {};
    ChannelAssumption pick(String key) {
      final raw = ch[key];
      if (raw is! Map<String, dynamic>) return const ChannelAssumption();
      return ChannelAssumption.fromJson(raw);
    }

    return ChannelConfig(
      budgetCny: (json['budget_cny'] as num?)?.toDouble() ?? 75000,
      targetGrams: (json['target_grams'] as num?)?.toDouble() ?? 55,
      brandStore: pick('brand_store'),
      shuibei: pick('shuibei'),
      bankBarDiy: pick('bank_bar_diy'),
    );
  }
}

class ChannelQuote {
  final String name;
  final double costPerGram;
  final double totalForTarget;
  final double gramsForBudget;
  final bool isBest;

  const ChannelQuote({
    required this.name,
    required this.costPerGram,
    required this.totalForTarget,
    required this.gramsForBudget,
    required this.isBest,
  });
}

class ChannelComparison {
  final List<ChannelQuote> quotes;
  final ChannelQuote best;
  final ChannelQuote worst;
  final double savings;
  final double savingsPct;

  const ChannelComparison({
    required this.quotes,
    required this.best,
    required this.worst,
    required this.savings,
    required this.savingsPct,
  });
}

/// 用当日大盘价与品牌最低价，算出各渠道的克价与可买克重。
ChannelComparison compareChannels({
  required double benchmarkClose,
  required String brandName,
  required double brandGold,
  required ChannelConfig config,
  double? bankBarPrice,
}) {
  // 银行金条优先使用实时报价（数据来自采集器）；拿不到才回退到「大盘 + 假设加点」。
  final bankBase =
      bankBarPrice ?? (benchmarkClose + config.bankBarDiy.benchmarkMarkup);
  final raw = <String, double>{
    brandName + '(最低价)':
        brandGold + config.brandStore.benchmarkMarkup + config.brandStore.laborPerGram,
    '深圳水贝': benchmarkClose +
        config.shuibei.benchmarkMarkup +
        config.shuibei.laborPerGram,
    '银行金条+打金': bankBase + config.bankBarDiy.laborPerGram,
  };

  var bestCost = double.infinity;
  var worstCost = 0.0;
  raw.forEach((_, cost) {
    if (cost < bestCost) bestCost = cost;
    if (cost > worstCost) worstCost = cost;
  });

  final quotes = raw.entries.map((e) {
    return ChannelQuote(
      name: e.key,
      costPerGram: e.value,
      totalForTarget: config.targetGrams * e.value,
      gramsForBudget: config.budgetCny / e.value,
      isBest: e.value == bestCost,
    );
  }).toList();

  final best = quotes.firstWhere((q) => q.costPerGram == bestCost);
  final worst = quotes.firstWhere((q) => q.costPerGram == worstCost);
  final savings = worst.totalForTarget - best.totalForTarget;

  return ChannelComparison(
    quotes: quotes,
    best: best,
    worst: worst,
    savings: savings,
    savingsPct: worst.totalForTarget == 0 ? 0 : savings / worst.totalForTarget,
  );
}

/// 「一口价」黄金折算克价 —— 防坑工具。
///
/// 品牌店常推「一口价」商品，折算下来可能高达 1500~2000 元/克。
/// 本函数把总价除以克重，与当日大盘价和品牌首饰金价对比给出结论。
class OnePriceResult {
  final double pricePerGram;
  final double benchmarkClose;
  final double? referenceGoldPrice;
  final double? premiumVsBenchmarkPct;
  final double? premiumVsReferencePct;
  final String verdict;
  final bool overpriced;

  const OnePriceResult({
    required this.pricePerGram,
    required this.benchmarkClose,
    this.referenceGoldPrice,
    this.premiumVsBenchmarkPct,
    this.premiumVsReferencePct,
    required this.verdict,
    required this.overpriced,
  });
}

OnePriceResult evaluateOnePrice({
  required double totalPrice,
  required double grams,
  required double benchmarkClose,
  double? referenceGoldPrice,
}) {
  final perGram = grams <= 0 ? double.infinity : totalPrice / grams;
  final vsBenchmark =
      benchmarkClose <= 0 ? null : perGram / benchmarkClose - 1.0;
  final vsReference = (referenceGoldPrice == null || referenceGoldPrice <= 0)
      ? null
      : perGram / referenceGoldPrice - 1.0;

  String verdict;
  bool overpriced;
  final compare = vsReference ?? vsBenchmark;
  if (compare == null) {
    verdict = '无法判断';
    overpriced = false;
  } else if (compare > 0.30) {
    verdict = '严重偏贵：一口价折算克价远高于正常首饰金价，强烈建议改买按克计价商品';
    overpriced = true;
  } else if (compare > 0.15) {
    verdict = '偏贵：折算克价明显高于正常首饰金价，建议货比三家或改按克计价';
    overpriced = true;
  } else if (compare > 0.0) {
    verdict = '略贵：溢价在可接受范围，但仍高于按克计价商品';
    overpriced = false;
  } else {
    verdict = '划算：折算克价不高于参考价';
    overpriced = false;
  }

  return OnePriceResult(
    pricePerGram: perGram,
    benchmarkClose: benchmarkClose,
    referenceGoldPrice: referenceGoldPrice,
    premiumVsBenchmarkPct: vsBenchmark,
    premiumVsReferencePct: vsReference,
    verdict: verdict,
    overpriced: overpriced,
  );
}
