import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';

class ToolsData {
  final LatestSnapshot snapshot;
  final ChannelConfig channelConfig;

  const ToolsData({required this.snapshot, required this.channelConfig});
}

/// 买金实用工具。
///
/// 最要紧的是「一口价折算克价」：品牌店常推「一口价」商品，
/// 折算下来能到 1500~2000 元/克，是买五金最容易吃亏的地方。
/// 这里的判定逻辑复用了 packages/goldprice_domain 里有测试覆盖的 evaluateOnePrice。
class ToolsPage extends StatefulWidget {
  final GoldRepository repository;

  const ToolsPage({super.key, required this.repository});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  late final Future<ToolsData> _future = _load();

  final TextEditingController _totalPrice = TextEditingController();
  final TextEditingController _grams = TextEditingController();
  final TextEditingController _budget = TextEditingController(text: '75000');

  @override
  void dispose() {
    _totalPrice.dispose();
    _grams.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<ToolsData> _load() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      widget.repository.loadLatest(),
      widget.repository.loadUserConfig(),
    ]);
    return ToolsData(
      snapshot: results[0] as LatestSnapshot,
      channelConfig: ChannelConfig.fromJson(results[1] as Map<String, dynamic>),
    );
  }

  double? _num(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('买金工具')),
      body: FutureBuilder<ToolsData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<ToolsData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              _onePriceCard(context, data),
              const SizedBox(height: 12),
              _budgetCard(context, data),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- 一口价

  Widget _onePriceCard(BuildContext context, ToolsData data) {
    final benchmark = data.snapshot.benchmark.close;
    final reference = data.snapshot.brandStats['gold']?.avg;

    final total = _num(_totalPrice);
    final grams = _num(_grams);

    OnePriceResult? result;
    if (total != null && grams != null && grams > 0) {
      result = evaluateOnePrice(
        totalPrice: total,
        grams: grams,
        benchmarkClose: benchmark,
        referenceGoldPrice: reference,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('一口价折算克价（防坑）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '把「一口价」商品的总价除以克重，看它到底合多少克价。'
              '很多一口价折算下来是正常首饰金的 1.2~1.5 倍。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _totalPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '总价',
                      suffixText: '元',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String _) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _grams,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '克重',
                      suffixText: '克',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String _) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null)
              Text('填入总价与克重后自动计算',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        result.pricePerGram.toStringAsFixed(0),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: result.overpriced
                                  ? Theme.of(context).colorScheme.error
                                  : Colors.green.shade700,
                            ),
                      ),
                      const SizedBox(width: 4),
                      const Text('元/克'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('大盘 ${benchmark.toStringAsFixed(2)} 元/克'),
                  if (reference != null)
                    Text('当日品牌首饰金均价 ${reference.toStringAsFixed(2)} 元/克'),
                  if (result.premiumVsReferencePct != null)
                    Text('比首饰金均价高 ${(result.premiumVsReferencePct! * 100).toStringAsFixed(1)}%'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: result.overpriced
                          ? Theme.of(context).colorScheme.errorContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(result.verdict),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 预算

  Widget _budgetCard(BuildContext context, ToolsData data) {
    final cheapest = data.snapshot.cheapestMainlandGold;
    if (cheapest == null) {
      return const Card(child: ListTile(title: Text('暂无品牌数据')));
    }

    final budget = _num(_budget) ?? data.channelConfig.budgetCny;
    final config = ChannelConfig(
      budgetCny: budget,
      targetGrams: data.channelConfig.targetGrams,
      brandStore: data.channelConfig.brandStore,
      shuibei: data.channelConfig.shuibei,
      bankBarDiy: data.channelConfig.bankBarDiy,
    );
    final cmp = compareChannels(
      benchmarkClose: data.snapshot.benchmark.close,
      brandName: cheapest.name,
      brandGold: cheapest.gold!,
      bankBarPrice: data.snapshot.cheapestBankBarPrice,
      config: config,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('预算能买多少克',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '同样的钱，不同渠道买到的克重差别很大 —— 这是本项目最想让你看到的一件事。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '预算',
                suffixText: '元',
                border: OutlineInputBorder(),
              ),
              onChanged: (String _) => setState(() {}),
            ),
            const SizedBox(height: 12),
            ...cmp.quotes.map((ChannelQuote q) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    if (q.isBest)
                      Icon(Icons.check_circle,
                          size: 16, color: Theme.of(context).colorScheme.primary)
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
                    Text('${q.costPerGram.toStringAsFixed(0)} 元/克',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 66,
                      child: Text(
                        '${q.gramsForBudget.toStringAsFixed(1)} 克',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight:
                              q.isBest ? FontWeight.bold : FontWeight.normal,
                          color: q.isBest
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 22),
            Text(
              '同样 ${budget.toStringAsFixed(0)} 元，${cmp.best.name} 能买 ${cmp.best.gramsForBudget.toStringAsFixed(1)} 克，${cmp.worst.name} 只能买 ${cmp.worst.gramsForBudget.toStringAsFixed(1)} 克，相差 ${(cmp.best.gramsForBudget - cmp.worst.gramsForBudget).toStringAsFixed(1)} 克。',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '渠道参数为假设值（可在仓库 config/user.json 调整），仅供参考。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
