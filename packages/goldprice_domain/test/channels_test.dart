/// 渠道对比与一口价折算的单元测试。
///
/// 期望值来自 Python 参考实现 analysis/today_signals.py 的实际输出
/// （大盘 939.54，中国黄金最低价 1280，预算 75000，目标 55 克）。
import 'package:goldprice_domain/goldprice_domain.dart';
import 'package:test/test.dart';

void main() {
  const config = ChannelConfig(
    budgetCny: 75000,
    targetGrams: 55,
    brandStore: ChannelAssumption(laborPerGram: 50),
    shuibei: ChannelAssumption(benchmarkMarkup: 3, laborPerGram: 30),
    bankBarDiy: ChannelAssumption(benchmarkMarkup: 12, laborPerGram: 25),
  );

  test('三渠道克价与 Python 输出一致', () {
    final cmp = compareChannels(
      benchmarkClose: 939.54,
      brandName: '中国黄金',
      brandGold: 1280,
      config: config,
    );

    expect(cmp.quotes.length, 3);
    final byName = <String, ChannelQuote>{
      for (final q in cmp.quotes) q.name: q,
    };

    expect(byName['中国黄金(最低价)']!.costPerGram, closeTo(1330.00, 1e-9));
    expect(byName['深圳水贝']!.costPerGram, closeTo(972.54, 1e-9));
    expect(byName['银行金条+打金']!.costPerGram, closeTo(976.54, 1e-9));
  });

  test('目标克重总价与节省金额正确', () {
    final cmp = compareChannels(
      benchmarkClose: 939.54,
      brandName: '中国黄金',
      brandGold: 1280,
      config: config,
    );

    expect(cmp.best.name, '深圳水贝');
    expect(cmp.worst.name, '中国黄金(最低价)');
    expect(cmp.worst.totalForTarget, closeTo(73150, 1e-6));
    expect(cmp.best.totalForTarget, closeTo(53489.70, 1e-6));
    expect(cmp.savings, closeTo(19660.30, 1e-6));
    expect(cmp.savingsPct, closeTo(0.2687628, 1e-6));
  });

  test('预算可买克重正确', () {
    final cmp = compareChannels(
      benchmarkClose: 939.54,
      brandName: '中国黄金',
      brandGold: 1280,
      config: config,
    );
    final byName = <String, ChannelQuote>{
      for (final q in cmp.quotes) q.name: q,
    };
    expect(byName['深圳水贝']!.gramsForBudget, closeTo(75000 / 972.54, 1e-9));
    expect(byName['中国黄金(最低价)']!.gramsForBudget, closeTo(75000 / 1330, 1e-9));
  });

  test('一口价折算：严重偏贵会被标记', () {
    final bad = evaluateOnePrice(
      totalPrice: 3000,
      grams: 2,
      benchmarkClose: 939.54,
      referenceGoldPrice: 1300,
    );
    expect(bad.pricePerGram, closeTo(1500, 1e-9));
    expect(bad.premiumVsReferencePct, closeTo(1500 / 1300 - 1, 1e-9));
    expect(bad.overpriced, isTrue);
    expect(bad.verdict.contains('偏贵'), isTrue);
  });

  test('一口价折算：等于参考价不算偏贵', () {
    final ok = evaluateOnePrice(
      totalPrice: 2600,
      grams: 2,
      benchmarkClose: 939.54,
      referenceGoldPrice: 1300,
    );
    expect(ok.overpriced, isFalse);
    expect(ok.verdict.contains('划算'), isTrue);
  });
}
