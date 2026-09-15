import 'dart:math' as math;

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

  /// 苍青 —— 图表 / 装饰用，取「远山青」而非品牌黛蓝，避免与宋色撞车
  final Color cerulean;

  /// 古铜 —— 图表 / 装饰用，比藤黄更沉、比赭石更冷
  final Color bronze;

  /// 前景-on实色：压在**品牌实色块**（朱砂 / 黛蓝 / 松绿 … 的实心填充）上的文字与图标。
  ///
  /// 必须与 [silk] 分开：品牌色在深色模式下会**变亮**，压在它上面的前景就得**变暗**，
  /// 而 `silk` 的语义是「卡片底色」，两者只是数值上碰巧接近，不该互相顶替。
  /// 浅色 = 绢白，深色 = 墨底。
  final Color onAccent;

  /// 前景-on深块：压在**固定深色块**（[deepFrom]→[deepTo] 渐变）上的文字与图标。
  ///
  /// 这类底色不随明暗模式变化（导出的分享图要可复现），所以前景也**不随模式变化** ——
  /// 浅色模式下用 `paper` 恰好对，深色模式下就会变成墨字压黛蓝、直接看不见。
  final Color onDeep;

  /// 深色块渐变起点 / 终点 —— 首页「今日推荐」与分享卡同源的那张黛蓝卡。
  ///
  /// 浅色模式沿用品牌原值；深色模式整体抬一档，否则卡片与墨底页面糊成一片。
  final Color deepFrom;
  final Color deepTo;

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
    required this.cerulean,
    required this.bronze,
    required this.onAccent,
    required this.onDeep,
    required this.deepFrom,
    required this.deepTo,
  });

  /// 浅色 —— 宣纸白底上的水墨配色。
  ///
  /// 五个品牌/朝代色的取值不是「挑好看的」，而是按「压在绢白卡面上的对比度 ≥ 4.5:1」
  /// 反解出来的（见 `test/design_system_test.dart` 的可读性守卫）。
  /// 选色时优先保住色相，只降明度 —— 藤黄天生明度高，在纸白底上只能压成深橄榄金。
  static const ShiciColors light = ShiciColors(
    paper: Color(0xFFF5F0E8),
    silk: Color(0xFFFAF7F2),
    sand: Color(0xFFEDE5D9),
    line: Color(0xFFE0D6C4),
    ink: Color(0xFF1A2A3A),
    inkSoft: Color(0xFF6B7280),
    // 字-三：弱提示层。按 WCAG 图形/大字门槛 3.3:1 取值，不按正文 4.5:1，
    // 否则会与字-次挤成同一级灰阶，三级层次当场塌掉。
    inkFaint: Color(0xFF8D8776),
    indigo: Color(0xFF1A2A3A),
    cinnabar: Color(0xFFC41A1A),
    ochre: Color(0xFF925933),
    pine: Color(0xFF4A6B52),
    gamboge: Color(0xFF7E601B),
    cerulean: Color(0xFF4F6F8F),
    bronze: Color(0xFF8B6914),
    onAccent: Color(0xFFFAF7F2),
    onDeep: Color(0xFFF5F0E8),
    deepFrom: Color(0xFF1A293B),
    deepTo: Color(0xFF2E4257),
  );

  /// 深色 —— 墨底上的配色。
  ///
  /// **朝代色在深底上必须单独定值。** 墨底 #12171C 的明度只有 0.015，同一批色相在
  /// 浅底上够用的明度（藤黄 2.4:1、松绿 2.7:1、黛蓝 1.6:1）到深底上会整体翻车：
  /// 色带糊进卡面、徽记看不清、实心胶囊变成深字压深底。
  ///
  /// 解法不是「把颜色调亮」这么粗暴 —— 高彩度色一提亮就褪成粉。定值规则是
  /// **锁死原色相与原彩度，只抬明度**，一路抬到四个真实用法同时过线：
  /// 徽记字 / 色带 / 实心胶囊 / 页面底图标。结果是一组「旧绢上的矿物色」：
  /// 朱砂转珊瑚、黛蓝转月白、松绿转苔绿、赭石转陶土、藤黄转琥珀。
  static const ShiciColors dark = ShiciColors(
    paper: Color(0xFF12171C),
    silk: Color(0xFF1C2129),
    sand: Color(0xFF212933),
    line: Color(0xFF2B333D),
    ink: Color(0xFFF2EDE3),
    inkSoft: Color(0xFF99A3B2),
    inkFaint: Color(0xFF6E7887),
    indigo: Color(0xFF6F96BE),
    cinnabar: Color(0xFFEB6767),
    ochre: Color(0xFFC48358),
    pine: Color(0xFF719D7B),
    gamboge: Color(0xFFB78B2A),
    cerulean: Color(0xFF6BB8CE),
    bronze: Color(0xFFD9A24F),
    onAccent: Color(0xFF12171C),
    onDeep: Color(0xFFF5F0E8),
    deepFrom: Color(0xFF23334D),
    deepTo: Color(0xFF354962),
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
    Color? cerulean,
    Color? bronze,
    Color? onAccent,
    Color? onDeep,
    Color? deepFrom,
    Color? deepTo,
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
      cerulean: cerulean ?? this.cerulean,
      bronze: bronze ?? this.bronze,
      onAccent: onAccent ?? this.onAccent,
      onDeep: onDeep ?? this.onDeep,
      deepFrom: deepFrom ?? this.deepFrom,
      deepTo: deepTo ?? this.deepTo,
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
      cerulean: Color.lerp(cerulean, other.cerulean, t)!,
      bronze: Color.lerp(bronze, other.bronze, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      onDeep: Color.lerp(onDeep, other.onDeep, t)!,
      deepFrom: Color.lerp(deepFrom, other.deepFrom, t)!,
      deepTo: Color.lerp(deepTo, other.deepTo, t)!,
    );
  }
}

