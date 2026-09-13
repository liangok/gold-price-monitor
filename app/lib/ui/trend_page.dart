import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';
import 'widgets/price_line_chart.dart';

class TrendPage extends StatefulWidget {
  final GoldRepository repository;

  const TrendPage({super.key, required this.repository});

  @override
  State<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<TrendPage> {
  late final Future<BenchmarkHistory> _future =
      widget.repository.loadBenchmarkHistory();
  int _rangeDays = 365;

  static const List<List<Object>> _options = <List<Object>>[
    <Object>['30天', 30],
    <Object>['90天', 90],
    <Object>['1年', 365],
    <Object>['3年', 1095],
    <Object>['全部', 100000],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('大盘趋势')),
      body: FutureBuilder<BenchmarkHistory>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<BenchmarkHistory> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final history = snap.data!;
          final total = history.records.length;
          final take = _rangeDays < total ? _rangeDays : total;
          final records = history.records.sublist(total - take);
          final closes = records.map((BenchmarkRecord r) => r.close).toList();

          var minValue = closes.first;
          var maxValue = closes.first;
          for (final v in closes) {
            if (v < minValue) minValue = v;
            if (v > maxValue) maxValue = v;
          }
          final changePct = closes.last / closes.first - 1.0;
          final drawdown = closes.last / maxValue - 1.0;
          final ma20 = _tailAverage(closes, 20);
          final ma60 = _tailAverage(closes, 60);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: _options.map((List<Object> opt) {
                  final int days = opt[1] as int;
                  return ChoiceChip(
                    label: Text(opt[0] as String),
                    selected: _rangeDays == days,
                    onSelected: (_) => setState(() => _rangeDays = days),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${records.first.date}  ~  ${records.last.date}   （$take 个交易日）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: PriceLineChart(
                          values: closes,
                          labels: records
                              .map((BenchmarkRecord r) => r.date)
                              .toList(),
                          lineColor: Theme.of(context).colorScheme.primary,
                          averageLine: ma60,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '橙线为 MA60（近 60 日均价）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('区间指标',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      _metric(context, '最新收盘',
                          '${closes.last.toStringAsFixed(2)} 元/克'),
                      _metric(context, '区间涨跌',
                          '${changePct >= 0 ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%'),
                      _metric(context, '区间最低 / 最高',
                          '${minValue.toStringAsFixed(2)} / ${maxValue.toStringAsFixed(2)}'),
                      _metric(context, '距区间高点',
                          '${(drawdown * 100).toStringAsFixed(2)}%'),
                      _metric(context, 'MA20',
                          ma20 == null ? 'n/a' : ma20.toStringAsFixed(2)),
                      _metric(context, 'MA60',
                          ma60 == null ? 'n/a' : ma60.toStringAsFixed(2)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '回测提醒：回撤、跌破均线这类规则在 2016-2026 的样本里都跑输「随便哪天买」。\n'
                    '真正有超额收益的是稀有的恐慌信号（RSI 超卖、单日大跌），十年只出现几十次。\n'
                    '所以别指望靠这个 App 抄到最低点 —— 它的第一价值是帮你选对渠道。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  double? _tailAverage(List<double> values, int n) {
    if (values.length < n) return null;
    var sum = 0.0;
    for (var i = values.length - n; i < values.length; i++) {
      sum += values[i];
    }
    return sum / n;
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
