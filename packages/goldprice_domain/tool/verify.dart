/// 零依赖自检脚本：验证 Dart 领域层与 Python 参考实现完全一致。
///
/// 刻意不使用 package:test，也不引入任何第三方依赖 —— 这样在只有 Dart SDK、
/// 无法访问 pub.dev 的环境里同样能跑，用来捕捉端口转录错误。
///
/// 用法（在 packages/goldprice_domain 目录下）:
///     dart run tool/verify.dart
///
/// 退出码 0 表示全部通过，1 表示有失败项。
import 'dart:convert';
import 'dart:io';

import 'package:goldprice_domain/goldprice_domain.dart';

int _checks = 0;
int _failures = 0;

String _show(Object? v) => v == null ? 'null' : v.toString();

void checkNum(String name, num? actual, num? expected, [double tol = 1e-9]) {
  _checks++;
  if (actual == null || expected == null) {
    if (actual != expected) {
      _failures++;
      print('  FAIL  ' + name + '  actual=' + _show(actual) +
          '  expected=' + _show(expected));
    }
    return;
  }
  final diff = (actual - expected).abs().toDouble();
  if (diff > tol) {
    _failures++;
    print('  FAIL  ' + name + '  actual=' + _show(actual) +
        '  expected=' + _show(expected) +
        '  diff=' + diff.toStringAsExponential(3));
  }
}

void checkBool(String name, bool actual, bool expected) {
  _checks++;
  if (actual != expected) {
    _failures++;
    print('  FAIL  ' + name + '  actual=' + actual.toString() +
        '  expected=' + expected.toString());
  }
}

void checkNull(String name, Object? value) {
  _checks++;
  if (value != null) {
    _failures++;
    print('  FAIL  ' + name + '  期望 null，实际=' + _show(value));
  }
}

