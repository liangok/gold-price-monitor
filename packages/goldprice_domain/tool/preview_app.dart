/// 用真实线上数据，走一遍 App 首页的完整链路并打印结果。
///
/// 不需要手机、不需要 Flutter —— 直接验证「仓库里的数据 + 领域层逻辑」
/// 能不能算出 App 该显示的内容。改动数据结构或策略后，跑一下这个最快。
///
/// 用法: dart run tool/preview_app.dart
library;

import 'dart:convert';

import 'package:goldprice_domain/goldprice_domain.dart';

Future<void> main() async {
  const RepoConfig repo = RepoConfig(
    owner: 'liangok',
    repo: 'gold-price-monitor',
  );

  print('== 拉取线上数据 ==');
  final FetchedData latestRaw = await fetchFreshest(repo.latestUrls);
  final FetchedData historyRaw = await fetchFreshest(repo.benchmarkHistoryUrls);
  final FetchedData configRaw = await fetchFreshest(repo.userConfigUrls);
  print('latest   : ' + (latestRaw.stamp ?? '?') + '  <- ' + (latestRaw.url ?? '?'));
  print('history  : ' + (historyRaw.stamp ?? '?'));
  print('config   : ' + (configRaw.stamp ?? '?'));
  print('');

  final LatestSnapshot latest = LatestSnapshot.decode(latestRaw.text);
  final BenchmarkHistory history = BenchmarkHistory.decode(historyRaw.text);
  final Map<String, dynamic> cfg =
      jsonDecode(configRaw.text) as Map<String, dynamic>;
  final ChannelConfig channelConfig = ChannelConfig.fromJson(cfg);
  final AlertConfig alertConfig = AlertConfig.fromJson(cfg);

  // ---------------- 大盘 ----------------
  print('== 今日（App 首页顶部卡片）==');
  final BenchmarkRecord b = latest.benchmark;
  final List<double> closes = history.closes;
  final double changePct = closes.length >= 2
      ? closes.last / closes[closes.length - 2] - 1.0
      : 0.0;
  print('数据日期      ' + latest.dataDate);
  print('大盘 Au99.99  ' + b.date);
  print('收盘价        ' + b.close.toStringAsFixed(2) + ' 元/克');
  print('日涨跌        ' + (changePct * 100).toStringAsFixed(2) + '%');
  print('');

  // ---------------- 渠道对比 ----------------
  print('== 渠道对比（App 首页第一块）==');
  final BrandQuote? cheapest = latest.cheapestMainlandGold;
  if (cheapest == null) {
    print('（没有大陆品牌数据）');
  } else {
    final ChannelComparison cmp = compareChannels(
      benchmarkClose: b.close,
      brandName: cheapest.name,
      brandGold: cheapest.gold!,
      bankBarPrice: latest.cheapestBankBarPrice,
      config: channelConfig,
    );
    print('预算 ' +
        channelConfig.budgetCny.toStringAsFixed(0) +
        ' 元 / 目标 ' +
        channelConfig.targetGrams.toStringAsFixed(0) +
        ' 克');
    for (final ChannelQuote q in cmp.quotes) {
      print('  ' +
          (q.isBest ? '✓ ' : '  ') +
          q.name.padRight(16) +
          q.costPerGram.toStringAsFixed(0).padLeft(6) +
          ' 元/克   ' +
          q.gramsForBudget.toStringAsFixed(1).padLeft(6) +
          ' 克');
    }
    print('  最优 ' +
        cmp.best.name +
        '，最差 ' +
        cmp.worst.name +
        '，买 ' +
        channelConfig.targetGrams.toStringAsFixed(0) +
        ' 克可省 ' +
        cmp.savings.toStringAsFixed(0) +
        ' 元（' +
        (cmp.savingsPct * 100).toStringAsFixed(0) +
        '%）');
  }
  print('');

  // ---------------- 提醒 ----------------
  print('== 提醒（App 首页提醒卡片）==');
  final IndicatorSnapshot? ind = computeLatest(closes, history.dates);
  if (ind == null) {
    print('（历史数据不足）');
  } else {
    print('MA20/MA60     ' +
        (ind.ma(20)?.toStringAsFixed(2) ?? 'n/a') +
        ' / ' +
        (ind.ma(60)?.toStringAsFixed(2) ?? 'n/a'));
    print('距90日高点    ' + ((ind.drawdown ?? 0) * 100).toStringAsFixed(2) + '%');
    print('RSI14         ' + (ind.rsi?.toStringAsFixed(1) ?? 'n/a'));
    final List<AlertResult> results = evaluateAlerts(ind, alertConfig);
    for (final AlertResult a in results) {
      print('  ' +
          (a.triggered ? '[已触发]' : '[  --  ]') +
          ' ' +
          a.name.padRight(24) +
          (a.level == AlertLevel.hint ? '[仅提示] ' : '[核心]   ') +
          a.detail);
    }
    print('  共 ' + triggeredCount(results).toString() + ' 条触发');
  }
  print('');

  // ---------------- 品牌比价 ----------------
  print('== 品牌首饰金比价 ==');
  final List<BrandQuote> brands = latest.mainlandBrands
      .where((BrandQuote x) => x.gold != null)
      .toList()
    ..sort((BrandQuote x, BrandQuote y) => x.gold!.compareTo(y.gold!));
  for (final BrandQuote x in brands) {
    print('  ' +
        x.name.padRight(12) +
        x.gold!.toStringAsFixed(0).padLeft(6) +
        ' 元/克' +
        (x.bar == null ? '' : '   金条 ' + x.bar!.toStringAsFixed(0)));
  }
  final BrandStats? stats = latest.brandStats['gold'];
  if (stats != null && stats.min != null && stats.max != null) {
    print('  价差 ' + stats.spread!.toStringAsFixed(0) + ' 元/克');
  }
}
