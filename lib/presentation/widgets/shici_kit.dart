import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import 'poem_icon.dart';

/// 方印 —— 品牌母题，出现在启动页、页首、成就徽章与空状态。
///
/// 构造与设计稿画布节点 `3:39` / `3:1170` 同源：
/// 朱砂底 + 「雅」书法字 + 圆角 = 边长 × 0.16。
/// 后续改标识只需要改这里 + `assets/` 里的应用图标。
class SealMark extends StatelessWidget {
  /// 边长（正方形）
  final double size;

  /// 印文，默认「雅」
  final String glyph;

  /// 底色，默认朱砂
  final Color? color;

  /// 印文色，默认绢白
  final Color? glyphColor;

  /// 是否描边（浅底单色用法）
  final bool outlined;

  const SealMark({
    super.key,
    this.size = 44,
    this.glyph = '雅',
    this.color,
    this.glyphColor,
    this.outlined = false,
  });

  /// 与画布一致的圆角比例
  static double radiusFor(double size) => (size * 0.16).clamp(2, size / 2);

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final bg = color ?? c.cinnabar;
    // 印文压在朱砂实色上 —— 深色模式下朱砂转珊瑚，字就得从纸白翻成墨底
    final fg = glyphColor ?? (outlined ? bg : c.onAccent);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(radiusFor(size)),
        border: outlined ? Border.all(color: bg, width: 1.2) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: ShiciText.calligraphy.copyWith(
          fontSize: size * 0.56,
          color: fg,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 品牌锁定组合：方印 + 「诗词雅集」字标（横版）
class BrandLockup extends StatelessWidget {
  final double sealSize;
  final double fontSize;
  final Color? textColor;

  const BrandLockup({
    super.key,
    this.sealSize = 34,
    this.fontSize = 26,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SealMark(size: sealSize, color: c.cinnabar),
        SizedBox(width: sealSize * 0.28),
        Text(
          '诗词雅集',
          style: ShiciText.calligraphy.copyWith(
            fontSize: fontSize,
            color: textColor ?? c.ink,
          ),
        ),
      ],
    );
  }
}

/// 区块头（页内小节）：朱砂编号 + 宋体标题 + 青灰副标题
///
/// 对齐设计稿每个区块顶部的 07 · 品牌标识 / 标题 / 副标题 三级结构。
class ShiciSectionHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const ShiciSectionHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (eyebrow != null) ...<Widget>[
                Text(
                  eyebrow!,
                  style: ShiciText.tag.copyWith(
                    color: c.cinnabar,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: <Widget>[
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c.cinnabar,
                      borderRadius:
                          BorderRadius.circular(ShiciSize.rSeal / 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      style: ShiciText.title.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Text(
                    subtitle!,
                    style: ShiciText.caption.copyWith(color: c.inkSoft),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 绢白卡片：圆角 14 + 极细描边，无阴影（水墨留白，不靠投影分层）
class ShiciCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  /// 定高卡片（画布上的列表行 52 / 复习卡 88 都是定高）
  final double? height;

  const ShiciCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius = ShiciSize.rMd,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final box = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.silk,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: box,
      ),
    );
  }
}

/// 胶囊标签（可点）：热门搜索、体裁、朝代筛选用
class ShiciPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? materialIcon;
  final String? poemIcon;

  const ShiciPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.materialIcon,
    this.poemIcon,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    // 选中态是黛蓝实心胶囊：深色下黛蓝转月白，前景必须跟着翻成墨底
    final fg = selected ? c.onAccent : c.ink;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: poemIcon != null || materialIcon != null ? 12 : 14),
        decoration: BoxDecoration(
          color: selected ? c.indigo : c.silk,
          borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
          border: Border.all(color: selected ? c.indigo : c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (poemIcon != null) ...<Widget>[
              PoemIcon(poemIcon!, size: 13, color: fg),
              const SizedBox(width: 6),
            ] else if (materialIcon != null) ...<Widget>[
              Icon(materialIcon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: ShiciText.caption.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分段控件：全部 / 唐诗 / 宋词 ……（单选，选中实底黛蓝）
class ShiciSegmented extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const ShiciSegmented({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: ShiciSize.pagePadding),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            ShiciPill(
              label: options[i],
              selected: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
          ],
        ],
      ),
    );
  }
}

/// 数据单元：大数字（Inter）+ 说明
class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final String? suffix;

  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: ShiciText.numeral.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: accent ?? c.indigo,
              ),
            ),
            if (suffix != null)
              Text(
                suffix!,
                style: ShiciText.caption.copyWith(color: accent ?? c.indigo),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: ShiciText.caption.copyWith(color: c.inkSoft)),
      ],
    );
  }
}

/// 空状态插画：远山留白 + 朱砂小印（全站统一，替代各页各画一套）
///
/// 对应设计稿 S4 插画系统的「远山孤舟」母题的极简版。
/// [size] 传 `null` 表示铺满父容器（父级需给出紧约束，如 `Positioned`
/// 的 left/right/top/bottom）。
class InkMountain extends StatelessWidget {
  final Size? size;
  final Color? inkColor;

  const InkMountain({
    super.key,
    this.size = const Size(184, 96),
    this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    // size 为 null 时给 Size.zero，让紧约束决定实际绘制尺寸
    return CustomPaint(
      size: size ?? Size.zero,
      painter: _InkMountainPainter(inkColor ?? c.ink, c.cinnabar),
    );
  }
}

class _InkMountainPainter extends CustomPainter {
  final Color ink;
  final Color seal;
  const _InkMountainPainter(this.ink, this.seal);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    const layers = <List<double>>[
      <double>[0.18, 0.62, 0.30],
      <double>[0.30, 0.74, 0.42],
      <double>[0.46, 0.86, 0.56],
    ];
    for (final l in layers) {
      final paint = Paint()
        ..color = ink.withOpacity(l[0])
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(0, h)
        ..lineTo(0, h * l[1])
        ..quadraticBezierTo(w * 0.22, h * (l[1] - l[2]), w * 0.42, h * l[1])
        ..quadraticBezierTo(w * 0.62, h * (l[1] - l[2] * 0.7), w * 0.82, h * l[1])
        ..quadraticBezierTo(w * 0.94, h * (l[1] - l[2] * 0.4), w, h * l[1])
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, paint);
    }

    // 朱砂日轮 + 一叶孤舟
    canvas.drawCircle(
      Offset(w * 0.80, h * 0.26),
      math.max(4.0, w * 0.030),
      Paint()..color = seal.withOpacity(0.9),
    );
    final boat = Path()
      ..moveTo(w * 0.30, h * 0.93)
      ..quadraticBezierTo(w * 0.36, h * 0.98, w * 0.42, h * 0.93);
    canvas.drawPath(
      boat,
      Paint()
        ..color = ink.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _InkMountainPainter old) =>
      old.ink != ink || old.seal != seal;
}
