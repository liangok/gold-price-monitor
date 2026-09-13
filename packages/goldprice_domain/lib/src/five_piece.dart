/// 结婚「五金」清单的逐件累加计算。
///
/// 为什么单独做这个：App 首页的渠道对比是按「一个目标克重」算的，
/// 但真实买五金是 5 件不同重量的首饰，且工费差异很大（古法金 / 3D 硬金按件卖）。
/// 这里让用户逐件录入，再算出整份清单在各渠道的总价。
library;

import 'channels.dart';

/// 清单里的一件首饰。
class GoldPiece {
  final String name;
  final double grams;

  /// 品牌店口径的工费（元/克）。水贝 / 打金的工费通常低得多。
  final double laborPerGram;

  const GoldPiece({
    required this.name,
    required this.grams,
    this.laborPerGram = 0,
  });

  GoldPiece copyWith({double? grams, double? laborPerGram}) {
    return GoldPiece(
      name: name,
      grams: grams ?? this.grams,
      laborPerGram: laborPerGram ?? this.laborPerGram,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'grams': grams,
        'labor_per_gram': laborPerGram,
      };

  factory GoldPiece.fromJson(Map<String, dynamic> json) {
    return GoldPiece(
      name: json['name'] as String? ?? '',
      grams: (json['grams'] as num?)?.toDouble() ?? 0,
      laborPerGram: (json['labor_per_gram'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 一份五金清单。
class GoldPlan {
  final List<GoldPiece> pieces;

  const GoldPlan({required this.pieces});

  double get totalGrams {
    var sum = 0.0;
    for (final GoldPiece piece in pieces) {
      sum += piece.grams;
    }
    return sum;
  }

  /// 按逐件工费累加出来的品牌店工费总额。
  double get totalLaborAtBrandPrice {
    var sum = 0.0;
    for (final GoldPiece piece in pieces) {
      sum += piece.grams * piece.laborPerGram;
    }
    return sum;
  }

  /// 折算到每克的平均品牌工费。
  double get weightedBrandLaborPerGram {
    final double grams = totalGrams;
    if (grams <= 0) return 0;
    return totalLaborAtBrandPrice / grams;
  }

  GoldPlan withPiece(int index, GoldPiece piece) {
    final List<GoldPiece> next = List<GoldPiece>.of(pieces);
    if (index >= 0 && index < next.length) {
      next[index] = piece;
    }
    return GoldPlan(pieces: next);
  }

  /// 常见的结婚五金默认清单。
  /// 克重只是「起手值」，每个人差异很大，用户可自行修改。
  /// 默认合计 53 克 —— 按 7~8 万预算、品牌店 1300 元/克上下，量级吻合。
  static const GoldPlan weddingFive = GoldPlan(pieces: <GoldPiece>[
    GoldPiece(name: '戒指', grams: 4, laborPerGram: 60),
    GoldPiece(name: '项链', grams: 12, laborPerGram: 55),
    GoldPiece(name: '耳环', grams: 3, laborPerGram: 60),
    GoldPiece(name: '手镯', grams: 28, laborPerGram: 50),
    GoldPiece(name: '吊坠', grams: 6, laborPerGram: 60),
  ]);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pieces': pieces.map((GoldPiece p) => p.toJson()).toList(),
      };

  factory GoldPlan.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['pieces'];
    if (raw is! List || raw.isEmpty) return weddingFive;
    return GoldPlan(
      pieces: raw
          .whereType<Map<String, dynamic>>()
          .map(GoldPiece.fromJson)
          .toList(growable: false),
    );
  }
}

/// 整份清单在某个渠道的花费拆解。
class PlanChannelCost {
  final String channelName;
  final double metalPerGram;
  final double laborPerGram;

  /// 工费是否来自「逐件录入」（品牌店）而非渠道默认值。
  final bool laborFromPieces;
  final double totalGrams;

  const PlanChannelCost({
    required this.channelName,
    required this.metalPerGram,
    required this.laborPerGram,
    required this.laborFromPieces,
    required this.totalGrams,
  });

  double get metalTotal => totalGrams * metalPerGram;
  double get laborTotal => totalGrams * laborPerGram;
  double get total => metalTotal + laborTotal;
  double get costPerGram => metalPerGram + laborPerGram;
}

/// 把一份清单按各渠道的克价与工费算出总价。
///
/// 克价口径与 [compareChannels] 保持一致，避免两处算法不一致。
List<PlanChannelCost> pricePlan({
  required GoldPlan plan,
  required double benchmarkClose,
  required String brandName,
  required double brandGold,
  double? bankBarPrice,
  required ChannelConfig config,
}) {
  final double grams = plan.totalGrams;
  final double bankBase =
      bankBarPrice ?? (benchmarkClose + config.bankBarDiy.benchmarkMarkup);

  return <PlanChannelCost>[
    PlanChannelCost(
      channelName: '$brandName(品牌店)',
      metalPerGram: brandGold + config.brandStore.benchmarkMarkup,
      laborPerGram: plan.weightedBrandLaborPerGram,
      laborFromPieces: true,
      totalGrams: grams,
    ),
    PlanChannelCost(
      channelName: '深圳水贝',
      metalPerGram: benchmarkClose + config.shuibei.benchmarkMarkup,
      laborPerGram: config.shuibei.laborPerGram,
      laborFromPieces: false,
      totalGrams: grams,
    ),
    PlanChannelCost(
      channelName: '银行金条+打金',
      metalPerGram: bankBase,
      laborPerGram: config.bankBarDiy.laborPerGram,
      laborFromPieces: false,
      totalGrams: grams,
    ),
  ];
}
