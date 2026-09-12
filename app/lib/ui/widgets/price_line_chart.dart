import 'package:flutter/material.dart';

/// 轻量折线图 —— 用 CustomPainter 实现，避免引入第三方图表依赖。
///
/// 之所以不直接用 fl_chart：v1 希望「零第三方依赖」先把 App 跑起来，
/// 图表能力后续再按需要替换。
class PriceLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final double? averageLine;

  const PriceLineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.lineColor,
    this.averageLine,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        values: values,
        lineColor: lineColor,
        averageLine: averageLine,
        gridColor: Theme.of(context).dividerColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final double? averageLine;

  _LinePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    this.averageLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var minValue = values.first;
    var maxValue = values.first;
    for (final v in values) {
      if (v < minValue) minValue = v;
      if (v > maxValue) maxValue = v;
    }
    if (averageLine != null) {
      if (averageLine! < minValue) minValue = averageLine!;
      if (averageLine! > maxValue) maxValue = averageLine!;
    }
    final span = (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;
    final padding = span * 0.08;
    minValue -= padding;
    maxValue += padding;

    double yOf(double value) =>
        size.height - (value - minValue) / (maxValue - minValue) * size.height;
    double xOf(int i) => values.length == 1
        ? 0
        : i / (values.length - 1) * size.width;

    // 横向网格
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 均线
    if (averageLine != null) {
      final maPaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      final y = yOf(averageLine!);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), maPaint);
    }

    // 价格折线 + 渐变填充
    final path = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.averageLine != averageLine;
}
