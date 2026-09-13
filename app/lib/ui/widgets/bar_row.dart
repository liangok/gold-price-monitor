import 'package:flutter/material.dart';

import '../theme.dart';

/// 一条带长度的横条 —— 用「长度」代替「读数字」。
///
/// 用在渠道对比、品牌比价这类「一堆数字排队」的场景，
/// 一眼就能看出谁长谁短，不必逐行比大小。
class BarRow extends StatelessWidget {
  final String label;
  final String valueText;

  /// 0~1，条长比例。通常用「当前值 / 最大值」。
  final double fraction;

  final bool highlight;
  final Color color;

  const BarRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.fraction,
    this.highlight = false,
    this.color = IosColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    final double f = fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                    color: IosColors.label,
                  ),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  color: highlight ? color : IosColors.secondaryLabel,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: <Widget>[
                Container(height: 6, color: IosColors.barTrack),
                FractionallySizedBox(
                  widthFactor: f,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: highlight
                          ? color
                          : color.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
