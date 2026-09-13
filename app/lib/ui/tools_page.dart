import 'dart:async';

import 'package:flutter/material.dart';
import 'package:goldprice_domain/goldprice_domain.dart';

import '../data/repository.dart';
import '../services/plan_store.dart';
import 'widgets/ios_card.dart';

class ToolsData {
  final LatestSnapshot snapshot;
  final ChannelConfig channelConfig;
  final GoldPlan plan;

  const ToolsData({
    required this.snapshot,
    required this.channelConfig,
    required this.plan,
  });
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
  final TextEditingController _totalPrice = TextEditingController();
  final TextEditingController _grams = TextEditingController();
  final TextEditingController _budget = TextEditingController(text: '75000');

  /// 五金清单：逐件的克重与工费输入框
  final List<TextEditingController> _gramsControllers =
      <TextEditingController>[];
  final List<TextEditingController> _laborControllers =
      <TextEditingController>[];
  GoldPlan? _plan;

  late final Future<ToolsData> _future = _load();

  @override
  void dispose() {
    _totalPrice.dispose();
    _grams.dispose();
    _budget.dispose();
    for (final TextEditingController c in _gramsControllers) {
      c.dispose();
    }
    for (final TextEditingController c in _laborControllers) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  void _updatePiece(int index, {double? grams, double? labor}) {
    final GoldPlan? plan = _plan;
    if (plan == null || index < 0 || index >= plan.pieces.length) return;
    final GoldPiece piece = plan.pieces[index];
    final GoldPlan updated = plan.withPiece(
      index,
      piece.copyWith(
        grams: grams ?? piece.grams,
        laborPerGram: labor ?? piece.laborPerGram,
      ),
    );
    setState(() => _plan = updated);
    unawaited(PlanStore.save(updated));
  }

  Future<ToolsData> _load() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      widget.repository.loadLatest(),
      widget.repository.loadUserConfig(),
    ]);
    final GoldPlan plan = await PlanStore.load();
    for (final GoldPiece piece in plan.pieces) {
      _gramsControllers.add(
          TextEditingController(text: _trimNumber(piece.grams)));
      _laborControllers.add(
          TextEditingController(text: _trimNumber(piece.laborPerGram)));
    }
    return ToolsData(
      snapshot: results[0] as LatestSnapshot,
      channelConfig: ChannelConfig.fromJson(results[1] as Map<String, dynamic>),
      plan: plan,
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
              const SizedBox(height: 12),
              _planCard(context, data),
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

    return IosCard(
      title: '一口价折算克价',
      info: '把「一口价」商品的总价除以克重，看它到底合多少克价。'
          '很多一口价折算下来是正常首饰金的 1.2~1.5 倍，是买五金最容易吃亏的地方。',
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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

    return IosCard(
      title: '预算能买多少克',
      info: '同样的钱，不同渠道买到的克重差别很大 —— 这是本项目最想让你看到的一件事。'
          '渠道克价为可调假设值，见仓库 config/user.json。',
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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

          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 五金清单

  void _resetPlan() {
    final GoldPlan fresh = GoldPlan.weddingFive;
    for (var i = 0;
        i < fresh.pieces.length && i < _gramsControllers.length;
        i++) {
      _gramsControllers[i].text = _trimNumber(fresh.pieces[i].grams);
      _laborControllers[i].text = _trimNumber(fresh.pieces[i].laborPerGram);
    }
    setState(() => _plan = fresh);
    unawaited(PlanStore.save(fresh));
  }

  Widget _planCard(BuildContext context, ToolsData data) {
    final GoldPlan plan = _plan ?? data.plan;
    final BrandQuote? cheapest = data.snapshot.cheapestMainlandGold;
    if (cheapest == null) {
      return const Card(child: ListTile(title: Text('暂无品牌数据')));
    }

    final List<PlanChannelCost> costs = pricePlan(
      plan: plan,
      benchmarkClose: data.snapshot.benchmark.close,
      brandName: cheapest.name,
      brandGold: cheapest.gold!,
      bankBarPrice: data.snapshot.cheapestBankBarPrice,
      config: data.channelConfig,
    );
    PlanChannelCost best = costs.first;
    PlanChannelCost worst = costs.first;
    for (final PlanChannelCost c in costs) {
      if (c.total < best.total) best = c;
      if (c.total > worst.total) worst = c;
    }
    final double gap = worst.total - best.total;

    return IosCard(
      title: '五金清单',
      info: '逐件录入你的五金，算出整份清单在各渠道要花多少钱。'
          '工费按每件填 —— 古法金、3D 硬金差别很大。',
      padding: EdgeInsets.zero,
      trailing: TextButton(
        onPressed: _resetPlan,
        child: const Text('恢复默认'),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: const <Widget>[
                Expanded(
                    flex: 3,
                    child: Text('首饰',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 3,
                    child: Text('克重',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(width: 6),
                Expanded(
                    flex: 3,
                    child: Text('工费/克',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            ...List<Widget>.generate(plan.pieces.length, (int i) {
              final GoldPiece piece = plan.pieces[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(flex: 3, child: Text(piece.name)),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _gramsControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                            isDense: true, border: OutlineInputBorder()),
                        onChanged: (String value) =>
                            _updatePiece(i, grams: double.tryParse(value)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _laborControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                            isDense: true, border: OutlineInputBorder()),
                        onChanged: (String value) =>
                            _updatePiece(i, labor: double.tryParse(value)),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 22),
            Text(
              '合计 ${plan.totalGrams.toStringAsFixed(1)} 克，品牌店工费合计 ${plan.totalLaborAtBrandPrice.toStringAsFixed(0)} 元',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...costs.map((PlanChannelCost c) {
              final bool isBest = identical(c, best);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    if (isBest)
                      Icon(Icons.check_circle,
                          size: 16, color: Theme.of(context).colorScheme.primary)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(c.channelName,
                          style: TextStyle(
                              fontWeight: isBest
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ),
                    Text('${c.costPerGram.toStringAsFixed(0)} 元/克',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 84,
                      child: Text('${c.total.toStringAsFixed(0)} 元',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight:
                                isBest ? FontWeight.bold : FontWeight.normal,
                            color: isBest
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          )),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 22),
            Text(
              '整份清单：${worst.channelName} 约 ${worst.total.toStringAsFixed(0)} 元，'
              '${best.channelName} 约 ${best.total.toStringAsFixed(0)} 元，'
              '相差 ${gap.toStringAsFixed(0)} 元（${(gap / worst.total * 100).toStringAsFixed(0)}%）。',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '品牌店工费按你逐件填写；水贝与打金的工费取自渠道假设值（config/user.json）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
