import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../widgets/card_exporter.dart';
import '../widgets/poem_icon.dart';

/// 抄写 / 练字模式 —— 把一首诗铺成米字格字帖，半透明范字做底，手写层覆盖其上。
///
/// 纯 Flutter 实现，可离线，无新依赖：
/// - 范字用 [TextPainter] 半透明绘制，米字（叉）用 [CustomPaint] 画；
/// - 手写笔迹用 `GestureDetector` 收集点，[CustomPainter] 连成路径；
/// - 可撤销上一笔 / 清空 / 隐藏范字（默写）/ 导出我的抄写为 PNG（走 [CardExporter]）。
///
/// 字体只提供已有的宋体（[ShiciFont.serif]），不做商业书体授权范畴的几十种临摹。
class CopyPracticePage extends StatefulWidget {
  final Poem poem;

  const CopyPracticePage({super.key, required this.poem});

  @override
  State<CopyPracticePage> createState() => _CopyPracticePageState();
}

/// 一笔：一串相对画板左上角的点。
class _Stroke {
  final List<Offset> points;
  const _Stroke(this.points);
}

class _CopyPracticePageState extends State<CopyPracticePage> {
  /// 每个格子的边长（逻辑像素）
  static const double _cell = 60;

  List<String> _chars = const <String>[];
  List<_Stroke> _strokes = const <_Stroke>[];
  List<Offset>? _current;
  bool _showModel = true;
  bool _exporting = false;

  final GlobalKey _boardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _chars = _extractChars(widget.poem.content);
  }

  /// 取诗中全部非空字符（含标点），按原文顺序铺格；
  /// 换行作为分词的天然断点（不进格），让字帖读起来就是诗的排列。
  static List<String> _extractChars(String content) {
    final out = <String>[];
    for (final line in content.split('\n')) {
      for (final r in line.runes) {
        final ch = String.fromCharCode(r);
        if (ch.trim().isEmpty) continue;
        out.add(ch);
      }
    }
    return out;
  }

  void _onPanStart(Offset p) {
    _current = <Offset>[p];
    setState(() => _strokes = <_Stroke>[..._strokes, _Stroke(_current!)]);
  }

  void _onPanUpdate(Offset p) {
    if (_current == null) return;
    _current!.add(p);
    setState(() {});
  }

  void _onPanEnd() => _current = null;

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes = <_Stroke>[..._strokes]..removeLast());
  }

  void _clear() => setState(() => _strokes = const <_Stroke>[]);

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final err = await CardExporter.exportAndShare(
        key: _boardKey,
        fileName: 'copy_${widget.poem.id}.png',
        text: '《${widget.poem.title}》抄写 · 来自「诗词雅集」',
        subject: widget.poem.title,
      );
      if (err != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final byline = _byline(widget.poem);

    return Scaffold(
      appBar: AppBar(
        title: Text('抄写', style: ShiciText.title.copyWith(fontSize: 18, color: c.ink)),
        actions: <Widget>[
          IconButton(
            onPressed: _chars.isEmpty ? null : _export,
            icon: PoemIcon(PoemIcons.share, color: c.ink),
            tooltip: '导出我的抄写',
          ),
        ],
      ),
      body: _chars.isEmpty
          ? Center(
              child: Text('这首诗没有可抄写的内容',
                  style: ShiciText.body.copyWith(color: c.inkSoft)),
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ShiciSize.pagePadding,
                    14,
                    ShiciSize.pagePadding,
                    8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(widget.poem.title,
                                style: ShiciText.heading
                                    .copyWith(fontSize: 15, color: c.ink)),
                            if (byline.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(byline,
                                    style: ShiciText.caption
                                        .copyWith(color: c.inkSoft)),
                              ),
                          ],
                        ),
                      ),
                      _ToggleChip(
                        label: _showModel ? '隐藏范字' : '显示范字',
                        active: _showModel,
                        onTap: () => setState(() => _showModel = !_showModel),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      const pad = ShiciSize.pagePadding;
                      final columns = _columns(constraints.maxWidth - pad * 2);
                      final rows = (_chars.length / columns).ceil();
                      final boardW = columns * _cell;
                      final boardH = rows * _cell;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          pad,
                          6,
                          pad,
                          pad,
                        ),
                        child: RepaintBoundary(
                          key: _boardKey,
                          child: GestureDetector(
                            onPanStart: (d) => _onPanStart(d.localPosition),
                            onPanUpdate: (d) => _onPanUpdate(d.localPosition),
                            onPanEnd: (_) => _onPanEnd(),
                            child: CustomPaint(
                              size: Size(boardW, boardH),
                              painter: _BoardPainter(
                                chars: _chars,
                                columns: columns,
                                cell: _cell,
                                strokes: _strokes,
                                showModel: _showModel,
                                modelColor: c.ink.withOpacity(0.16),
                                gridColor: c.line,
                                inkColor: c.ink,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _Toolbar(
                  canUndo: _strokes.isNotEmpty,
                  exporting: _exporting,
                  onUndo: _undo,
                  onClear: _clear,
                  onExport: _export,
                ),
              ],
            ),
    );
  }

  int _columns(double availableWidth) {
    final n = (availableWidth / _cell).floor();
    return n < 1 ? 1 : n;
  }

  String _byline(Poem poem) {
    final author = poem.authorName?.trim() ?? '';
    final dynasty = poem.dynastyName?.trim() ?? '';
    if (author.isEmpty && dynasty.isEmpty) return '';
    if (dynasty.isEmpty) return author;
    if (author.isEmpty) return dynasty;
    return '$author · $dynasty';
  }
}

