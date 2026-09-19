import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/prosody.dart';

/// 平仄·韵脚标注视图。
///
/// 把正文渲染成带格律标注的版式 —— 按句排列，**每个汉字一个等宽单元**：
/// 上排是字、下排是对应的平仄符号（平=`○`、仄=`●`、未审=`·`）。
/// 句末字（韵脚位）用朱砂色，并在该句**末尾**显示其所属韵部名。
///
/// 颜色全部取自 [ShiciColors]（恒定色守卫在守）：平=indigo、仄=ochre、
/// 未审=inkFaint、韵脚=cinnabar、正文=ink。正文走 [ShiciFont.serif]。
///
/// 数据未加载或某字未收录时**只降级、不编造**：未收录字仍占位渲染、符号为 `·`，
/// 不会出现假结果。
class ProsodyView extends StatelessWidget {
  const ProsodyView({
    super.key,
    required this.content,
    this.fontSize = 18.0,
  });

  final String content;
  final double fontSize;

  static const Key rhymeCharKey = Key('prosody-rhyme-char');

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    // 数据可能在首帧前已加载；这里统一等一次，保证标注不闪。
    return FutureBuilder<void>(
      future: Prosody.load(),
      builder: (context, snapshot) {
        final result = Prosody.analyze(content);
        return LayoutBuilder(
          builder: (context, constraints) {
            // 用可用宽度约束每句，避免 130% 全局字号下横向溢出。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final verse in result.verses)
                  _VerseRow(
                    verse: verse,
                    fontSize: fontSize,
                    maxWidth: constraints.maxWidth,
                    colors: c,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.verse,
    required this.fontSize,
    required this.maxWidth,
    required this.colors,
  });

  final VerseAnalysis verse;
  final double fontSize;
  final double maxWidth;
  final ShiciColors colors;

  @override
  Widget build(BuildContext context) {
    // 找出句末字（最后一个汉字）在 cells 中的位置，用于标朱砂 + 显示韵部。
    int? rhymeIndex;
    for (var i = verse.cells.length - 1; i >= 0; i--) {
      if (verse.cells[i].isHanzi) {
        rhymeIndex = i;
        break;
      }
    }
    final rhymeGroup = verse.endingRhyme;

    final cells = <Widget>[];
    for (var i = 0; i < verse.cells.length; i++) {
      final cell = verse.cells[i];
      final isRhyme = i == rhymeIndex && rhymeGroup != null;
      cells.add(_Cell(
        cell: cell,
        fontSize: fontSize,
        colors: colors,
        isRhyme: isRhyme,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Wrap(
              spacing: 2,
              runSpacing: 6,
              children: cells,
            ),
          ),
          if (rhymeGroup != null) ...[
            const SizedBox(width: 8),
            // 韵部名置于句末（末尾），朱砂小字，不挤占字格。
            Container(
              constraints: BoxConstraints(
                maxWidth: maxWidth * 0.4,
              ),
              child: Text(
                rhymeGroup,
                style: TextStyle(
                  fontSize: fontSize * 0.5,
                  fontFamily: ShiciFont.serif,
                  color: colors.cinnabar,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.cell,
    required this.fontSize,
    required this.colors,
    required this.isRhyme,
  });

  final ProsodyCell cell;
  final double fontSize;
  final ShiciColors colors;
  final bool isRhyme;

  Color get _charColor {
    if (isRhyme) return colors.cinnabar;
    if (!cell.isHanzi) return colors.inkSoft;
    return colors.ink;
  }

  Color get _symbolColor {
    switch (cell.tone) {
      case Tone.ping:
        return colors.indigo;
      case Tone.ze:
        return colors.ochre;
      case Tone.unknown:
        return colors.inkFaint;
    }
  }

  String get _symbol {
    switch (cell.tone) {
      case Tone.ping:
        return '○';
      case Tone.ze:
        return '●';
      case Tone.unknown:
        return '·';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fontSize * 1.15,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cell.char,
            key: isRhyme ? ProsodyView.rhymeCharKey : null,
            style: TextStyle(
              fontSize: fontSize,
              fontFamily: ShiciFont.serif,
              color: _charColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          // 非汉字（标点等）无平仄，底部留白保持字格对齐。
          Text(
            cell.isHanzi ? _symbol : ' ',
            style: TextStyle(
              fontSize: fontSize * 0.55,
              fontFamily: ShiciFont.serif,
              color: cell.isHanzi ? _symbolColor : colors.inkFaint,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
