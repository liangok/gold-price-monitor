import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';

import '../theme.dart';

/// iOS 风格的「开关行」：左侧标题/副标题，右侧系统开关。
class IosSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const IosSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: IosColors.label)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          fontSize: 12.5, color: IosColors.secondaryLabel)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          cupertino.CupertinoSwitch(
            value: value,
            activeTrackColor: IosColors.gold,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// iOS 风格的「可点击行」：图标 + 标题/副标题 + 右侧箭头。
class IosRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback? onTap;

  const IosRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Icon(icon,
                size: 20,
                color: enabled ? IosColors.gold : IosColors.tertiaryLabel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? IosColors.label
                          : IosColors.secondaryLabel,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12.5, color: IosColors.secondaryLabel)),
                  ],
                ],
              ),
            ),
            if (trailingText != null)
              Text(trailingText!,
                  style: const TextStyle(
                      fontSize: 13, color: IosColors.secondaryLabel)),
            if (enabled) ...<Widget>[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: IosColors.tertiaryLabel),
            ],
          ],
        ),
      ),
    );
  }
}

/// 卡片内部的分隔线：左侧留出图标宽度，与 iOS 分组列表一致。
class IosSeparator extends StatelessWidget {
  final double indent;

  const IosSeparator({super.key, this.indent = 16});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const Divider(height: 1, thickness: 0.5, color: IosColors.separator),
    );
  }
}