/// 字帖画板：范字 + 米字格 + 用户笔迹，三层都画在同一个 [CustomPaint] 上。
class _BoardPainter extends CustomPainter {
  final List<String> chars;
  final int columns;
  final double cell;
  final List<_Stroke> strokes;
  final bool showModel;
  final Color modelColor;
  final Color gridColor;
  final Color inkColor;

  const _BoardPainter({
    required this.chars,
    required this.columns,
    required this.cell,
    required this.strokes,
    required this.showModel,
    required this.modelColor,
    required this.gridColor,
    required this.inkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 米字（叉）比边框更浅，避免抢范字与笔迹的读序
    final crossPaint = Paint()
      ..color = gridColor.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < chars.length; i++) {
      final col = i % columns;
      final row = i ~/ columns;
      final x = col * cell;
      final y = row * cell;
      final rect = Rect.fromLTWH(x, y, cell, cell);

      // 边框
      canvas.drawRect(rect, gridPaint);
      // 米字：两条对角线
      canvas.drawLine(Offset(x, y), Offset(x + cell, y + cell), crossPaint);
      canvas.drawLine(
          Offset(x + cell, y), Offset(x, y + cell), crossPaint);

      // 半透明范字
      if (showModel && chars[i].trim().isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: chars[i],
            style: TextStyle(
              fontFamily: ShiciFont.serif,
              fontSize: cell * 0.62,
              color: modelColor,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas,
            Offset(x + (cell - tp.width) / 2, y + (cell - tp.height) / 2));
      }
    }

    // 用户笔迹
    final ink = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      if (s.points.length == 1) {
        canvas.drawCircle(
          s.points.first,
          ink.strokeWidth / 2,
          Paint()..color = inkColor..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()
        ..moveTo(s.points.first.dx, s.points.first.dy);
      for (int k = 1; k < s.points.length; k++) {
        path.lineTo(s.points[k].dx, s.points[k].dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.chars != chars ||
      old.columns != columns ||
      old.showModel != showModel ||
      old.strokes.length != strokes.length;
}

/// 顶栏的「隐藏/显示范字」开关（胶囊）。
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? c.indigo : c.silk,
          borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
          border: Border.all(color: active ? c.indigo : c.line),
        ),
        child: Center(
          child: Text(
            label,
            style: ShiciText.caption.copyWith(
              color: active ? c.onAccent : c.ink,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部工具栏：撤销 / 清空 / 导出。
class _Toolbar extends StatelessWidget {
  final bool canUndo;
  final bool exporting;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onExport;

  const _Toolbar({
    required this.canUndo,
    required this.exporting,
    required this.onUndo,
    required this.onClear,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ShiciSize.pagePadding,
        10,
        ShiciSize.pagePadding,
        16,
      ),
      decoration: BoxDecoration(
        color: c.silk,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: <Widget>[
          _ToolButton(
            icon: Icons.undo,
            label: '撤销',
            enabled: canUndo,
            onTap: onUndo,
          ),
          const SizedBox(width: 12),
          _ToolButton(
            icon: Icons.delete_outline,
            label: '清空',
            enabled: canUndo,
            onTap: onClear,
          ),
          const Spacer(),
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: exporting ? null : onExport,
              icon: PoemIcon(PoemIcons.share, size: 16, color: c.onAccent),
              label: Text(exporting ? '生成中…' : '导出抄写'),
              style: FilledButton.styleFrom(
                backgroundColor: c.cinnabar,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final color = enabled ? c.ink : c.inkFaint;
    return Material(
      color: c.sand,
      borderRadius: BorderRadius.circular(ShiciSize.rMd),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: ShiciText.caption.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
