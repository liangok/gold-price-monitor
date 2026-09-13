/// iOS 风格的设计常量。
///
/// 只承载「视觉」，不含业务逻辑 —— 各页面统一引用，避免颜色/圆角/间距各写一套。
library;

import 'package:flutter/material.dart';

class IosColors {
  /// 类似 iOS 的 systemGroupedBackground：灰底 + 白卡片是 iOS 分组列表的标志。
  static const Color pageBackground = Color(0xFFF2F2F7);
  static const Color card = Color(0xFFFFFFFF);

  /// systemFill 那种极淡的分隔线。
  static const Color separator = Color(0x1F3C3C43);

  static const Color label = Color(0xFF1C1C1E);
  static const Color secondaryLabel = Color(0xFF8A8A8E);
  static const Color tertiaryLabel = Color(0xFFC7C7CC);

  /// 品牌色：金
  static const Color gold = Color(0xFFB8860B);
  static const Color goldSoft = Color(0xFFF6EFDC);

  /// 国内习惯：涨红跌绿
  static const Color up = Color(0xFFD23B3B);
  static const Color down = Color(0xFF1E9E5A);

  static const Color barTrack = Color(0x14000000);
}

class IosMetrics {
  static const double pagePadding = 16;
  static const double cardRadius = 14;
  static const double cardGap = 12;
  static const double cardPadding = 16;
  static const double sectionGap = 24;
}

/// 卡片装饰：扁平白卡 + 大圆角，可选极淡投影。
BoxDecoration iosCardDecoration({bool elevated = false}) {
  return BoxDecoration(
    color: IosColors.card,
    borderRadius: BorderRadius.circular(IosMetrics.cardRadius),
    boxShadow: elevated
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ]
        : null,
  );
}

/// App 主题：浅灰底、白卡、金作为 tint，尽量贴近 iOS 的克制感。
ThemeData buildIosLikeTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: IosColors.gold,
    brightness: Brightness.light,
  ).copyWith(
    surface: IosColors.card,
    onSurface: IosColors.label,
    primary: IosColors.gold,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: IosColors.pageBackground,
    dividerColor: IosColors.separator,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: IosColors.pageBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: IosColors.label,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    textTheme: const TextTheme(
      titleMedium: TextStyle(color: IosColors.label, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: IosColors.label),
      bodySmall: TextStyle(color: IosColors.secondaryLabel, height: 1.35),
      labelSmall: TextStyle(color: IosColors.secondaryLabel),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
