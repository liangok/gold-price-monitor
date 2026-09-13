import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';
import 'theme.dart';
import 'widgets/price_line_chart.dart';
import 'widgets/ios_card.dart';

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

  static const List<int> _ranges = <int>[30, 90, 365, 1095, 100000];

  String _rangeLabel(int days) {
    switch (days) {
      case 30:
        return '30天';
      case 90:
        return '90天';
      case 365:
        return '1年';
      case 1095:
        return '3年';
      default:
        return '全部';
    }
  }

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
          final BenchmarkHistory history = snap.data!;
          final int total = history.records.length;
          final int take = _rangeDays < total ? _rangeDays : total;
          final List<BenchmarkRecord> records =
              history.records.sublist(total - take);
          final List<double> closes =
              records.map((BenchmarkRecord r) => r.close).toList();
          final List<String> dates =
              records.map((BenchmarkRecord r) => r.date).toList();

          double minValue = closes.first;
          double maxValue = closes.first;
          for (final double v in closes) {
            if (v < minValue) minValue = v;
            if (v > maxValue) maxValue = v;
          }
          final double changePct = closes.last / closes.first - 1.0;
          final double drawdown = closes.last / maxValue - 1.0;
          final double? ma20 = _tailAverage(closes, 20);
          final double? ma60 = _tailAverage(closes, 60);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                IosMetrics.pagePadding, 4, IosMetrics.pagePadding, 32),
            children: <Widget>[
              cupertino.CupertinoSlidingSegmentedControl<int>(
                groupValue: _rangeDays,
                backgroundColor: const Color(0x1F767680),
                thumbColor: IosColors.card,
                onValueChanged: (int? value) {
                  if (value != null) setState(() => _rangeDays = value);
                },
                children: <int, Widget>{
                  for (final int days in _ranges)
                    days: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(_rangeLabel(days),
                          style: const TextStyle(fontSize: 13)),
                    ),
                },
              ),
              const SizedBox(height: IosMetrics.cardGap),
              IosCard(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '${dates.first}  →  ${dates.last}',
                            style: const TextStyle(
                                fontSize: 13, color: IosColors.secondaryLabel),
                          ),
                          const Spacer(),
                          Text('$take 个交易日',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: IosColors.secondaryLabel)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: PriceLineChart(
                        values: closes,
                        labels: dates,
                        lineColor: IosColors.gold,
                        averageLine: ma60,
                        unit: '元/克',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.touch_app_outlined,
                              size: 14, color: IosColors.tertiaryLabel),
                          SizedBox(width: 5),
                          Text(
                            '按住图表可查看任意一天的具体数值',
                            style: TextStyle(
                                fontSize: 12,
                                color: IosColors.tertiaryLabel),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: <Widget>[
                          Container(width: 12, height: 2, color: IosColors.gold),
                          const SizedBox(width: 6),
                          const Text('收盘价',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: IosColors.secondaryLabel)),
                          const SizedBox(width: 14),
                          Container(
                              width: 12,
                              height: 2,
                              color: const Color(0xFFE8A33D)),
                          const SizedBox(width: 6),
                          const Text('MA60 均线',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: IosColors.secondaryLabel)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IosMetrics.cardGap),
              IosCard(
                title: '区间指标',
                info: '均线、涨跌、回撤都只描述「已经发生了什么」。'
                    '回测显示这类指标并不能预测后续走势 —— 真正有超额收益的是罕见的恐慌日。',
                child: Column(
                  children: <Widget>[
                    _heroMetric(context, closes.last, changePct),
                    const SizedBox(height: 10),
                    _metricRow('区间最低 / 最高',
                        '${minValue.toStringAsFixed(2)} / ${maxValue.toStringAsFixed(2)}'),
                    _metricRow('距区间高点',
                        '${(drawdown * 100).toStringAsFixed(2)}%'),
                    _metricRow('MA20', ma20?.toStringAsFixed(2) ?? '—'),
                    _metricRow('MA60', ma60?.toStringAsFixed(2) ?? '—'),
                  ],
                ),
              ),
              const SizedBox(height: IosMetrics.cardGap),
              IosCard(
                title: '怎么理解这些数字',
                child: Text(
                  '回撤、跌破均线这类规则在 2016-2026 的样本里都跑输「随便哪天买」，'
                  '所以它们在本 App 里只作提示。'
                  '别指望靠它抄到最低点 —— 第一价值是帮你选对渠道。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _heroMetric(BuildContext context, double close, double changePct) {
    final bool up = changePct >= 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          close.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: IosColors.label,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        const Text('元/克',
            style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
        const Spacer(),
        Text(
          '${up ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: up ? IosColors.up : IosColors.down,
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: IosColors.secondaryLabel)),
          ),
          Text(value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: IosColors.label,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }

  double? _tailAverage(List<double> values, int n) {
    if (values.length < n) return null;
    double sum = 0;
    for (int i = values.length - n; i < values.length; i++) {
      sum += values[i];
    }
    return sum / n;
  }
}
