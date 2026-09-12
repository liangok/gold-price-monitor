/// 技术指标 —— Dart 端口。
///
/// 必须与 Python 参考实现 analysis/indicators.py 语义完全一致：
///   1. 第 i 天的指标只使用 0..i 的数据（严禁未来函数）
///   2. RSI 使用 Wilder 平滑，不是简单移动平均
///   3. 分位数 = 窗口内小于等于当前价的天数占比
library;

/// 第 i 天的 n 日简单移动平均；数据不足返回 null。
double? sma(List<double> vals, int i, int n) {
  if (i + 1 < n) return null;
  var sum = 0.0;
  for (var k = i - n + 1; k <= i; k++) {
    sum += vals[k];
  }
  return sum / n;
}

/// Wilder 平滑 RSI 序列，元素可能为 null（数据不足）。
List<double?> rsiSeries(List<double> vals, [int n = 14]) {
  final out = List<double?>.filled(vals.length, null);
  if (vals.length <= n) return out;

  var gain = 0.0;
  var loss = 0.0;
  for (var k = 1; k <= n; k++) {
    final d = vals[k] - vals[k - 1];
    if (d > 0) gain += d;
    if (d < 0) loss += -d;
  }
  var ag = gain / n;
  var al = loss / n;
  out[n] = al == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + ag / al);

  for (var k = n + 1; k < vals.length; k++) {
    final d = vals[k] - vals[k - 1];
    ag = (ag * (n - 1) + (d > 0 ? d : 0.0)) / n;
    al = (al * (n - 1) + (d < 0 ? -d : 0.0)) / n;
    out[k] = al == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + ag / al);
  }
  return out;
}

/// 第 i 天往前 window 天的最大值；数据不足返回 null。
double? rollingMax(List<double> vals, int i, int window) {
  if (i + 1 < window) return null;
  var best = vals[i - window + 1];
  for (var k = i - window + 2; k <= i; k++) {
    if (vals[k] > best) best = vals[k];
  }
  return best;
}

/// 当前价在近 window 天中的分位（0~1）。
double? percentile(List<double> vals, int i, int window) {
  if (i + 1 < window) return null;
  final current = vals[i];
  var count = 0;
  for (var k = i - window + 1; k <= i; k++) {
    if (vals[k] <= current) count++;
  }
  return count / window;
}

/// 最后一天的全部指标快照。
class IndicatorSnapshot {
  final int index;
  final String date;
  final double close;
  final double? changePct;
  final double? drawdown;
  final int drawdownWindow;
  final double? percentile365;
  final int percentileWindow;
  final double? rsi;
  final Map<int, double?> movingAverages;

  const IndicatorSnapshot({
    required this.index,
    required this.date,
    required this.close,
    this.changePct,
    this.drawdown,
    required this.drawdownWindow,
    this.percentile365,
    required this.percentileWindow,
    this.rsi,
    required this.movingAverages,
  });

  double? ma(int window) => movingAverages[window];
}

IndicatorSnapshot? computeLatest(
  List<double> vals,
  List<String> dates, {
  int drawdownWindow = 90,
  int percentileWindow = 365,
  int rsiN = 14,
  List<int> maWindows = const [20, 60],
}) {
  if (vals.isEmpty) return null;
  final i = vals.length - 1;
  final hi = rollingMax(vals, i, drawdownWindow);
  final rsiAll = rsiSeries(vals, rsiN);
  final mas = <int, double?>{};
  for (final w in maWindows) {
    mas[w] = sma(vals, i, w);
  }
  return IndicatorSnapshot(
    index: i,
    date: i >= 0 && i < dates.length ? dates[i] : '',
    close: vals[i],
    changePct: i >= 1 ? vals[i] / vals[i - 1] - 1.0 : null,
    drawdown: hi == null ? null : vals[i] / hi - 1.0,
    drawdownWindow: drawdownWindow,
    percentile365: percentile(vals, i, percentileWindow),
    percentileWindow: percentileWindow,
    rsi: rsiAll[i],
    movingAverages: mas,
  );
}
