import 'dart:async';

import 'package:flutter/material.dart';

/// 可交互的折线图（零第三方依赖，用 CustomPainter 手绘）。
///
/// 交互：**点按或左右拖动**会显示竖直十字线与该点的数值卡片；
/// 松手约 2.5 秒后自动淡出。数据动辄两千多个点，命中测试直接用
/// \`(x / width * (n-1)).round()\` 即可，无需空间索引。
class PriceLineChart extends StatefulWidget {
  final List<double> values;

  /// 与 [values] 一一对应的标签（通常是日期），用于交互时显示。
  final List<String> labels;
  final Color lineColor;
  final double? averageLine;
  final String unit;

  const PriceLineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.lineColor,
    this.averageLine,
    this.unit = '',
  });

  @override
  State<PriceLineChart> createState() => _PriceLineChartState();
}

class _PriceLineChartState extends State<PriceLineChart> {
  static const double _tooltipWidth = 138;

  int? _activeIndex;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _selectAt(double dx, double width) {
    final int n = widget.values.length;
    if (n < 2 || width <= 0) return;
    final int index = ((dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _activeIndex = null);
    });
  }

  String _label(int index) {
    if (index < widget.labels.length) return widget.labels[index];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int? active = _activeIndex;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) {
            _selectAt(d.localPosition.dx, width);
            _scheduleHide();
          },
          onHorizontalDragStart: (DragStartDetails d) {
            _hideTimer?.cancel();
            _selectAt(d.localPosition.dx, width);
          },
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _selectAt(d.localPosition.dx, width),
          onHorizontalDragEnd: (DragEndDetails _) => _scheduleHide(),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _LinePainter(
                    values: widget.values,
                    lineColor: widget.lineColor,
                    averageLine: widget.averageLine,
                    gridColor: theme.dividerColor,
                    labelColor: theme.textTheme.bodySmall?.color ??
                        theme.colorScheme.onSurfaceVariant,
                    activeIndex: active,
                  ),
                ),
              ),
              if (active != null)
                Positioned(
                  top: 0,
                  left: _tooltipLeft(active, width),
                  width: _tooltipWidth,
                  child: _Tooltip(
                    date: _label(active),
                    value: widget.values[active],
                    unit: widget.unit,
                    previous: active > 0 ? widget.values[active - 1] : null,
                    accent: widget.lineColor,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _tooltipLeft(int index, double width) {
    final int n = widget.values.length;
    final double x = n <= 1 ? 0 : index / (n - 1) * width;
    return (x - _tooltipWidth / 2).clamp(0.0, (width - _tooltipWidth).clamp(0.0, width));
  }
}

/// 交互时浮出的数值卡片。
class _Tooltip extends StatelessWidget {
  final String date;
  final double value;
  final String unit;
  final double? previous;
  final Color accent;

  const _Tooltip({
    required this.date,
    required this.value,
    required this.unit,
    required this.accent,
    this.previous,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    double? changePct;
    if (previous != null && previous != 0) {
      changePct = value / previous! - 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            date,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          if (changePct != null)
            Text(
              '${changePct >= 0 ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: changePct >= 0
                    ? const Color(0xFFD23B3B)
                    : const Color(0xFF1E9E5A),
              ),
            ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final double? averageLine;
  final int? activeIndex;

  _LinePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    this.averageLine,
    this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    double minValue = values.first;
    double maxValue = values.first;
    for (final double v in values) {
      if (v < minValue) minValue = v;
      if (v > maxValue) maxValue = v;
    }
    if (averageLine != null) {
      if (averageLine! < minValue) minValue = averageLine!;
      if (averageLine! > maxValue) maxValue = averageLine!;
    }
    final double span =
        (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;
    final double padding = span * 0.10;
    final double lo = minValue - padding;
    final double hi = maxValue + padding;

    double yOf(double value) => size.height - (value - lo) / (hi - lo) * size.height;
    double xOf(int i) =>
        values.length == 1 ? 0 : i / (values.length - 1) * size.width;

    // ── 网格：3 条细线，透明度很低（iOS 风格不喧宾夺主）
    final Paint grid = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 2; i++) {
      final double y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // ── 均线
    if (averageLine != null) {
      canvas.drawLine(
        Offset(0, yOf(averageLine!)),
        Offset(size.width, yOf(averageLine!)),
        Paint()
          ..color = const Color(0xFFE8A33D).withValues(alpha: 0.9)
          ..strokeWidth = 1.2,
      );
    }

    // ── 折线 + 渐变填充
    final Path path = Path()..moveTo(xOf(0), yOf(values[0]));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    final Path fill = Path.from(path)
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
            lineColor.withValues(alpha: 0.22),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // ── 最高 / 最低价刻度（左上、左下）
    _drawText(canvas, maxValue.toStringAsFixed(2), const Offset(4, 2));
    _drawText(canvas, minValue.toStringAsFixed(2),
        Offset(4, size.height - 14));

    // ── 交互：竖直十字线 + 高亮点
    final int? index = activeIndex;
    if (index != null && index >= 0 && index < values.length) {
      final double x = xOf(index);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = lineColor.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
      final Offset point = Offset(x, yOf(values[index]));
      canvas.drawCircle(
        point,
        6,
        Paint()..color = lineColor.withValues(alpha: 0.18),
      );
      canvas.drawCircle(point, 3.2, Paint()..color = lineColor);
      canvas.drawCircle(
        point,
        1.4,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset at) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor.withValues(alpha: 0.85),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values ||
      old.averageLine != averageLine ||
      old.activeIndex != activeIndex ||
      old.lineColor != lineColor;
}