void main() {
  final scriptPath = Platform.script.toFilePath();
  final pkgDir = File(scriptPath).parent.parent;
  final fixtureFile =
      File(pkgDir.path + '/test/fixtures/indicators_reference.json');

  if (!fixtureFile.existsSync()) {
    print('找不到夹具: ' + fixtureFile.path);
    print('请先运行: python3 analysis/gen_dart_fixture.py');
    exit(2);
  }

  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final closes = (fixture['closes'] as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList();
  final dates = (fixture['dates'] as List<dynamic>).cast<String>();
  final expected = fixture['expected'] as Map<String, dynamic>;

  print('== 跨语言一致性自检 ==');
  print('夹具: ' + closes.length.toString() + ' 个交易日  ' +
      dates.first + ' -> ' + dates.last);

  // ---------- 1. 指标 ----------
  final snapshot = computeLatest(closes, dates);
  if (snapshot == null) {
    _failures++;
    print('  FAIL  computeLatest 返回 null');
  } else {
    checkNum('close', snapshot.close, closes.last);
    checkBool('date 匹配', snapshot.date == dates.last, true);
    checkNum('sma20', snapshot.ma(20), expected['sma20'] as num);
    checkNum('sma60', snapshot.ma(60), expected['sma60'] as num);
    checkNum('drawdown90', snapshot.drawdown, expected['drawdown90'] as num);
    checkNum('percentile365', snapshot.percentile365,
        expected['percentile365'] as num);
    checkNum('rsi14', snapshot.rsi, expected['rsi14_last'] as num);
    checkNum('changePct', snapshot.changePct, expected['change_pct'] as num);
  }

  // ---------- 2. RSI 采样点 ----------
  final rsi = rsiSeries(closes, 14);
  final samples = expected['rsi14_samples'] as Map<String, dynamic>;
  samples.forEach((key, value) {
    final i = int.parse(key);
    checkNum('rsi[' + key + ']', rsi[i], value as num);
  });

  // ---------- 3. 边界行为 ----------
  checkNull('sma 数据不足', sma(closes, 5, 20));
  checkNull('rollingMax 数据不足', rollingMax(closes, 5, 20));
  checkNull('percentile 数据不足', percentile(closes, 5, 365));
  checkNull('computeLatest 空输入', computeLatest(<double>[], <String>[]));

  // ---------- 4. 渠道对比（对照 Python 实际输出）----------
  const config = ChannelConfig(
    budgetCny: 75000,
    targetGrams: 55,
    brandStore: ChannelAssumption(laborPerGram: 50),
    shuibei: ChannelAssumption(benchmarkMarkup: 3, laborPerGram: 30),
    bankBarDiy: ChannelAssumption(benchmarkMarkup: 12, laborPerGram: 25),
  );
  final cmp = compareChannels(
    benchmarkClose: 939.54,
    brandName: '中国黄金',
    brandGold: 1280,
    bankBarPrice: 953.54, // 民生银行实时最低价（来自采集器）
    config: config,
  );
  final byName = <String, ChannelQuote>{
    for (final q in cmp.quotes) q.name: q,
  };
  checkNum('中国黄金 克价', byName['中国黄金(最低价)']!.costPerGram, 1330.00);
  checkNum('深圳水贝 克价', byName['深圳水贝']!.costPerGram, 972.54);
  checkNum('银行金条+打金 克价', byName['银行金条+打金']!.costPerGram, 978.54);
  checkNum('最便宜渠道总价', cmp.best.totalForTarget, 53489.70, 1e-6);
  checkNum('最贵渠道总价', cmp.worst.totalForTarget, 73150, 1e-6);
  checkNum('节省金额', cmp.savings, 19660.30, 1e-6);
  // 注意：不要手写四舍五入过的常量，直接用精确表达式，否则会误报
  checkNum('节省比例', cmp.savingsPct, 19660.30 / 73150, 1e-12);
  checkBool('最便宜渠道是水贝', cmp.best.name == '深圳水贝', true);

  // ---------- 5. 一口价折算 ----------
  final bad = evaluateOnePrice(
    totalPrice: 3000,
    grams: 2,
    benchmarkClose: 939.54,
    referenceGoldPrice: 1300,
  );
  checkNum('一口价 克价', bad.pricePerGram, 1500);
  checkNum('一口价 相对首饰金溢价', bad.premiumVsReferencePct,
      1500 / 1300 - 1);
  checkBool('一口价 应判为偏贵', bad.overpriced, true);

  final ok = evaluateOnePrice(
    totalPrice: 2600,
    grams: 2,
    benchmarkClose: 939.54,
    referenceGoldPrice: 1300,
  );
  checkBool('等于参考价不应判为偏贵', ok.overpriced, false);

  // ---------- 6. 提醒规则（对照 Python 的 alert_variants）----------
  final variants = fixture['alert_variants'] as Map<String, dynamic>;
  if (snapshot != null) {
    variants.forEach((name, raw) {
      final v = raw as Map<String, dynamic>;
      final c = v['config'] as Map<String, dynamic>;
      final cfg = AlertConfig(
        targetPrice: (c['target_price'] as num?)?.toDouble(),
        dailyDropPct: (c['daily_drop_pct'] as num).toDouble(),
        rsiOversold: (c['rsi_oversold'] as num).toDouble(),
        drawdownPct: (c['drawdown_pct'] as num).toDouble(),
        maWindow: (c['ma_window'] as num).toInt(),
      );
      final results = evaluateAlerts(snapshot, cfg);
      final byKey = <String, AlertResult>{
        for (final r in results) r.key: r,
      };
      final expectedTriggered = v['triggered'] as Map<String, dynamic>;
      checkNum('alert 数量[' + name + ']', results.length,
          expectedTriggered.length);
      expectedTriggered.forEach((key, want) {
        final got = byKey[key];
        if (got == null) {
          _failures++;
          _checks++;
          print('  FAIL  alert[' + name + '/' + key + ']  缺少该规则');
          return;
        }
        checkBool('alert[' + name + '/' + key + ']', got.triggered,
            want as bool);
      });
    });
  }

  // ---------- 7. 数据源地址 ----------
  const repo = RepoConfig(owner: 'someone', repo: 'gold-price-monitor');
  final latest = repo.latestUrls;
  checkNum('候选地址数量', latest.length, 4);
  checkBool(
      '首选用 api.github.com（实测最快且最新）',
      latest.first ==
          'https://api.github.com/repos/someone/gold-price-monitor/contents/data/latest.json?ref=main',
      true);
  checkBool(
      'gcore.jsdelivr 作为第二候选',
      latest[1] ==
          'https://gcore.jsdelivr.net/gh/someone/gold-price-monitor@main/data/latest.json',
      true);
  checkBool(
      'raw 作为最后候选（国内常被墙）',
      latest.last ==
          'https://raw.githubusercontent.com/someone/gold-price-monitor/main/data/latest.json',
      true);

  // ---------- 8. 数据时间戳解析（用于在多个数据源之间挑较新的）----------
  checkBool(
      'dataStamp 读取 generated_at',
      dataStamp('{"generated_at":"2026-09-13T22:13:42+08:00"}') ==
          '2026-09-13T22:13:42+08:00',
      true);
  checkBool(
      'dataStamp 读取 updated_at',
      dataStamp('{"updated_at":"2026-09-13T22:04:43+08:00"}') ==
          '2026-09-13T22:04:43+08:00',
      true);
  checkNull('dataStamp 非 JSON 返回 null', dataStamp('not json'));
  checkNull('dataStamp 无时间戳返回 null', dataStamp('{"a":1}'));
  checkBool(
      'ISO8601 可直接按字典序比较新旧',
      '2026-09-13T22:13:42+08:00'.compareTo('2026-09-13T22:04:43+08:00') > 0,
      true);

  // ---------- 9. 五金清单逐件累加 ----------
  const GoldPlan plan = GoldPlan.weddingFive;
  checkNum('五金默认清单总克重', plan.totalGrams, 53);
  checkNum('五金品牌工费合计', plan.totalLaborAtBrandPrice, 2840);
  checkNum('折算每克品牌工费', plan.weightedBrandLaborPerGram, 2840 / 53);

  const ChannelConfig planCfg = ChannelConfig(
    budgetCny: 75000,
    targetGrams: 55,
    brandStore: ChannelAssumption(laborPerGram: 50),
    shuibei: ChannelAssumption(benchmarkMarkup: 3, laborPerGram: 30),
    bankBarDiy: ChannelAssumption(benchmarkMarkup: 12, laborPerGram: 25),
  );

  final List<PlanChannelCost> costs = pricePlan(
    plan: plan,
    benchmarkClose: 939.54,
    brandName: '中国黄金',
    brandGold: 1280,
    bankBarPrice: 953.54,
    config: planCfg,
  );
  checkNum('清单渠道数量', costs.length, 3);
  final Map<String, PlanChannelCost> planByName = <String, PlanChannelCost>{
    for (final PlanChannelCost c in costs) c.channelName: c,
  };
  checkNum('品牌店每克', planByName['中国黄金(品牌店)']!.costPerGram,
      1280 + 2840 / 53, 1e-6);
  checkNum('品牌店整单总价', planByName['中国黄金(品牌店)']!.total, 70680, 1e-6);
  checkNum('水贝每克', planByName['深圳水贝']!.costPerGram, 972.54);
  checkNum('水贝整单总价', planByName['深圳水贝']!.total, 51544.62, 1e-6);
  checkNum('银行打金每克', planByName['银行金条+打金']!.costPerGram, 978.54);
  checkNum('银行打金整单总价', planByName['银行金条+打金']!.total, 51862.62, 1e-6);
  checkNum(
      '整单可省金额',
      planByName['中国黄金(品牌店)']!.total - planByName['深圳水贝']!.total,
      19135.38,
      1e-6);

  final GoldPlan edited = plan.withPiece(
      3, const GoldPiece(name: '手镯', grams: 38, laborPerGram: 50));
  checkNum('改克重后总克重', edited.totalGrams, 63);
  checkNum('原清单不受影响', plan.totalGrams, 53);

  // ---------- 10. 买点评估 ----------
  const MacroSnapshot macro = MacroSnapshot(
    updatedAt: '2026-09-13T23:00:00+08:00',
    series: <String, MacroSeries>{
      'gold_spot': MacroSeries(
          name: '伦敦金现', date: '2026-09-11', value: 4348.35, chg20Pct: -0.0154),
      'dxy': MacroSeries(
          name: '美元指数', date: '2026-09-11', value: 98.9664, chg20Pct: -0.0033),
      'usdcny': MacroSeries(
          name: '离岸人民币', date: '2026-09-11', value: 6.6959, chg20Pct: -0.0046),
    },
  );

  final double? intlCny = internationalGoldInCny(macro);
  checkNum('国际金价换算', intlCny, 4348.35 * 6.6959 / 31.1034768, 1e-6);

  final BuyAssessment base = assessBuyPoint(
    macro: macro,
    benchmarkClose: 939.54,
    rsi: 45.4,
    changePct: -0.0141,
    drawdown: -0.0896,
  );
  checkNum('基准场景总分', base.total, 1);
  checkBool('基准场景结论为略偏顺风', base.verdict == '略偏顺风', true);
  checkNum('依据条数（含回撤占位）', base.factors.length, 5);

  // 国内大幅溢价 → 负面
  final BuyAssessment rich = assessBuyPoint(
    macro: macro,
    benchmarkClose: 985.0,
    rsi: 45.4,
    changePct: -0.0141,
  );
  checkBool('国内大幅溢价时更差', rich.total < base.total, true);

  // 稀有恐慌信号 → 正面
  final BuyAssessment panic = assessBuyPoint(
    macro: macro,
    benchmarkClose: 939.54,
    rsi: 24.0,
    changePct: -0.031,
  );
  checkBool('恐慌信号提升总分', panic.total > base.total, true);
  checkNum('恐慌信号加满 4 分', panic.factors[3].score, 4);

  // 回撤不加分
  int drawdownScore = 0;
  for (final BuyFactor f in base.factors) {
    if (f.name == '距90日高点') drawdownScore = f.score;
  }
  checkNum('回撤因子不计分', drawdownScore, 0);

  // 缺少宏观数据也不能崩
  final BuyAssessment noMacro = assessBuyPoint(
    macro: null,
    benchmarkClose: 939.54,
    rsi: 45.4,
  );
  checkBool('无宏观数据时仍可评估', noMacro.factors.isNotEmpty, true);

  // ---------- 汇总 ----------
  print('');
  if (_failures == 0) {
    print('全部通过：' + _checks.toString() + ' 项断言，Dart 领域层与 Python 参考实现一致。');
    exit(0);
  }
  print('失败 ' + _failures.toString() + ' / ' + _checks.toString() + ' 项');
  exit(1);
}
