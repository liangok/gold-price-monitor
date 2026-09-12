/// 跨语言一致性测试：Dart 端口 vs Python 参考实现。
///
/// 夹具由 analysis/gen_dart_fixture.py 从真实上金所数据生成，包含
/// 520 个交易日收盘价以及 Python 算出的期望值。这里逐项断言，
/// 目的是捕捉端口转录错误（浮点比较留 1e-9 容差）。
import 'dart:convert';
import 'dart:io';

import 'package:goldprice_domain/goldprice_domain.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> fixture;
  late List<double> closes;
  late List<String> dates;
  late Map<String, dynamic> expected;

  setUpAll(() {
    final file = File('test/fixtures/indicators_reference.json');
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    closes = (fixture['closes'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();
    dates = (fixture['dates'] as List<dynamic>).cast<String>();
    expected = fixture['expected'] as Map<String, dynamic>;
  });

  test('夹具规模正确', () {
    expect(closes.length, fixture['window']);
    expect(dates.length, closes.length);
  });

  test('computeLatest 与 Python 完全一致', () {
    final ind = computeLatest(closes, dates);
    expect(ind, isNotNull);
    final snapshot = ind!;

    expect(snapshot.ma(20)!, closeTo((expected['sma20'] as num).toDouble(), 1e-9));
    expect(snapshot.ma(60)!, closeTo((expected['sma60'] as num).toDouble(), 1e-9));
    expect(snapshot.drawdown!, closeTo((expected['drawdown90'] as num).toDouble(), 1e-9));
    expect(snapshot.percentile365!,
        closeTo((expected['percentile365'] as num).toDouble(), 1e-9));
    expect(snapshot.rsi!, closeTo((expected['rsi14_last'] as num).toDouble(), 1e-9));
    expect(snapshot.changePct!, closeTo((expected['change_pct'] as num).toDouble(), 1e-9));
    expect(snapshot.close, closes.last);
    expect(snapshot.date, dates.last);
  });

  test('RSI 序列各采样点与 Python 完全一致', () {
    final rsi = rsiSeries(closes, 14);
    final samples = expected['rsi14_samples'] as Map<String, dynamic>;
    expect(samples, isNotEmpty);
    samples.forEach((key, value) {
      final i = int.parse(key);
      expect(rsi[i], isNotNull, reason: 'index ' + key + ' 不应为 null');
      expect(rsi[i]!, closeTo((value as num).toDouble(), 1e-9),
          reason: 'index ' + key);
    });
  });

  test('sma / rollingMax / percentile 边界行为', () {
    expect(sma(closes, 5, 20), isNull, reason: '数据不足应返回 null');
    expect(rollingMax(closes, 5, 20), isNull);
    expect(percentile(closes, 5, 365), isNull);
    expect(computeLatest(const <double>[], const <String>[]), isNull);
  });
}
