import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';

class HomeData {
  final LatestSnapshot snapshot;
  final BenchmarkHistory history;
  final AlertConfig alertConfig;
  final ChannelConfig channelConfig;

  const HomeData({
    required this.snapshot,
    required this.history,
    required this.alertConfig,
    required this.channelConfig,
  });
}

class HomePage extends StatefulWidget {
  final GoldRepository repository;

  const HomePage({super.key, required this.repository});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<HomeData> _future = _load();

  Future<HomeData> _load() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      widget.repository.loadLatest(),
      widget.repository.loadBenchmarkHistory(),
      widget.repository.loadUserConfig(),
    ]);
    final cfg = results[2] as Map<String, dynamic>;
    return HomeData(
      snapshot: results[0] as LatestSnapshot,
      history: results[1] as BenchmarkHistory,
      alertConfig: AlertConfig.fromJson(cfg),
      channelConfig: ChannelConfig.fromJson(cfg),
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _money(double v) => v.toStringAsFixed(2);

  String _grams(double v) => v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('金价监控'),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<HomeData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              message: snap.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                _benchmarkCard(context, data),
                const SizedBox(height: 12),
                _channelCard(context, data, scheme),
                const SizedBox(height: 12),
                _alertCard(context, data),
                const SizedBox(height: 12),
                _brandCard(context, data),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _benchmarkCard(BuildContext context, HomeData data) {
    final b = data.snapshot.benchmark;
    final closes = data.history.closes;
    double? changePct;
    if (closes.length >= 2) {
      changePct = closes.last / closes[closes.length - 2] - 1.0;
    }
    final up = (changePct ?? 0) >= 0;
    final color = up ? Colors.red.shade600 : Colors.green.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text('上海黄金交易所 Au99.99',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(b.date, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  _money(b.close),
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Text('元/克'),
                const Spacer(),
                if (changePct != null)
                  Text(
                    (up ? '+' : '') +
                        (changePct * 100).toStringAsFixed(2) +
                        '%',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '开 ' +
                  _money(b.open) +
                  '   高 ' +
                  _money(b.high) +
                  '   低 ' +
                  _money(b.low),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelCard(BuildContext context, HomeData data, ColorScheme scheme) {
    final cheapest = data.snapshot.cheapestMainlandGold;
    if (cheapest == null) {
      return const Card(child: ListTile(title: Text('暂无品牌数据')));
    }
    final cmp = compareChannels(
      benchmarkClose: data.snapshot.benchmark.close,
      brandName: cheapest.name,
      brandGold: cheapest.gold!,
      bankBarPrice: data.snapshot.cheapestBankBarPrice,
      config: data.channelConfig,
    );
    final target = data.channelConfig.targetGrams;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text('渠道对比',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 8),
                Text('预算 ' +
                    data.channelConfig.budgetCny.toStringAsFixed(0) +
                    ' 元 / 目标 ' +
                    target.toStringAsFixed(0) +
                    ' 克'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '同样预算，不同渠道能买的克重差很多 —— 这比择时更重要。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ...cmp.quotes.map((ChannelQuote q) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    if (q.isBest)
                      Icon(Icons.check_circle,
                          size: 16, color: scheme.primary)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        q.name,
                        style: TextStyle(
                          fontWeight:
                              q.isBest ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(_money(q.costPerGram) + ' 元/克'),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 62,
                      child: Text(
                        _grams(q.gramsForBudget) + ' 克',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: q.isBest ? scheme.primary : null,
                          fontWeight:
                              q.isBest ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 20),
            Text(
              '买 ' +
                  target.toStringAsFixed(0) +
                  ' 克：' +
                  cmp.worst.name +
                  ' 需 ' +
                  cmp.worst.totalForTarget.toStringAsFixed(0) +
                  ' 元，' +
                  cmp.best.name +
                  ' 需 ' +
                  cmp.best.totalForTarget.toStringAsFixed(0) +
                  ' 元，省 ' +
                  cmp.savings.toStringAsFixed(0) +
                  ' 元（' +
                  (cmp.savingsPct * 100).toStringAsFixed(0) +
                  '%）',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (data.snapshot.cheapestBankBarPrice != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '银行金条+打金：实时最低银行金条 ' +
                      _money(data.snapshot.cheapestBankBarPrice!) +
                      ' 元/克',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(BuildContext context, HomeData data) {
    final ind = computeLatest(data.history.closes, data.history.dates);
    if (ind == null) {
      return const Card(child: ListTile(title: Text('历史数据不足，无法判断')));
    }
    final alerts = evaluateAlerts(ind, data.alertConfig);
    final hits = triggeredCount(alerts);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              hits > 0 ? '提醒（$hits 条触发）' : '提醒（当前无触发）',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...alerts.map((AlertResult a) {
              final isHint = a.level == AlertLevel.hint;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      a.triggered
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      size: 16,
                      color: a.triggered
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).disabledColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(child: Text(a.name)),
                              const SizedBox(width: 6),
                              if (isHint)
                                Text('仅提示',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          Text(a.detail,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _brandCard(BuildContext context, HomeData data) {
    final stats = data.snapshot.brandStats['gold'];
    final brands = data.snapshot.mainlandBrands
        .where((BrandQuote b) => b.gold != null)
        .toList()
      ..sort((BrandQuote a, BrandQuote b) => a.gold!.compareTo(b.gold!));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('品牌首饰金比价',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (stats != null && stats.min != null && stats.max != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '最低 ' +
                      stats.min!.name +
                      ' ' +
                      stats.min!.price.toStringAsFixed(0) +
                      '  |  最高 ' +
                      stats.max!.name +
                      ' ' +
                      stats.max!.price.toStringAsFixed(0) +
                      '  |  价差 ' +
                      stats.spread!.toStringAsFixed(0) +
                      ' 元/克',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            ...brands.map((BrandQuote b) {
              final isMin = stats?.min?.name == b.name;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        b.name,
                        style: TextStyle(
                          fontWeight:
                              isMin ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (b.bar != null)
                      Text('金条 ' + b.bar!.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 64,
                      child: Text(
                        b.gold!.toStringAsFixed(0) + ' 元',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: isMin
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight:
                              isMin ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text('拉取数据失败'),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '请检查 app/lib/config.dart 里的 GitHub 用户名/仓库名是否正确。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
