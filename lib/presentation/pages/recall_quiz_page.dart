import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/empty_state.dart';
import 'library_page.dart';

/// 背诵自测
///
/// 隐藏原文，先自行背诵再对照，结果记为「自测通过 / 自测未过」，
/// 与艾宾浩斯复习（ReviewPage）互补：复习是「按周期回顾」，
/// 自测是「主动检验是否真的背下来」。
class RecallQuizPage extends StatefulWidget {
  /// 自测范围名称（显示在标题栏）
  final String title;

  /// 指定诗词 id 列表（如某个学习计划）；为空时随机抽取 [randomLimit] 首
  final List<int>? poemIds;

  /// 随机模式下的抽取数量
  final int randomLimit;

  const RecallQuizPage({
    super.key,
    required this.title,
    this.poemIds,
    this.randomLimit = 20,
  });

  @override
  State<RecallQuizPage> createState() => _RecallQuizPageState();
}

class _RecallQuizPageState extends State<RecallQuizPage> {
  List<Poem> _poems = [];
  bool _loading = true;
  int _index = 0;
  bool _revealed = false;
  int _pass = 0;
  int _fail = 0;

  @override
  void initState() {
    super.initState();
    _loadPoems();
  }

  Future<void> _loadPoems({bool reshuffle = false}) async {
    setState(() => _loading = true);
    final ids = widget.poemIds;
    List<Poem> poems;
    if (ids != null && ids.isNotEmpty) {
      poems = await DatabaseHelper.getPoemsByIds(ids);
    } else {
      final all = await DatabaseHelper.getAllPoems();
      all.shuffle();
      poems = all.take(widget.randomLimit).toList();
    }
    if (reshuffle && ids == null) {
      poems.shuffle();
    }
    if (!mounted) return;
    setState(() {
      _poems = poems;
      _index = 0;
      _revealed = false;
      _pass = 0;
      _fail = 0;
      _loading = false;
    });
  }

  Future<void> _mark(bool remembered) async {
    final poem = _poems[_index];
    await DatabaseHelper.recordRecall(poem.id, remembered: remembered);
    if (!mounted) return;
    setState(() {
      if (remembered) {
        _pass++;
      } else {
        _fail++;
      }
      if (_index + 1 >= _poems.length) {
        _index = _poems.length; // 标记完成
      } else {
        _index++;
        _revealed = false;
      }
    });
  }

  bool get _finished => !_loading && _poems.isNotEmpty && _index >= _poems.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontFamily: 'serif')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _poems.isEmpty
              ? _buildEmpty(theme)
              : _finished
                  ? _buildSummary(theme)
                  : _buildQuiz(theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return EmptyState(
      icon: PoemIcons.library,
      title: '暂无可自测的诗词',
      description: '先去诗词库读几首，或给学习计划加入诗词',
      actionLabel: '去诗词库',
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LibraryPage()),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final total = _poems.length;
    final rate = total > 0 ? (_pass / total * 100).toStringAsFixed(0) : '0';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 64, color: AppTheme.songLv),
            const SizedBox(height: 16),
            Text('本轮自测完成',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _resultCell('记住了', _pass, AppTheme.songLv, theme),
                _resultCell('没记住', _fail, AppTheme.zhuShaHong, theme),
                _resultCell('正确率', '$rate%', AppTheme.daiLan, theme),
              ],
            ),
            const SizedBox(height: 24),
            Text('结果已记入学习记录，可在统计中查看',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _loadPoems(reshuffle: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('再来一轮'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.songLv),
                  child: const Text('完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCell(String label, dynamic value, Color color, ThemeData theme) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'serif')),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildQuiz(ThemeData theme) {
    final poem = _poems[_index];
    final total = _poems.length;
    final progress = (_index + 1) / total;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('第 ${_index + 1} / $total 首',
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              Text('记住 $_pass · 未过 $_fail',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: AppTheme.songLv,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    poem.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: 'serif', fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${poem.dynastyName ?? ''} · ${poem.authorName ?? '佚名'}',
                    style: TextStyle(
                        fontSize: 14, color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 20),
                  if (_revealed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.songLv.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.songLv.withOpacity(0.25)),
                      ),
                      child: Text(
                        poem.content,
                        style: const TextStyle(
                            fontSize: 17, height: 1.9, fontFamily: 'serif'),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 48),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.visibility_off_outlined,
                              size: 40, color: AppTheme.qingHui),
                          const SizedBox(height: 12),
                          Text(
                            '先试着背出来，再对照原文',
                            style: TextStyle(
                                color: theme.colorScheme.outline, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() => _revealed = !_revealed),
            icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility,
                size: 18),
            label: Text(_revealed ? '隐藏原文' : '显示原文'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _mark(false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('没记住'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.zhuShaHong),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _mark(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('记住了'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.songLv),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
