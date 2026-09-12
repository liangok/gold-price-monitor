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
  checkNum('节省比例', cmp.savingsPct, 0.2687628, 1e-6);
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

  // ---------- 汇总 ----------
  print('');
  if (_failures == 0) {
    print('全部通过：' + _checks.toString() + ' 项断言，Dart 领域层与 Python 参考实现一致。');
    exit(0);
  }
  print('失败 ' + _failures.toString() + ' / ' + _checks.toString() + ' 项');
  exit(1);
}
