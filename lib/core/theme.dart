import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'design_tokens.dart';

/// 新中式 (Neo-Chinese) 设计主题。
///
/// 色彩 / 字体 / 尺寸的**唯一来源**是 [ShiciColors]、[ShiciFont]、[ShiciSize]
/// （对应设计稿画布上的同名变量集）。本文件只负责把它们装配成 ThemeData。
///
/// 下面的 `static const Color xxx` 是历史兼容别名 —— 旧代码直接引用它们，
/// 值已与令牌对齐，并由 `test/design_tokens_test.dart` 断言一致。
/// **新代码请用 `ShiciColors.of(context)`**，以便自动跟随明暗模式。
class AppTheme {
  // 核心色彩（= ShiciColors.light 对应项）
  static const Color daiLan = Color(0xFF1A2A3A); // 品牌-黛蓝 / 字-主
  static const Color xuanZhiBai = Color(0xFFF5F0E8); // 底-宣纸
  static const Color zhuShaHong = Color(0xFFC41A1A); // 品牌-朱砂
  static const Color moHei = Color(0xFF1A2A3A); // 墨黑（并入字-主）
  static const Color qingHui = Color(0xFF6B7280); // 字-次
  static const Color danHuang = Color(0xFFFAF7F2); // 底-绢白

  // 扩展色彩（图表/装饰用）
  static const Color qingCang = Color(0xFF4F6F8F); // 苍青
  static const Color shiHuang = Color(0xFF7E601B); // 辅-藤黄（原石黄）
  static const Color songLv = Color(0xFF4A6B52); // 辅-松绿
  static const Color tongSe = Color(0xFF925933); // 辅-赭石（原铜色）
  static const Color yaBai = Color(0xFF8D8776); // 字-三

  // 深色（= ShiciColors.dark 对应项）
  static const Color darkSurface = Color(0xFF12171C);
  static const Color darkCard = Color(0xFF1C2129);
  static const Color darkText = Color(0xFFF2EDE3);

