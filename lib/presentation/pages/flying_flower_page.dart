import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/poem_icon.dart';
import '../../core/s2t_converter.dart';
import '../../core/design_tokens.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';

/// 飞花令游戏页
///
/// 经典飞花令：给出一个汉字，用户在限时内尽可能多地找出包含该字的诗句。
/// 每首诗只能用一次；答对得分，答错扣分并显示正确答案后自动跳到下一首。
///
/// 取材自《唐诗三百首》《宋词三百首》等数据包，字的选择加权随机，
/// 避免出现「的」「了」等无意义高频字。
class FlyingFlowerPage extends StatefulWidget {
  const FlyingFlowerPage({super.key});

  @override
  State<FlyingFlowerPage> createState() => _FlyingFlowerPageState();
}

class _FlyingFlowerPageState extends State<FlyingFlowerPage>
    with SingleTickerProviderStateMixin {
  // ---- 游戏状态 ----
  bool _loading = true;
  bool _started = false;
  bool _finished = false;

  String _playChar = '';
  List<Poem> _allCharPoems = const []; // 包含该字的全部诗词（随机序）
  List<Poem> _distractorPool = const []; // 不含该字的诗词池（干扰项来源）
  int _currentIndex = 0; // 当前题目索引

  int _score = 0;
  int _combo = 0; // 连续答对
  int _correct = 0;
  int _wrong = 0;

  // ---- 倒计时 ----
  late AnimationController _timerCtrl;
  static const int _roundSeconds = 60;
  bool _timerActive = false;

  // ---- 每轮选项（4选1：哪个包含该字） ----
  List<Poem> _options = const [];
  int? _selectedIdx;
  bool _answered = false;

  /// 单局最多答几题，避免扩充包后一局跑完数百首
  static const int _maxRounds = 12;

  bool _traditional = false;

  String _t(String s) => _traditional
      ? S2TConverter.toTraditional(s)
      : S2TConverter.toSimplified(s);

  @override
  void initState() {
    super.initState();
    _timerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _roundSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_answered) {
          _timeUp();
        }
      });
    _init();
  }

  @override
  void dispose() {
    _timerCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final char = await DatabaseHelper.getRandomPlayChar(minCount: 3);
    if (char == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _playChar = '月';
        });
      }
      return;
    }
    final poems = await DatabaseHelper.getPoemsContainingChar(char);
    final distractors = await DatabaseHelper.getRandomPoemsExcludingChar(char);
    if (!mounted) return;
    setState(() {
      _traditional = prefs.getBool('traditional_chinese') ?? false;
      _playChar = char;
      _allCharPoems = poems;
      _distractorPool = distractors;
      _loading = false;
    });
  }

  int get _totalRounds =>
      min(_maxRounds, _allCharPoems.length);

  /// 返回 [poem] 中首次出现令字的那一行（或标题），供选项预览与对错解析
  String? _matchingSnippet(Poem poem) {
    final char = _playChar;
    for (final raw in poem.content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.contains(char)) return line;
    }
    if (poem.title.contains(char)) {
      return '《${poem.title}》';
    }
    return null;
  }

  /// 将令字高亮（答题后展示命中句用）。
  /// [text] 可能已转繁体，因此同时匹配简/繁令字。
  Widget _highlightLine(String text, ThemeData theme, ShiciColors c,
      {bool revealed = false}) {
    final chars = <String>{_playChar, _t(_playChar)};
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      String? hit;
      for (final c in chars) {
        if (c.isEmpty) continue;
        if (text.startsWith(c, i)) {
          hit = c;
          break;
        }
      }
      if (hit != null) {
        spans.add(TextSpan(
          text: hit,
          style: TextStyle(
            color: revealed ? c.cinnabar : theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ));
        i += hit.length;
      } else {
        // 收集连续非命中字符
        var j = i + 1;
        while (j < text.length) {
          var isHit = false;
          for (final c in chars) {
            if (c.isNotEmpty && text.startsWith(c, j)) {
              isHit = true;
              break;
            }
          }
          if (isHit) break;
          j++;
        }
        spans.add(TextSpan(text: text.substring(i, j)));
        i = j;
      }
    }
    return Text.rich(
      TextSpan(children: spans, style: theme.textTheme.bodySmall),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ---- 开始游戏 ----
  void _startGame() {
    setState(() {
      _started = true;
      _finished = false;
      _currentIndex = 0;
      _score = 0;
      _combo = 0;
      _correct = 0;
      _wrong = 0;
      _timerActive = false;
    });
    _timerCtrl.reset();
    _nextRound();
  }

  /// 出题：从包含 playChar 的诗中选一首正确答案，再从不含该字的诗中抽 3 首干扰项
  void _nextRound() {
    if (_currentIndex >= _totalRounds || _allCharPoems.isEmpty) {
      _finishGame();
      return;
    }
    final correct = _allCharPoems[_currentIndex];
    final rng = Random();
    // 干扰项必须不含目标字（title/content 都不含），否则用户无法判断
    final correctId = correct.id;
    final distractors = _distractorPool
        .where((p) => p.id != correctId)
        .toList()
      ..shuffle(rng);
    final picked = distractors.take(3).toList();
    final opts = [correct, ...picked]..shuffle(rng);
    setState(() {
      _options = opts;
      _selectedIdx = null;
      _answered = false;
    });
    // 每 5 题加时间压力
    if (_currentIndex % 5 == 0) {
      _timerCtrl.reset();
      _timerCtrl.forward(from: 0);
      _timerActive = true;
    }
  }

  void _timeUp() {
    if (_answered) return;
    setState(() {
      _answered = true;
      _selectedIdx = -1;
      _wrong++;
      _combo = 0;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _started && !_finished) {
        setState(() => _currentIndex++);
        _nextRound();
      }
    });
  }

  void _selectOption(int idx) {
    if (_answered) return;
    final correct = _allCharPoems[_currentIndex];
    final chosen = _options[idx];
    final isCorrect = chosen.id == correct.id;

    setState(() {
      _answered = true;
      _selectedIdx = idx;
      if (isCorrect) {
        _combo++;
        _correct++;
        // 连击加分：基础 10 + 连击奖励（最高 +15）
        final bonus = _combo > 1 ? min(_combo - 1, 15) : 0;
        _score += 10 + bonus;
      } else {
        _combo = 0;
        _wrong++;
        // 错误扣 5 分（不低于 0）
        _score = max(0, _score - 5);
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _started && !_finished) {
        setState(() => _currentIndex++);
        _nextRound();
      }
    });
  }

  void _finishGame() {
    _timerCtrl.stop();
    setState(() {
      _finished = true;
      _timerActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('飞花令')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('飞花令')),
      body: _started
          ? _finished
              ? _buildResult(theme)
              : _buildGame(theme)
          : _buildStart(theme),
    );
  }

  // ---- 开始页 ----
  Widget _buildStart(ThemeData theme) {
    final c = ShiciColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PoemIcon(PoemIcons.feihualing, size: 64, color: c.cinnabar),
            const SizedBox(height: 16),
            Text('飞花令',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '「飞花令」原为古人行酒令的一种，\n'
              '以「花」为令，轮流背诵含「花」的诗句。\n\n'
              '现代飞花令以任意汉字为题：\n'
              '给你一个字，选出包含该字的诗句，\n'
              '连续答对可获得连击加分！',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.silk,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('今日令字：',
                      style: theme.textTheme.bodyMedium),
                  Text(
                    _t(_playChar),
                    style: TextStyle(
                      fontSize: 48,
                      fontFamily: 'serif',
                      fontWeight: FontWeight.bold,
                      color: c.cinnabar,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('共 ${_allCharPoems.length} 首包含「${_t(_playChar)}」的诗，本局答 $_totalRounds 题',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _allCharPoems.isEmpty ? null : _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.pine,
                foregroundColor: c.onAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('开始挑战', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 游戏进行中 ----
  Widget _buildGame(ThemeData theme) {
    final c = ShiciColors.of(context);
    return Column(
      children: [
        // 顶栏：进度 + 分数 + 连击
        _buildScoreBar(theme),
        // 倒计时条
        if (_timerActive)
          AnimatedBuilder(
            animation: _timerCtrl,
            builder: (_, __) => LinearProgressIndicator(
              value: 1.0 - _timerCtrl.value,
              backgroundColor: c.sand,
              valueColor: AlwaysStoppedAnimation<Color>(
                _timerCtrl.value > 0.3 ? c.pine : c.cinnabar,
              ),
              minHeight: 4,
            ),
          ),
        // 题目区
        Expanded(
          child: _currentIndex >= _totalRounds
              ? const Center(child: CircularProgressIndicator())
              : _buildQuestion(theme),
        ),
      ],
    );
  }

  Widget _buildScoreBar(ThemeData theme) {
    final c = ShiciColors.of(context);
    final total = _totalRounds;
    final progress = total > 0 ? (_currentIndex + 1) / total : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          // 进度
          Text(
            '${_currentIndex + 1}/$total',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: c.sand,
              valueColor: AlwaysStoppedAnimation<Color>(c.pine),
              minHeight: 4,
            ),
          ),
          const SizedBox(width: 12),
          // 分数
          Icon(Icons.star, color: c.gamboge, size: 18),
          const SizedBox(width: 4),
          Text('$_score',
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold, color: c.gamboge)),
          // 连击
          if (_combo > 1) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.cinnabar,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('×$_combo',
                  style: TextStyle(
                      color: c.onAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestion(ThemeData theme) {
    final c = ShiciColors.of(context);
    final correct = _allCharPoems[_currentIndex];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 提示
          Text(
            '以下哪首诗包含「${_t(_playChar)}」字？',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // 选项
          Expanded(
            child: ListView.builder(
              itemCount: _options.length,
              itemBuilder: (_, i) {
                final opt = _options[i];
                final isChosen = _selectedIdx == i;
                final isCorrectOpt = opt.id == correct.id;
                Color? bgColor;
                Color? borderColor;
                if (_answered) {
                  if (isCorrectOpt) {
                    bgColor = c.pine.withOpacity(0.12);
                    borderColor = c.pine;
                  } else if (isChosen && !isCorrectOpt) {
                    bgColor = c.cinnabar.withOpacity(0.12);
                    borderColor = c.cinnabar;
                  }
                }
                // 答题前：节选前两行（考验是否记得全文）
                // 答题后：正确项展示「含令字的原句」并高亮，避免只凭标题猜
                String preview;
                if (!_answered) {
                  final raw = opt.content.replaceAll('\n', ' ');
                  preview = raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
                } else if (isCorrectOpt) {
                  preview = _matchingSnippet(opt) ?? opt.content;
                } else {
                  final raw = opt.content.replaceAll('\n', ' ');
                  preview = raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: bgColor ??
                        theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: borderColor ?? Colors.transparent, width: 2),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _answered ? null : () => _selectOption(i),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(opt.title),
                              style: TextStyle(
                                fontFamily: 'serif',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _answered && isCorrectOpt
                                    ? c.pine
                                    : _answered && isChosen && !isCorrectOpt
                                        ? c.cinnabar
                                        : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_answered && isCorrectOpt)
                              _highlightLine(_t(preview), theme, c, revealed: true)
                            else
                              Text(
                                _t(preview),
                                style: theme.textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 答错时显示正确答案的包含字位置
          if (_answered)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                () {
                  if (_selectedIdx == null || _selectedIdx == -1) {
                    final snip = _matchingSnippet(correct);
                    return snip == null
                        ? '⏱ 时间到！「${_t(_playChar)}」出自《${_t(correct.title)}》'
                        : '⏱ 时间到！「${_t(_playChar)}」出自《${_t(correct.title)}》：${_t(snip)}';
                  }
                  if (_options[_selectedIdx!].id == correct.id) {
                    final snip = _matchingSnippet(correct);
                    return snip == null
                        ? '✅ 正确！「${_t(_playChar)}」出自《${_t(correct.title)}》'
                        : '✅ 正确！「${_t(_playChar)}」出自《${_t(correct.title)}》：${_t(snip)}';
                  }
                  final snip = _matchingSnippet(correct);
                  return snip == null
                      ? '❌ 「${_t(_playChar)}」出自《${_t(correct.title)}》'
                      : '❌ 「${_t(_playChar)}」出自《${_t(correct.title)}》：${_t(snip)}';
                }(),
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  // ---- 结算页 ----
  Widget _buildResult(ThemeData theme) {
    final c = ShiciColors.of(context);
    final total = _correct + _wrong;
    final rate = total > 0 ? (_correct / total * 100).round() : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PoemIcon(
              _score > 100 ? PoemIcons.achievement : PoemIcons.feihualing,
              size: 64,
              color: _score > 100 ? c.gamboge : c.cinnabar,
            ),
            const SizedBox(height: 16),
            Text('飞花令结束',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            // 得分
            Text(
              '$_score',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                fontFamily: 'serif',
                color: c.gamboge,
              ),
            ),
            Text('分', style: TextStyle(color: c.inkSoft)),
            const SizedBox(height: 16),
            // 统计
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _resultStat('正确', '$_correct', c.pine, theme),
                _resultStat('错误', '$_wrong', c.cinnabar, theme),
                _resultStat('正确率', '$rate%', c.pine, theme),
              ],
            ),
            const SizedBox(height: 32),
            // 评价
            Text(
              _score >= 200
                  ? '🏆 诗神驾到！博闻强记！'
                  : _score >= 100
                      ? '👏 学富五车，功底扎实！'
                      : _score >= 50
                          ? '📚 继续加油，多读多记！'
                          : '🌱 初出茅庐，来日方长！',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () async {
                    // 重新加载数据并重开
                    setState(() {
                      _loading = true;
                      _started = false;
                      _finished = false;
                    });
                    await _init();
                    _startGame();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.pine,
                    foregroundColor: c.onAccent,
                  ),
                  child: const Text('再来一轮'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultStat(
      String label, String value, Color color, ThemeData theme) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'serif')),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
