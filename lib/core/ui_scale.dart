import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局字号 —— 「设置 → 阅读设置 → 全局字号」的唯一数据源。
///
/// 与 `font_size`（诗词正文字号，单位 px）**语义完全不同**，别把两者混起来：
///
/// - `font_size`（16 / 18 / 22 / 26）：只乘在**诗词正文**上的阅读页专用字号；
/// - 本类：**全站文本缩放因子**，作用在整棵 Widget 树的 `MediaQuery.textScaler`
///   上 —— 导航标签、卡片标题、按钮、弹窗、设置项、诗词正文一并生效。
///
/// 两者会**相乘**：正文实际渲染字号 = `font_size × UiFontScale.value`。
/// 这不是 bug，而是「全局放大」与「正文再单独微调」两层语义的自然叠加。
///
/// 为什么走 `MediaQuery` 而不是改字号令牌：`ShiciText` 那七档是 `static const`，
/// 按设计稿逐档钉死（见 `core/theme.dart` 的「字体层级 7 档」）；而且 Material 与
/// shadcn 组件内部大量使用**自己的默认字号**，根本读不到我们的令牌。只有在
/// `MediaQuery` 这一层缩放，才能覆盖到全站每一个 `Text`。
class UiFontScale {
  UiFontScale._();

  /// 偏好键
  static const String prefsKey = 'ui_font_scale';

  /// 出厂默认：标准（1.0 = 设计稿原尺寸）
  static const double normal = 1.0;

  /// 四档可选值 —— 与设置页的分段按钮一一对应
  static const List<double> levels = <double>[0.9, 1.0, 1.15, 1.3];

  /// 载入时的合法区间。存量档位若被手改坏（0 或负数）会直接把界面缩没，
  /// 所以读取时夹一下，而不是无条件信任磁盘里那个数。
  static const double minLevel = 0.8;
  static const double maxLevel = 1.5;

  /// 当前档位。用 [ValueNotifier] 而不是普通字段，是为了让根组件的
  /// `ValueListenableBuilder` 一改就重建整棵树 —— 切档位即时生效，无需重启。
  static final ValueNotifier<double> notifier = ValueNotifier<double>(normal);

  static double get value => notifier.value;

  /// 档位名 —— 设置页与提示文案共用，避免两处各写一套中文
  static String labelOf(double v) {
    if (v <= 0.95) return '小';
    if (v <= 1.05) return '标准';
    if (v <= 1.2) return '大';
    return '特大';
  }

  /// 百分比文案，例如 `115%`
  static String percentOf(double v) => '${(v * 100).round()}%';

  /// 从偏好读取。应用启动时调一次即可（[main] 里），
  /// 必须在首帧前完成，否则会先按 1.0 排版、读完再整页跳一下。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getDouble(prefsKey) ?? normal;
    notifier.value = raw.clamp(minLevel, maxLevel).toDouble();
  }

  /// 切换档位：先更新内存（界面立即跟随），再落盘。
  static Future<void> save(double v) async {
    final clamped = v.clamp(minLevel, maxLevel).toDouble();
    notifier.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(prefsKey, clamped);
  }
}

/// 供「固定尺度的画布」使用 —— 例如分享卡。
///
/// 分享卡导出的是 PNG，配色已刻意写死（见 `poem_share_cards.dart`）；字号同理：
/// 跟随全局字号会让同一首诗在「小号」和「特大号」用户手里导出两张版式不同的图，
/// 那不是自适应，是不可复现。包一层它，卡片在应用内预览与导出都恒定按 1.0 排版。
class FixedScaleCanvas extends StatelessWidget {
  final Widget child;

  const FixedScaleCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child,
    );
  }
}
