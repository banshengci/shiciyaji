import 'package:flutter/material.dart';

/// 设计令牌 —— 与设计稿「诗词雅集 · 品牌视觉系统」的变量集一一对应。
///
/// 变量集（颜色 / 字体 / 尺寸）在画布上的定义即本文件的唯一来源，
/// 改色请同时改画布变量与这里，保持「设计稿 = 代码」。
///
/// 用法：
/// ```dart
/// final c = ShiciColors.of(context);   // 随明暗模式自动切换
/// Container(color: c.paper, ...);
/// ```
@immutable
class ShiciColors extends ThemeExtension<ShiciColors> {
  /// 底-宣纸：全局背景
  final Color paper;

  /// 底-绢白：卡片 / 面板
  final Color silk;

  /// 底-淡赭：选中态、次级容器、胶囊导航底
  final Color sand;

  /// 线-描边：边框与分隔线
  final Color line;

  /// 字-主
  final Color ink;

  /// 字-次
  final Color inkSoft;

  /// 字-三：弱提示、占位
  final Color inkFaint;

  /// 品牌-黛蓝
  final Color indigo;

  /// 品牌-朱砂：点睛色，全站只用于强调
  final Color cinnabar;

  /// 辅-赭石
  final Color ochre;

  /// 辅-松绿
  final Color pine;

  /// 辅-藤黄
  final Color gamboge;

  const ShiciColors({
    required this.paper,
    required this.silk,
    required this.sand,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.indigo,
    required this.cinnabar,
    required this.ochre,
    required this.pine,
    required this.gamboge,
  });

  static const ShiciColors light = ShiciColors(
    paper: Color(0xFFF5F0E8),
    silk: Color(0xFFFAF7F2),
    sand: Color(0xFFEDE5D9),
    line: Color(0xFFE0D6C4),
    ink: Color(0xFF1A2A3A),
    inkSoft: Color(0xFF6B7280),
    inkFaint: Color(0xFFA8A396),
    indigo: Color(0xFF1A2A3A),
    cinnabar: Color(0xFFC41A1A),
    ochre: Color(0xFFA8663B),
    pine: Color(0xFF4A6B52),
    gamboge: Color(0xFFC9992E),
  );

  static const ShiciColors dark = ShiciColors(
    paper: Color(0xFF12171C),
    silk: Color(0xFF1C2129),
    sand: Color(0xFF212933),
    line: Color(0xFF2B333D),
    ink: Color(0xFFF2EDE3),
    inkSoft: Color(0xFF99A3B2),
    inkFaint: Color(0xFF6E7887),
    indigo: Color(0xFF2E4257),
    cinnabar: Color(0xFFD94A3D),
    ochre: Color(0xFFA8663B),
    pine: Color(0xFF4A6B52),
    gamboge: Color(0xFFC9992E),
  );

  static ShiciColors of(BuildContext context) =>
      Theme.of(context).extension<ShiciColors>() ?? light;

  static ShiciColors ofOr(Brightness b) =>
      b == Brightness.dark ? dark : light;

  @override
  ShiciColors copyWith({
    Color? paper,
    Color? silk,
    Color? sand,
    Color? line,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? indigo,
    Color? cinnabar,
    Color? ochre,
    Color? pine,
    Color? gamboge,
  }) {
    return ShiciColors(
      paper: paper ?? this.paper,
      silk: silk ?? this.silk,
      sand: sand ?? this.sand,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      indigo: indigo ?? this.indigo,
      cinnabar: cinnabar ?? this.cinnabar,
      ochre: ochre ?? this.ochre,
      pine: pine ?? this.pine,
      gamboge: gamboge ?? this.gamboge,
    );
  }

  @override
  ShiciColors lerp(ThemeExtension<ShiciColors>? other, double t) {
    if (other is! ShiciColors) return this;
    return ShiciColors(
      paper: Color.lerp(paper, other.paper, t)!,
      silk: Color.lerp(silk, other.silk, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      indigo: Color.lerp(indigo, other.indigo, t)!,
      cinnabar: Color.lerp(cinnabar, other.cinnabar, t)!,
      ochre: Color.lerp(ochre, other.ochre, t)!,
      pine: Color.lerp(pine, other.pine, t)!,
      gamboge: Color.lerp(gamboge, other.gamboge, t)!,
    );
  }
}

/// 尺寸令牌（不随模式变化）
class ShiciSize {
  ShiciSize._();

  /// 圆角-小 / 中 / 大 / 印章 / 胶囊
  static const double rSm = 8;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rSeal = 4;
  static const double rCapsule = 999;

  /// 间距-单元 / 区块 / 页面边距
  static const double gapUnit = 4;
  static const double gapSection = 32;
  static const double pagePadding = 20;

  /// 图标-描边
  static const double iconStroke = 1.5;

  /// 图标常规尺寸（导航 / 行内）
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;

  /// 标签栏（对齐画布 3:698 标签栏）
  static const double navHeight = 95;
  static const double navCapsuleHeight = 62;
  static const double navCapsuleRadius = 36;
  static const double navItemRadius = 26;
  static const double navIconSize = 18;
}

/// 字体族令牌。
///
/// - [calligraphy] Ma Shan Zheng，仅用于标题字与印文
/// - [serif] 系统 serif；Android 上即 Noto Serif CJK，覆盖中文正文与标题
/// - [latin] Inter，只用于数字与拉丁字母（不含中文）
class ShiciFont {
  ShiciFont._();

  static const String calligraphy = 'MaShanZheng';
  static const String serif = 'serif';
  static const String latin = 'Inter';

  /// 拉丁字体遇到中文时的回退，避免数字旁的汉字掉成无衬线
  static const List<String> latinFallback = <String>[serif];
}

/// 便捷扩展：把 `context.tokens` 当成属性用
extension ShiciTokensX on BuildContext {
  ShiciColors get tokens => ShiciColors.of(this);
}