/// 对比度核算 —— WCAG 2.1 相对亮度与对比度比值。
///
/// 存在的意义：**配色不该靠眼睛定**。深色模式尤其如此，同一个色相在墨底上
/// 视觉判断与数值判断经常相反（朱砂在 #12171C 上「看着还行」，实测只有 3.85:1）。
/// 调色时先跑一遍这里，`test/design_system_test.dart` 也用同一份实现守门，
/// 避免测试与实现各写一套算法后互相跑偏。
class ShiciContrast {
  ShiciContrast._();

  /// 单通道线性化
  static double _channel(double v) {
    v = v / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  /// 相对亮度 0~1
  ///
  /// ⚠️ 注意 `Color.red/green/blue` 是 **0~255 的整数**，不是 0~1 的小数
  /// （0~1 的那个访问器叫 `.r/.g/.b`）。早先这里多乘了一次 255，导致
  /// 黑白对比度算成 1049 万而不是 21 —— 数值全错但大小关系仍在，
  /// 所以「守卫」看着是通过的。这个 bug 是靠像素复核时比对参考值才翻出来的。
  static double luminance(Color c) {
    final r = _channel(c.red.toDouble());
    final g = _channel(c.green.toDouble());
    final b = _channel(c.blue.toDouble());
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// 对比度 1~21
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 前景按 [alpha] 压在 [background] 上之后的实际颜色 ——
  /// `withOpacity` 的合成结果，用来核算「色调底纹上的同色字」这类场景。
  static Color composite(Color foreground, double alpha, Color background) {
    return Color.fromARGB(
      255,
      (foreground.red * alpha + background.red * (1 - alpha)).round(),
      (foreground.green * alpha + background.green * (1 - alpha)).round(),
      (foreground.blue * alpha + background.blue * (1 - alpha)).round(),
    );
  }

  /// 正文级门槛
  static const double aaText = 4.5;

  /// 图形与大字级门槛
  static const double aaGraphic = 3.0;

  /// 弱提示层（字-三）采用的折中门槛
  static const double faint = 3.3;
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
