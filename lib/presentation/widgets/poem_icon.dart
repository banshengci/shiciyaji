import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 自有图标集名称表 —— 与 `assets/icons/` 下的 32 枚 SVG 一一对应。
///
/// 取形于匾额、书卷、竹简、印章、沙漏、花瓣，统一 24px 网格 / 1.5px 描边。
/// 使用方式见 [PoemIcon]。
class PoemIcons {
  PoemIcons._();

  // 导航
  static const String home = 'home';
  static const String library = 'library';
  static const String search = 'search';
  static const String bookmark = 'bookmark';
  static const String profile = 'profile';

  // 内容
  static const String dynasty = 'dynasty';
  static const String poet = 'poet';
  static const String category = 'category';
  static const String tag = 'tag';
  static const String review = 'review';
  static const String stats = 'stats';
  static const String achievement = 'achievement';

  // 学习
  static const String recite = 'recite';
  static const String note = 'note';
  static const String feihualing = 'feihualing';
  static const String checkin = 'checkin';
  static const String progress = 'progress';
  static const String goal = 'goal';
  static const String duration = 'duration';
  static const String streak = 'streak';
  static const String star = 'star';

  // 功能
  static const String tts = 'tts';
  static const String immersive = 'immersive';
  static const String darkmode = 'darkmode';
  static const String share = 'share';
  static const String download = 'download';
  static const String edit = 'edit';
  static const String settings = 'settings';
  static const String done = 'done';
  static const String filter = 'filter';
  static const String sort = 'sort';
  static const String random = 'random';

  /// 需要「选中/未选中」两态时，用同一枚图标换色即可（不自带实心版）。
  static const String assetDir = 'assets/icons';
}

/// 图标组件：优先渲染自有 SVG 图标，也接受 [IconData] 作为过渡期兜底。
///
/// 自有图标为单色矢量，通过 [ColorFilter.mode] + [BlendMode.srcIn] 着色，
/// 因此**天生跟随主题色**，无需为每套主题各导一份资源。
///
/// ```dart
/// PoemIcon(PoemIcons.home, size: 18, color: c.indigo)
/// PoemIcon(Icons.chevron_right)            // 兜底：仍是 Material 图标
/// ```
class PoemIcon extends StatelessWidget {
  /// [String] → `assets/icons/<name>.svg`；[IconData] → Material 兜底
  final Object icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  const PoemIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final s = size ?? iconTheme.size ?? 24;
    final c = color ?? iconTheme.color;

    final ic = icon;
    if (ic is String) {
      return SvgPicture.asset(
        '${PoemIcons.assetDir}/$ic.svg',
        width: s,
        height: s,
        colorFilter: c == null
            ? null
            : ColorFilter.mode(c, BlendMode.srcIn),
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      );
    }
    return Icon(
      ic as IconData,
      size: s,
      color: c,
      semanticLabel: semanticLabel,
    );
  }
}

/// 把 [IconData] 映射到自有图标，供批量迁移期使用。
///
/// 未收录的 Material 图标返回 `null`，调用方可继续用 Material 图标过渡。
/// 注意：`IconData` 重写了 `==`，因此这里只能是运行期 `final` 映射，
/// 不能声明成 `const`（Dart 不允许非常量相等性的对象作常量 Map 键）。
final Map<IconData, String> kMaterialToPoemIcon = <IconData, String>{
  Icons.home_outlined: PoemIcons.home,
  Icons.home: PoemIcons.home,
  Icons.menu_book_outlined: PoemIcons.library,
  Icons.menu_book: PoemIcons.library,
  Icons.search: PoemIcons.search,
  Icons.favorite_border: PoemIcons.bookmark,
  Icons.favorite: PoemIcons.bookmark,
  Icons.person_outline: PoemIcons.profile,
  Icons.person: PoemIcons.profile,
  Icons.school: PoemIcons.goal,
  Icons.psychology: PoemIcons.review,
  Icons.history: PoemIcons.duration,
  Icons.local_fire_department: PoemIcons.streak,
  Icons.emoji_events: PoemIcons.achievement,
  Icons.auto_awesome: PoemIcons.star,
  Icons.local_florist: PoemIcons.feihualing,
  Icons.shuffle: PoemIcons.random,
  Icons.edit_note: PoemIcons.note,
  Icons.edit: PoemIcons.edit,
  Icons.insights: PoemIcons.stats,
  Icons.bar_chart: PoemIcons.stats,
  Icons.volume_up: PoemIcons.tts,
  Icons.record_voice_over: PoemIcons.recite,
  Icons.fullscreen: PoemIcons.immersive,
  Icons.dark_mode: PoemIcons.darkmode,
  Icons.share: PoemIcons.share,
  Icons.download: PoemIcons.download,
  Icons.settings: PoemIcons.settings,
  Icons.filter_list: PoemIcons.filter,
  Icons.sort: PoemIcons.sort,
  Icons.tag: PoemIcons.tag,
  Icons.check_circle: PoemIcons.done,
  Icons.done: PoemIcons.done,
  Icons.bookmark_border: PoemIcons.bookmark,
  Icons.category_outlined: PoemIcons.category,
  Icons.person_search: PoemIcons.poet,
  Icons.event_available: PoemIcons.checkin,
  Icons.trending_up: PoemIcons.progress,
  Icons.timer_outlined: PoemIcons.duration,
  Icons.schedule: PoemIcons.duration,
  Icons.star_border: PoemIcons.star,
};

/// 迁移辅助：命中映射则返回自有图标名，否则原样返回 [IconData]。
Object poemIconOf(Object icon) {
  if (icon is IconData) return kMaterialToPoemIcon[icon] ?? icon;
  return icon;
}
