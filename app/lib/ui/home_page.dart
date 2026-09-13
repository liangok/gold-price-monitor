import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';
import 'theme.dart';
import 'widgets/bar_row.dart';
import 'widgets/ios_card.dart';

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

/// 今日页。
///
/// 信息层级刻意做得很「薄」：一张卡只回答一个问题，
/// 解释性长句一律收进标题旁的「?」，主界面只留数字和图形。
class HomePage extends StatefulWidget {
  final GoldRepository repository;

  const HomePage({super.key, required this.repository});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<HomeData> _future = _load();

  /// 提醒默认只显示「触发了什么」，完整规则列表折叠起来。
  bool _alertsExpanded = false;

  Future<HomeData> _load() async {
    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      widget.repository.loadLatest(),
      widget.repository.loadBenchmarkHistory(),
      widget.repository.loadUserConfig(),
    ]);
    final Map<String, dynamic> cfg = results[2] as Map<String, dynamic>;
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

  static String _money(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('金价监控'),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: IosColors.secondaryLabel),
            tooltip: '刷新',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<HomeData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(message: snap.error.toString(), onRetry: _refresh);
          }
          final HomeData data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  IosMetrics.pagePadding, 0, IosMetrics.pagePadding, 32),
              children: <Widget>[
                if (widget.repository.usingBundledData)
                  const _OfflineBanner()
                else
                  const SizedBox(height: 4),
                _benchmarkCard(context, data),
                const SizedBox(height: IosMetrics.cardGap),
                _channelCard(context, data),
                const SizedBox(height: IosMetrics.cardGap),
                _alertCard(context, data),
                const SizedBox(height: IosMetrics.cardGap),
                _brandCard(context, data),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ 大盘

  Widget _benchmarkCard(BuildContext context, HomeData data) {
    final BenchmarkRecord b = data.snapshot.benchmark;
    final List<double> closes = data.history.closes;
    double? changePct;
    if (closes.length >= 2) {
      changePct = closes.last / closes[closes.length - 2] - 1.0;
    }
    final bool up = (changePct ?? 0) >= 0;
    final Color tint = up ? IosColors.up : IosColors.down;

    return IosCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '上海黄金交易所 Au99.99',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: IosColors.secondaryLabel),
              ),
              const Spacer(),
              Text(b.date,
                  style: const TextStyle(
                      fontSize: 13, color: IosColors.secondaryLabel)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                _money(b.close),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: IosColors.label,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              const Text('元/克',
                  style:
                      TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
              const Spacer(),
              if (changePct != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: tint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '开 ${_money(b.open)}　高 ${_money(b.high)}　低 ${_money(b.low)}',
            style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 渠道

  Widget _channelCard(BuildContext context, HomeData data) {
    final BrandQuote? cheapest = data.snapshot.cheapestMainlandGold;
    if (cheapest == null) {
      return const IosCard(child: Text('暂无品牌数据'));
    }
    final ChannelComparison cmp = compareChannels(
      benchmarkClose: data.snapshot.benchmark.close,
      brandName: cheapest.name,
      brandGold: cheapest.gold!,
      bankBarPrice: data.snapshot.cheapestBankBarPrice,
      config: data.channelConfig,
    );
    final double maxGrams = cmp.quotes
        .map((ChannelQuote q) => q.gramsForBudget)
        .reduce((double a, double b) => a > b ? a : b);
    final double target = data.channelConfig.targetGrams;

    return IosCard(
      title: '渠道对比',
      info: '同样预算，不同渠道能买到的克重差别很大。'
          '品牌店的首饰金比大盘价高约 40%（品牌溢价 + 工费），'
          '水贝与银行金条打金则接近大盘价。'
          '这是本项目认为比「择时」重要得多的一件事。\n\n'
          '各渠道克价为可调假设值，见仓库 config/user.json。',
      trailing: Text(
        '预算 ${data.channelConfig.budgetCny.toStringAsFixed(0)} 元',
        style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 结论先行：一句话说清省多少
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              const Text('买 ',
                  style: TextStyle(fontSize: 15, color: IosColors.label)),
              Text(target.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const Text(' 克，最多省 ',
                  style: TextStyle(fontSize: 15, color: IosColors.label)),
              Text(
                cmp.savings.toStringAsFixed(0),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: IosColors.gold,
                    letterSpacing: -0.6),
              ),
              const Text(' 元',
                  style: TextStyle(fontSize: 15, color: IosColors.label)),
            ],
          ),
          const SizedBox(height: 14),
          ...cmp.quotes.map((ChannelQuote q) {
            return BarRow(
              label: q.name,
              valueText: '${q.gramsForBudget.toStringAsFixed(1)} 克',
              fraction: q.gramsForBudget / maxGrams,
              highlight: q.isBest,
            );
          }),
          const SizedBox(height: 6),
          Text(
            '克价：${cmp.best.name} ${cmp.best.costPerGram.toStringAsFixed(0)} 元/克　'
            '${cmp.worst.name} ${cmp.worst.costPerGram.toStringAsFixed(0)} 元/克',
            style: const TextStyle(fontSize: 12, color: IosColors.secondaryLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 提醒

  Widget _alertCard(BuildContext context, HomeData data) {
    final IndicatorSnapshot? ind =
        computeLatest(data.history.closes, data.history.dates);
    if (ind == null) {
      return const IosCard(child: Text('历史数据不足，无法判断'));
    }
    final List<AlertResult> alerts = evaluateAlerts(ind, data.alertConfig);
    final List<AlertResult> hits =
        alerts.where((AlertResult a) => a.triggered).toList();

    return IosCard(
      title: '提醒',
      info: '核心信号（绝对目标价 / 单日大跌 / RSI 超卖）可靠稀有；'
          '回撤与均线在 2016-2026 的回测里都跑输「随便哪天买」，'
          '所以只作提示、默认不发通知。',
      trailing: Text(
        hits.isEmpty ? '无触发' : '${hits.length} 条触发',
        style: TextStyle(
          fontSize: 13,
          fontWeight: hits.isEmpty ? FontWeight.w400 : FontWeight.w700,
          color: hits.isEmpty ? IosColors.secondaryLabel : IosColors.gold,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hits.isEmpty)
            Text(
              '当前无触发。这是常态 —— 回测显示最好的信号 10 年只出现 39 次。',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...hits.map((AlertResult a) => _alertRow(context, a)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _alertsExpanded = !_alertsExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: <Widget>[
                Text(
                  _alertsExpanded ? '收起全部规则' : '查看全部 ${alerts.length} 条规则',
                  style: const TextStyle(
                      fontSize: 13,
                      color: IosColors.gold,
                      fontWeight: FontWeight.w500),
                ),
                Icon(
                  _alertsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: IosColors.gold,
                ),
              ],
            ),
          ),
          if (_alertsExpanded) ...<Widget>[
            const SizedBox(height: 4),
            ...alerts.map((AlertResult a) => _ruleRow(context, a)),
          ],
        ],
      ),
    );
  }

  /// 触发的规则：只显示名字与关键数值。
  Widget _alertRow(BuildContext context, AlertResult a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.notifications_active,
                size: 15, color: IosColors.gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(a.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(a.detail,
                    style: const TextStyle(
                        fontSize: 12, color: IosColors.secondaryLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 完整规则列表：名称 + 状态圆点，明细不展开（要细节看提醒页）。
  Widget _ruleRow(BuildContext context, AlertResult a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            a.triggered ? Icons.check_circle : Icons.circle_outlined,
            size: 15,
            color: a.triggered ? IosColors.gold : IosColors.tertiaryLabel,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a.name,
                style: const TextStyle(fontSize: 13.5)),
          ),
          if (a.level == AlertLevel.hint)
            const Text('仅提示',
                style: TextStyle(fontSize: 12, color: IosColors.tertiaryLabel)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 品牌

  Widget _brandCard(BuildContext context, HomeData data) {
    final BrandStats? stats = data.snapshot.brandStats['gold'];
    final List<BrandQuote> brands = data.snapshot.mainlandBrands
        .where((BrandQuote b) => b.gold != null)
        .toList()
      ..sort((BrandQuote a, BrandQuote b) => a.gold!.compareTo(b.gold!));
    if (brands.isEmpty) {
      return const IosCard(child: Text('暂无品牌数据'));
    }
    final double maxGold = brands.last.gold!;
    final double minGold = brands.first.gold!;
    final double span = (maxGold - minGold).abs() < 1e-9 ? 1 : maxGold - minGold;

    return IosCard(
      title: '品牌首饰金比价',
      info: '各品牌「足金首饰」挂牌价，通常是首饰金，不含工费。'
          '价差看着不大，但按克重放大后是一笔钱。',
      trailing: stats?.spread == null
          ? null
          : Text('价差 ${stats!.spread!.toStringAsFixed(0)} 元/克',
              style: const TextStyle(
                  fontSize: 13, color: IosColors.secondaryLabel)),
      child: Column(
        children: brands.map((BrandQuote b) {
          final bool isMin = b.name == brands.first.name;
          // 用「相对最低价的差距」做条长：最低价最长
          final double f = 1.0 - ((b.gold! - minGold) / span) * 0.55;
          return BarRow(
            label: b.name,
            valueText: '${b.gold!.toStringAsFixed(0)} 元',
            fraction: f,
            highlight: isMin,
          );
        }).toList(),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: IosMetrics.cardGap),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(IosMetrics.cardRadius),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.cloud_off, size: 16, color: Color(0xFF9A6B00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前显示的是打包进 App 的快照数据，不是最新的。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF9A6B00)),
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 44, color: IosColors.tertiaryLabel),
            const SizedBox(height: 14),
            const Text('拉取数据失败',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: IosColors.secondaryLabel),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
