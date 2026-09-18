import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import 'poem_icon.dart';

/// 古籍式竖排正文 —— 从右到左分列，列内自上而下。
///
/// 只负责「怎么读原文」：汉字可点查音（回调交给详情页），标点/空白不可点。
/// 注释、译文等仍走详情页下方的横排分节，避免竖排里塞长段解释。
class PoemVerticalBody extends StatelessWidget {
  /// 已按繁简偏好转换后的正文（含 `\n` 分行）
  final String content;

  final double fontSize;
  final String fontFamily;
  final Color textColor;
  final Color? highlightColor;

  /// 点字回调；null 则整列不可点
  final void Function(String ch)? onCharTap;

  /// 跟读时高亮的行（与 content 的 `\n` 行对齐）；null 表示不高亮
  final int? highlightLine;

  const PoemVerticalBody({
    super.key,
    required this.content,
    required this.fontSize,
    required this.fontFamily,
    required this.textColor,
    this.highlightColor,
    this.onCharTap,
    this.highlightLine,
  });

  static const _punct = {
    '，', '。', '！', '？', '、', '；', '：', '《', '》', '「', '」',
    '（', '）', '(', ')', ',', '.', '!', '?', ';', ':', '"', "'", '…', '—',
  };

  bool _isChinese(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0xF900 && code <= 0xFAFF);
  }

  @override
  Widget build(BuildContext context) {
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return const SizedBox.shrink();

    // 古籍顺序：首句在最右 → 列表反转后用 Row 的 start-to-end 摆放
    final columns = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final highlighted = highlightLine != null && highlightLine == i;
      final colColor = highlighted && highlightColor != null
          ? highlightColor!
          : textColor;
      columns.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              for (final ch in line.runes.map(String.fromCharCode))
                if (ch.trim().isEmpty)
                  const SizedBox(height: 4)
                else
                  _VerticalCell(
                    ch: ch,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                    color: colColor,
                    tappable: _isChinese(ch) && onCharTap != null && !highlighted
                        ? onCharTap!
                        : null,
                    // 标点略小，贴近古籍句读
                    cellSize: _punct.contains(ch) ? fontSize * 0.72 : null,
                  ),
            ],
          ),
        ),
      );
    }

    // 反转：视觉上从右到左
    final ordered = columns.reversed.toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final row = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: ordered,
        );
        // 列过宽时横向滑动，避免小屏被裁切
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: row,
          ),
        );
      },
    );
  }
}

class _VerticalCell extends StatelessWidget {
  final String ch;
  final double fontSize;
  final String fontFamily;
  final Color color;
  final void Function(String)? tappable;
  final double? cellSize;

  const _VerticalCell({
    required this.ch,
    required this.fontSize,
    required this.fontFamily,
    required this.color,
    this.tappable,
    this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: cellSize ?? fontSize,
      fontFamily: fontFamily,
      color: color,
      height: 1.35,
    );
    final text = Text(ch, style: style, textAlign: TextAlign.center);
    if (tappable == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: text,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => tappable!(ch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
        child: text,
      ),
    );
  }
}

/// 竖排模式下的题签：作者朝代落在正文左侧，仿古籍边款。
class PoemVerticalColophon extends StatelessWidget {
  final String title;
  final String authorLine;
  final double fontSize;
  final String fontFamily;
  final Color ink;
  final Color inkSoft;

  const PoemVerticalColophon({
    super.key,
    required this.title,
    required this.authorLine,
    required this.fontSize,
    required this.fontFamily,
    required this.ink,
    required this.inkSoft,
  });

  @override
  Widget build(BuildContext context) {
    Widget col(String text, Color color, double size) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final ch in text.runes.map(String.fromCharCode))
            Text(
              ch,
              style: TextStyle(
                fontSize: size,
                fontFamily: fontFamily,
                color: color,
                height: 1.3,
              ),
            ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 竖排时作者在右、题名在左（古籍：题在右款在左略常见，这里题右更醒目）
        // 实际视觉：从右往左读 —— 先题名后作者
        col(title, ink, fontSize + 2),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: col(authorLine, inkSoft, fontSize * 0.72),
        ),
      ],
    );
  }
}

/// 详情页里竖排区块的壳：宣纸底 + 提示条。
class PoemVerticalShell extends StatelessWidget {
  final Widget child;
  final Widget? footnote;

  const PoemVerticalShell({super.key, required this.child, this.footnote});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: <Widget>[
          child,
          if (footnote != null) ...<Widget>[
            const SizedBox(height: 16),
            footnote!,
          ],
        ],
      ),
    );
  }
}

/// 轻提示：竖排模式下的一句话说明
class PoemVerticalHint extends StatelessWidget {
  const PoemVerticalHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        PoemIcon(PoemIcons.parallel, size: 14, color: c.inkFaint),
        const SizedBox(width: 6),
        Text(
          '自右向左竖排阅读，轻点汉字可查读音',
          style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkFaint),
        ),
      ],
    );
  }
}