  // ====== Material ThemeData ======
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c = ShiciColors.ofOr(brightness);
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.paper,
      extensions: <ThemeExtension<dynamic>>[c],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.indigo,
        // 品牌色在深色下会变亮、在浅色下是深色，因此压在它上面的前景必须跟着翻转。
        // 这里统一走 onAccent，不要用 silk/paper —— 那是「卡片底色」的语义。
        onPrimary: c.onAccent,
        secondary: c.cinnabar,
        onSecondary: c.onAccent,
        error: c.cinnabar,
        onError: c.onAccent,
        surface: c.silk,
        onSurface: c.ink,
        surfaceContainerHighest: c.sand,
        outline: c.line,
        outlineVariant: c.line,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: ShiciText.title.copyWith(color: c.ink),
      ),
      cardTheme: CardTheme(
        color: c.silk,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          side: BorderSide(color: c.line),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: c.silk,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.silk,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ShiciSize.rLg),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: ShiciText.heading.copyWith(color: c.onAccent),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.silk,
        selectedColor: c.sand,
        side: BorderSide(color: c.line),
        labelStyle: ShiciText.caption.copyWith(color: c.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.silk,
        hintStyle: ShiciText.body.copyWith(color: c.inkFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          borderSide: BorderSide(color: c.cinnabar, width: 1.2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.cinnabar,
        linearTrackColor: c.sand,
        circularTrackColor: c.sand,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.indigo,
          textStyle: ShiciText.heading,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.indigo,
          foregroundColor: c.onAccent,
          textStyle: ShiciText.heading,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.indigo,
          side: BorderSide(color: c.line),
          textStyle: ShiciText.heading,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkSoft,
        textColor: c.ink,
        titleTextStyle: ShiciText.heading.copyWith(color: c.ink),
        subtitleTextStyle: ShiciText.caption.copyWith(color: c.inkSoft),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: c.cinnabar,
        unselectedLabelColor: c.inkSoft,
        indicatorColor: c.cinnabar,
        dividerColor: c.line,
        labelStyle: ShiciText.heading.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: ShiciText.heading,
      ),
      textTheme: _textTheme(c, isLight),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.paper,
        selectedItemColor: c.cinnabar,
        unselectedItemColor: c.inkSoft,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static TextTheme _textTheme(ShiciColors c, bool isLight) {
    return TextTheme(
      headlineLarge: ShiciText.display.copyWith(color: c.ink),
      headlineMedium:
          ShiciText.display.copyWith(fontSize: 26, color: c.ink),
      titleLarge: ShiciText.title.copyWith(color: c.ink),
      titleMedium: ShiciText.heading.copyWith(color: c.ink),
      titleSmall: ShiciText.heading
          .copyWith(fontSize: 14, color: c.inkSoft),
      bodyLarge: ShiciText.body.copyWith(fontSize: 16, color: c.ink),
      bodyMedium: ShiciText.body.copyWith(color: c.ink),
      bodySmall: ShiciText.caption.copyWith(color: c.inkSoft),
      labelLarge: ShiciText.heading.copyWith(color: c.indigo),
      labelMedium: ShiciText.caption.copyWith(color: c.inkSoft),
      labelSmall: ShiciText.tag.copyWith(color: c.inkSoft),
    );
  }

  // ====== Shadcn UI ThemeData（新中式配色） ======
  static ShadThemeData shadLight() => ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadColorScheme(
          background: xuanZhiBai,
          foreground: moHei,
          card: Color(0xFFFAF7F2),
          cardForeground: moHei,
          popover: Color(0xFFFAF7F2),
          popoverForeground: moHei,
          primary: daiLan,
          primaryForeground: Color(0xFFFAF7F2),
          secondary: Color(0xFFEDE5D9),
          secondaryForeground: moHei,
          muted: Color(0xFFEDE5D9),
          mutedForeground: qingHui,
          accent: qingCang,
          accentForeground: Colors.white,
          destructive: zhuShaHong,
          destructiveForeground: Colors.white,
          border: Color(0xFFE0D6C4),
          input: Color(0xFFE0D6C4),
          ring: daiLan,
          selection: Color(0x4F1A2A3A), // 黛蓝 30%
        ),
        textTheme: ShadTextTheme(family: ShiciFont.serif),
        radius: const BorderRadius.all(Radius.circular(ShiciSize.rMd)),
      );

  static ShadThemeData shadDark() => ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadColorScheme(
          background: darkSurface,
          foreground: darkText,
          card: darkCard,
          cardForeground: darkText,
          popover: darkCard,
          popoverForeground: darkText,
          // 深色下黛蓝抬到月白；压在它上的前景随之由宣纸白改为墨底
          primary: Color(0xFF6F96BE),
          primaryForeground: Color(0xFF12171C),
          secondary: Color(0xFF212933),
          secondaryForeground: darkText,
          muted: Color(0xFF212933),
          mutedForeground: Color(0xFF99A3B2),
          accent: qingCang,
          accentForeground: Colors.white,
          destructive: Color(0xFFEB6767),
          destructiveForeground: Color(0xFF12171C),
          border: Color(0xFF2B333D),
          input: Color(0xFF2B333D),
          ring: Color(0xFF6F96BE),
          selection: Color(0x4F6F96BE),
        ),
        textTheme: ShadTextTheme(family: ShiciFont.serif),
        radius: const BorderRadius.all(Radius.circular(ShiciSize.rMd)),
      );
}

/// 文字层级 —— 设计稿「字体层级 7 档」的代码对应。
///
/// 全站只用三款字体：书法标题（[ShiciFont.calligraphy]）、
/// 宋体正文（[ShiciFont.serif]）、数字英文（[ShiciFont.latin]）。
/// 下面七档默认走 [ShiciFont.serif]，只在字标/巨号数字处显式换字体。
class ShiciText {
  ShiciText._();

  /// 1 · 巨号标题：页面主标题、启动页字标
  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontFamily: ShiciFont.serif,
    letterSpacing: 1.0,
  );

  /// 2 · 区块标题 / AppBar
  static const TextStyle title = TextStyle(
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w600,
    fontFamily: ShiciFont.serif,
    letterSpacing: 0.4,
  );

  /// 3 · 区块副标题
  static const TextStyle subtitle = TextStyle(
    fontSize: 17,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontFamily: ShiciFont.serif,
    letterSpacing: 0.2,
  );

  /// 4 · 卡片 / 列表主文本
  static const TextStyle heading = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w600,
    fontFamily: ShiciFont.serif,
  );

  /// 5 · 正文（行高 1.8，便于长诗阅读）
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.8,
    fontWeight: FontWeight.w400,
    fontFamily: ShiciFont.serif,
  );

  /// 6 · 辅助说明
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontFamily: ShiciFont.serif,
  );

  /// 7 · 标签 / 角标
  static const TextStyle tag = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w500,
    fontFamily: ShiciFont.serif,
  );

  /// 书法字标：品牌名、「雅」印文、巨号数字
  static const TextStyle calligraphy = TextStyle(
    fontFamily: ShiciFont.calligraphy,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );

  /// 数字与拉丁字母（仅用于不含中文的字符串）
  static const TextStyle numeral = TextStyle(
    fontFamily: ShiciFont.latin,
    fontFamilyFallback: ShiciFont.latinFallback,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
  );
}
