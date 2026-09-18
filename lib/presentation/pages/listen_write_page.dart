import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/tts_service.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';

/// 听写默写：听 TTS 念诗句，再把空缺的字填回去。
///
/// 与「背诵自测」互补：那边看提示回忆全文，这边**先听后写**，练听感与默写。
/// 判分只做「与原文字是否一致」，错字直接标出，不扣学习打卡语义。
class ListenWritePage extends StatefulWidget {
  final Poem poem;

  const ListenWritePage({super.key, required this.poem});

  @override
  State<ListenWritePage> createState() => _ListenWritePageState();
}

class _ListenWritePageState extends State<ListenWritePage> {
  final _tts = TtsService.instance;

  /// 每句：原文汉字序列
  late List<String> _rawLines;
  /// 每句：待填的空位下标（每隔 2–3 字挖空）
  late List<List<int>> _blanks;
  /// 用户填写：句下标 -> 空位下标 -> 字
  late List<List<String>> _answers;
  List<TextEditingController> _controllers = const [];
  bool _revealed = false;
  int _playCount = 0;

  String get _title => widget.poem.title;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    final lines = widget.poem.content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    _rawLines = lines;
    _blanks = [];
    _answers = [];
    for (final line in lines) {
      final chars = <String>[];
      for (final r in line.runes) {
        final ch = String.fromCharCode(r);
        if (ch.trim().isNotEmpty) chars.add(ch);
      }
      final blanks = <int>[];
      for (var i = 1; i < chars.length; i += 3) {
        blanks.add(i);
      }
      if (blanks.isEmpty && chars.isNotEmpty) {
        blanks.add(chars.length ~/ 2);
      }
      _blanks.add(blanks);
      _answers.add(List.filled(blanks.length, ''));
    }
    final all = <TextEditingController>[];
    for (final b in _blanks) {
      for (var i = 0; i < b.length; i++) {
        all.add(TextEditingController());
      }
    }
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers = all;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _play() async {
    await _tts.speak('$_title。${widget.poem.content}');
    if (mounted) setState(() => _playCount++);
  }

  int _score() {
    var total = 0;
    var hit = 0;
    for (var li = 0; li < _rawLines.length; li++) {
      final chars = _lineChars(_rawLines[li]);
      for (var bi = 0; bi < _blanks[li].length; bi++) {
        total++;
        final idx = _blanks[li][bi];
        final ans = _controllers[_offsetOf(li, bi)].text.trim();
        if (ans.isNotEmpty && ans == chars[idx]) hit++;
      }
    }
    return total == 0 ? 0 : (hit * 100 / total).round();
  }

  int _offsetOf(int line, int blank) {
    var k = 0;
    for (var li = 0; li < line; li++) {
      k += _blanks[li].length;
    }
    return k + blank;
  }

  List<String> _lineChars(String line) {
    final chars = <String>[];
    for (final r in line.runes) {
      final ch = String.fromCharCode(r);
      if (ch.trim().isNotEmpty) chars.add(ch);
    }
    return chars;
  }

  void _check() {
    setState(() => _revealed = true);
  }

  void _reset() {
    for (final c in _controllers) {
      c.clear();
    }
    setState(() => _revealed = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: Text('听写 · ${_title}',
            style: const TextStyle(fontFamily: ShiciFont.serif)),
        actions: [
          IconButton(
            onPressed: _play,
            icon: const PoemIcon(PoemIcons.tts),
            tooltip: '再听一遍',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '听音频补全空缺的字；填完后点「对答案」。已听 $_playCount 遍',
            style: ShiciText.caption.copyWith(color: c.inkSoft),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _playCount == 0 ? _play : null,
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: Text(_playCount == 0 ? '先听一遍' : '已播放'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _revealed ? _reset : _check,
                  child: Text(_revealed ? '再练一次' : '对答案'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (var li = 0; li < _rawLines.length; li++) ...[
            _buildLine(theme, li),
            const SizedBox(height: 14),
          ],
          if (_revealed) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.silk,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('得分 ${_score()}',
                      style: ShiciText.heading
                          .copyWith(color: c.ink, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    widget.poem.content,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 16,
                      height: 1.9,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLine(ThemeData theme, int li) {
    final c = ShiciColors.of(context);
    final chars = _lineChars(_rawLines[li]);
    final blanks = _blanks[li];
    final blankSet = {for (final b in blanks) b: true};
    final widgets = <Widget>[];
    var bi = 0;
    for (var ci = 0; ci < chars.length; ci++) {
      if (blankSet[ci] == true) {
        final ctrl = _controllers[_offsetOf(li, bi)];
        final correct = chars[ci];
        final typed = ctrl.text.trim();
        Color? border;
        if (_revealed) {
          border = typed == correct ? c.pine : c.cinnabar;
        }
        widgets.add(SizedBox(
          width: 40,
          child: TextField(
            controller: ctrl,
            enabled: !_revealed,
            maxLength: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 20,
              color: _revealed
                  ? (typed == correct ? c.pine : c.cinnabar)
                  : c.ink,
            ),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: border ?? c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.cinnabar),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ));
        bi++;
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          child: Text(
            chars[ci],
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ));
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }
}
