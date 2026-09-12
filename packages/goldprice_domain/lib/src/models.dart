/// 数据模型：严格对应仓库 data/*.json 的结构。
///
/// 数据由 GitHub Actions 每日采集（见 collector/collect.py），
/// App 只读不写，因此模型保持不可变（immutable）。
import 'dart:convert';

enum BrandRegion { mainland, hk }

class BenchmarkRecord {
  final String date;
  final double open;
  final double close;
  final double low;
  final double high;

  const BenchmarkRecord({
    required this.date,
    required this.open,
    required this.close,
    required this.low,
    required this.high,
  });

  factory BenchmarkRecord.fromJson(Map<String, dynamic> json) {
    return BenchmarkRecord(
      date: json['date'] as String,
      open: (json['open'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
    );
  }
}

class BenchmarkHistory {
  final String symbol;
  final String unit;
  final List<BenchmarkRecord> records;

  const BenchmarkHistory({
    required this.symbol,
    required this.unit,
    required this.records,
  });

  List<double> get closes =>
      records.map((r) => r.close).toList(growable: false);

  List<String> get dates => records.map((r) => r.date).toList(growable: false);

  factory BenchmarkHistory.fromJson(Map<String, dynamic> json) {
    final raw = json['records'] as List<dynamic>?;
    final list = (raw ?? const <dynamic>[])
        .map((e) => BenchmarkRecord.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return BenchmarkHistory(
      symbol: json['symbol'] as String? ?? 'Au99.99',
      unit: json['unit'] as String? ?? 'CNY/g',
      records: list,
    );
  }

  static BenchmarkHistory decode(String source) {
    return BenchmarkHistory.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}

class BrandQuote {
  final String name;
  final BrandRegion region;
  final String unit;
  final double? gold;
  final double? bar;
  final double? platinum;

  const BrandQuote({
    required this.name,
    required this.region,
    required this.unit,
    this.gold,
    this.bar,
    this.platinum,
  });

  factory BrandQuote.fromJson(Map<String, dynamic> json) {
    double? pick(String key) => (json[key] as num?)?.toDouble();
    final isHk = (json['region'] as String? ?? 'mainland') == 'hk';
    return BrandQuote(
      name: json['name'] as String,
      region: isHk ? BrandRegion.hk : BrandRegion.mainland,
      unit: json['unit'] as String? ?? 'CNY/g',
      gold: pick('gold'),
      bar: pick('bar'),
      platinum: pick('platinum'),
    );
  }
}

class BrandStat {
  final String name;
  final double price;

  const BrandStat({required this.name, required this.price});

  factory BrandStat.fromJson(Map<String, dynamic> json) {
    return BrandStat(
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
    );
  }
}

class BrandStats {
  final BrandStat? min;
  final BrandStat? max;
  final double? avg;
  final double? spread;
  final int count;

  const BrandStats({this.min, this.max, this.avg, this.spread, this.count = 0});

  factory BrandStats.fromJson(Map<String, dynamic> json) {
    BrandStat? stat(String key) {
      final raw = json[key];
      if (raw is! Map<String, dynamic>) return null;
      return BrandStat.fromJson(raw);
    }

    return BrandStats(
      min: stat('min'),
      max: stat('max'),
      avg: (json['avg'] as num?)?.toDouble(),
      spread: (json['spread'] as num?)?.toDouble(),
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class Premium {
  final String benchmarkDate;
  final double benchmarkClose;
  final double brandGoldAvg;
  final double amount;
  final double pct;

  const Premium({
    required this.benchmarkDate,
    required this.benchmarkClose,
    required this.brandGoldAvg,
    required this.amount,
    required this.pct,
  });

  factory Premium.fromJson(Map<String, dynamic> json) {
    return Premium(
      benchmarkDate: json['benchmark_date'] as String? ?? '',
      benchmarkClose: (json['benchmark_close'] as num).toDouble(),
      brandGoldAvg: (json['brand_gold_avg'] as num).toDouble(),
      amount: (json['amount'] as num).toDouble(),
      pct: (json['pct'] as num).toDouble(),
    );
  }
}

/// 银行 / 品牌金店的金条报价（数据源：金价查询网，每日更新）。
class BankBarQuote {
  final String name;
  final String product;
  final double price;
  final bool isBank;

  const BankBarQuote({
    required this.name,
    required this.product,
    required this.price,
    required this.isBank,
  });

  factory BankBarQuote.fromJson(Map<String, dynamic> json) {
    return BankBarQuote(
      name: json['name'] as String,
      product: json['product'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      isBank: json['is_bank'] as bool? ?? false,
    );
  }
}

/// data/latest.json —— App 首页直接消费的今日汇总。
class LatestSnapshot {
  final String dataDate;
  final String generatedAt;
  final BenchmarkRecord benchmark;
  final List<BrandQuote> brands;
  final Map<String, BrandStats> brandStats;
  final List<BankBarQuote> bankBars;
  final Premium? premium;

  const LatestSnapshot({
    required this.dataDate,
    required this.generatedAt,
    required this.benchmark,
    required this.brands,
    required this.brandStats,
    this.bankBars = const <BankBarQuote>[],
    this.premium,
  });

  List<BrandQuote> get mainlandBrands => brands
      .where((b) => b.region == BrandRegion.mainland)
      .toList(growable: false);

  /// 大陆品牌中首饰金最低的一家（用于渠道对比的「品牌店」基准）。
  BrandQuote? get cheapestMainlandGold {
    final pool = mainlandBrands.where((b) => b.gold != null).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.gold!.compareTo(b.gold!));
    return pool.first;
  }

  /// 银行金条中的最低价（用于渠道对比的「银行金条+打金」基准）。
  double? get cheapestBankBarPrice {
    final pool = bankBars.where((b) => b.isBank).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.price.compareTo(b.price));
    return pool.first.price;
  }

  factory LatestSnapshot.fromJson(Map<String, dynamic> json) {
    final rawBrands = json['brands'] as List<dynamic>? ?? const <dynamic>[];
    final rawBank = json['bank_bars'] as Map<String, dynamic>?;
    final rawBankItems =
        rawBank?['items'] as List<dynamic>? ?? const <dynamic>[];
    final rawStats = json['brand_stats'] as Map<String, dynamic>? ?? const {};
    final stats = <String, BrandStats>{};
    rawStats.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        stats[key] = BrandStats.fromJson(value);
      }
    });
    final rawPremium = json['premium'];
    return LatestSnapshot(
      dataDate: json['data_date'] as String? ?? '',
      generatedAt: json['generated_at'] as String? ?? '',
      benchmark:
          BenchmarkRecord.fromJson(json['benchmark'] as Map<String, dynamic>),
      brands: rawBrands
          .map((e) => BrandQuote.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      brandStats: stats,
      bankBars: rawBankItems
          .map((e) => BankBarQuote.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      premium: rawPremium is Map<String, dynamic>
          ? Premium.fromJson(rawPremium)
          : null,
    );
  }

  static LatestSnapshot decode(String source) {
    return LatestSnapshot.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}
