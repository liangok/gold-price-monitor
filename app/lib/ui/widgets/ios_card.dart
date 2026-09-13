import 'package:flutter/material.dart';

import '../theme.dart';

/// iOS 风格卡片。
///
/// 关键作用是**承载信息分层**：标题旁的「?」可以把原来摊在界面上的说明文字
/// 收起来，点一下才展开。这样主界面只留数据，长解释不再挤占视线。
class IosCard extends StatelessWidget {
  final String? title;

  /// 说明文字。非空时标题右侧会出现「?」，点击弹出。
  final String? info;

  /// 标题右侧的附加内容（例如一个数值或按钮）。
  final Widget? trailing;

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool elevated;

  const IosCard({
    super.key,
    this.title,
    this.info,
    this.trailing,
    required this.child,
    this.padding,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasHeader = title != null || trailing != null;
    return Container(
      decoration: iosCardDecoration(elevated: elevated),
      padding: padding ?? const EdgeInsets.all(IosMetrics.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasHeader) ...<Widget>[
            Row(
              children: <Widget>[
                if (title != null)
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: IosColors.label,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (info != null) _InfoButton(text: info!),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// 「?」按钮：把说明文字收进弹窗。
class _InfoButton extends StatelessWidget {
  final String text;

  const _InfoButton({required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.only(left: 6),
        child: Icon(
          Icons.help_outline,
          size: 16,
          color: IosColors.tertiaryLabel,
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: IosColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosMetrics.cardRadius),
        ),
        title: const Text('说明', style: TextStyle(fontSize: 17)),
        content: Text(text, style: const TextStyle(height: 1.45)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
