import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/design_tokens.dart';
import '../../core/tts_service.dart';
import '../../core/s2t_converter.dart';
import '../../core/achievement_service.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart' show Poem, Author, StudyNote;
import '../../utils/pinyin_helper.dart';
import '../widgets/poem_icon.dart';
import '../widgets/note_dialogs.dart'
    show runEditFlow, runDeleteFlow, EditOutcome;
import 'author_detail_page.dart';
import 'create_plan_page.dart';
import 'recall_quiz_page.dart';
import 'poem_card_page.dart';

/// 诗词详情页：原文/注释/译文/赏析，沉浸式阅读
class PoemDetailPage extends StatefulWidget {
  final int poemId;

  const PoemDetailPage({super.key, required this.poemId});

  @override
  State<PoemDetailPage> createState() => _PoemDetailPageState();
}

class _PoemDetailPageState extends State<PoemDetailPage> {
  Poem? _poem;
  Author? _author;
  bool _isFavorite = false;
  bool _loading = true;
  bool _showTranslation = true;
  bool _showNotes = true;
  bool _showAppreciation = true;
  bool _showBackground = false;
  double _fontSize = 18.0;
  bool _immersive = false;
  String _fontFamily = 'serif';
  bool _traditionalChinese = false;
  bool _showPinyin = false;

  /// 根据繁简设置转换文本
  /// 默认模式（简体）：先确保简体（兜底旧数据可能含繁体字）
  /// 繁体模式：简体→繁体
  String _t(String text) => _traditionalChinese
      ? S2TConverter.toTraditional(text)
      : S2TConverter.toSimplified(text);

  // TTS
  final _tts = TtsService.instance;
  bool _ttsPlaying = false;
  double _ttsRate = 1.0;

  // 导航
  int? _prevId;
  int? _nextId;

  // 笔记
  final _noteController = TextEditingController();
  final _noteFocusNode = FocusNode();
  List<StudyNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadData();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fontSize = prefs.getDouble('font_size') ?? 18.0;
        _fontFamily = prefs.getString('font_family') ?? 'serif';
        _traditionalChinese = prefs.getBool('traditional_chinese') ?? false;
        _showPinyin = prefs.getBool('show_pinyin') ?? false;
      });
    }
  }

  Future<void> _loadData() async {
    final poem = await DatabaseHelper.getPoemById(widget.poemId);
    Author? author;
    if (poem?.authorId != null) {
      author = await DatabaseHelper.getAuthorById(poem!.authorId!);
    }
    final fav = poem != null ? await DatabaseHelper.isFavorite(poem.id) : false;
    final prevId =
        poem != null ? await DatabaseHelper.getPrevPoemId(poem.id) : null;
    final nextId =
        poem != null ? await DatabaseHelper.getNextPoemId(poem.id) : null;
    final notes = poem != null
        ? await DatabaseHelper.getNotesByPoem(poem.id)
        : <StudyNote>[];
    // 记录阅读历史
    if (poem != null) {
      await DatabaseHelper.addReadingHistory(poem.id);
    }
    if (mounted) {
      setState(() {
        _poem = poem;
        _author = author;
        _isFavorite = fav;
        _prevId = prevId;
        _nextId = nextId;
        _notes = notes;
        _loading = false;
      });
    }
  }

  /// 打开诗人详情页（顺着作者看他的其他作品）
  void _openAuthor(Poem poem) {
    final id = poem.authorId;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AuthorDetailPage(authorId: id, authorName: poem.authorName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = ShiciColors.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_poem == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('未找到该诗词')),
      );
    }

    final poem = _poem!;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PrevIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextIntent(),
        SingleActivator(LogicalKeyboardKey.space): _TtsIntent(),
        SingleActivator(LogicalKeyboardKey.keyF): _FavIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _ExitIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PrevIntent: CallbackAction<_PrevIntent>(onInvoke: (_) {
            if (_prevId != null) _navigateTo(_prevId!);
            return null;
          }),
          _NextIntent: CallbackAction<_NextIntent>(onInvoke: (_) {
            if (_nextId != null) _navigateTo(_nextId!);
            return null;
          }),
          _TtsIntent: CallbackAction<_TtsIntent>(onInvoke: (_) {
            _toggleTts();
            return null;
          }),
          _FavIntent: CallbackAction<_FavIntent>(onInvoke: (_) {
            _toggleFavorite();
            return null;
          }),
          _ExitIntent: CallbackAction<_ExitIntent>(onInvoke: (_) {
            if (_immersive) {
              setState(() => _immersive = false);
            } else {
              Navigator.of(context).pop();
            }
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: _immersive ? Colors.black : null,
            appBar: _immersive
                ? null
                : AppBar(
                    // 画布顶栏不放诗题（诗题在内容区以大字号居中呈现），
                    // 只保留「返回 / 朗读 / 收藏」
                    actions: [
                      IconButton(
                        onPressed: _toggleTts,
                        icon: PoemIcon(
                          PoemIcons.tts,
                          color: _ttsPlaying ? AppTheme.zhuShaHong : null,
                        ),
                        tooltip: '朗读',
                      ),
                      IconButton(
                        onPressed: () => _toggleFavorite(),
                        icon: PoemIcon(
                          PoemIcons.bookmark,
                          color: _isFavorite ? AppTheme.zhuShaHong : null,
                        ),
                        tooltip: _isFavorite ? '取消收藏' : '收藏',
                      ),
                    ],
                  ),
            body: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                if (details.primaryVelocity! > 200 && _prevId != null) {
                  _navigateTo(_prevId!);
                } else if (details.primaryVelocity! < -200 && _nextId != null) {
                  _navigateTo(_nextId!);
                }
              },
              child: Stack(
                children: [
                  ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: _immersive ? 32 : 20,
                      vertical: _immersive ? 40 : 24,
                    ),
                    children: [
                      if (_immersive) ...[
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.fullscreen_exit,
                                color: Colors.white70),
                            onPressed: () => setState(() => _immersive = false),
                            tooltip: '退出沉浸模式',
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      // 诗名：28 号居中（默认字号 18 + 10），全屏视觉焦点
                      Center(
                        child: Text(
                          _t(poem.title),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _fontSize + 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                            color: _immersive ? Colors.white : pal.ink,
                            fontFamily: _fontFamily,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 作者行：小圆印 + 朝代 · 作者 · 体裁（点进诗人页）
                      Center(
                        child: (poem.authorId != null && !_immersive)
                            ? InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _openAuthor(poem),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  child: _authorLine(poem),
                                ),
                              )
                            : _authorLine(poem),
                      ),
                      const SizedBox(height: 18),
                      // 诗体：居中、行距 2.0。点击进入沉浸阅读
                      // （画布顶栏没有沉浸入口，用「点正文」承载）
                      GestureDetector(
                        onTap: _immersive
                            ? null
                            : () => setState(() => _immersive = true),
                        onLongPress: _immersive ? null : _showPoemActions,
                        child: Center(
                          child: _showPinyin
                              ? _buildPinyinText(_t(poem.content), theme)
                              : Text(
                                  _t(poem.content),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: _fontSize,
                                    height: 2.0,
                                    fontFamily: _fontFamily,
                                    color: _immersive
                                        ? Colors.white
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildDivider(theme),
                      const SizedBox(height: 18),
                      // 注释
                      if (_showNotes && poem.notes.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildCollapsibleSection(
                          theme,
                          '注 释',
                          PoemIcons.note,
                          _showNotes,
                          () => setState(() => _showNotes = !_showNotes),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: poem.notes
                                .map((n) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                              fontSize: _fontSize - 2,
                                              height: 1.8,
                                              color: _immersive
                                                  ? Colors.white70
                                                  : theme.colorScheme.onSurface,
                                              fontFamily: _fontFamily),
                                          children: [
                                            TextSpan(
                                                text: '【${_t(n.word)}】',
                                                style: TextStyle(
                                                    color: theme
                                                        .colorScheme.secondary,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            TextSpan(text: _t(n.meaning)),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                      // 译文
                      if (poem.translation != null) ...[
                        const SizedBox(height: 24),
                        _buildCollapsibleSection(
                          theme,
                          '译 文',
                          PoemIcons.recite,
                          _showTranslation,
                          () => setState(
                              () => _showTranslation = !_showTranslation),
                          Text(
                            _t(poem.translation!),
                            style: TextStyle(
                                fontSize: _fontSize - 2,
                                height: 1.8,
                                color: _immersive
                                    ? Colors.white70
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.85)),
                          ),
                        ),
                      ],
                      // 赏析
                      if (poem.appreciation != null) ...[
                        const SizedBox(height: 24),
                        _buildCollapsibleSection(
                          theme,
                          '赏 析',
                          PoemIcons.star,
                          _showAppreciation,
                          () => setState(
                              () => _showAppreciation = !_showAppreciation),
                          Text(
                            _t(poem.appreciation!),
                            style: TextStyle(
                                fontSize: _fontSize - 2,
                                height: 1.8,
                                color: _immersive
                                    ? Colors.white70
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.85)),
                          ),
                        ),
                      ],
                      // 创作背景
                      if (poem.background != null) ...[
                        const SizedBox(height: 24),
                        _buildCollapsibleSection(
                          theme,
                          '创作背景',
                          PoemIcons.dynasty,
                          _showBackground,
                          () => setState(
                              () => _showBackground = !_showBackground),
                          Text(
                            _t(poem.background!),
                            style: TextStyle(
                                fontSize: _fontSize - 2,
                                height: 1.8,
                                color: _immersive
                                    ? Colors.white70
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.85)),
                          ),
                        ),
                      ],
                      // 作者生平
                      if (_author?.bio != null) ...[
                        const SizedBox(height: 24),
                        _buildSection(
                          theme,
                          '作者简介',
                          PoemIcons.poet,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(_author!.bio!),
                                style: TextStyle(
                                    fontSize: _fontSize - 2,
                                    height: 1.8,
                                    color: _immersive
                                        ? Colors.white70
                                        : theme.colorScheme.onSurface
                                            .withOpacity(0.85)),
                              ),
                              if (!_immersive) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _openAuthor(poem),
                                    icon: const PoemIcon(PoemIcons.library,
                                        size: 16),
                                    label: Text(
                                        '查看${_t(_author!.name)}的全部作品',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      // 底部操作栏
                      if (!_immersive) _buildActionBar(theme),
                      const SizedBox(height: 20),
                      // 上一篇/下一篇
                      if (!_immersive) _buildNavButtons(theme),
                      const SizedBox(height: 20),
                      // 学习笔记
                      if (!_immersive) _buildNotesSection(theme),
                      const SizedBox(height: 40),
                    ],
                  ),
                  // TTS 控制条
                  if (_ttsPlaying && !_immersive)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildTtsBar(theme),
                    ),
                ],
              ),
            ),
            floatingActionButton: !_immersive
                ? FloatingActionButton(
                    onPressed: _markAsStudied,
                    tooltip: '标记已学习',
                    child: const Icon(Icons.check),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// 分割纹：左右细线夹一枚朱砂小方印（画布上的「分割纹」）
  Widget _buildDivider(ThemeData theme) {
    final color = _immersive ? Colors.white : theme.colorScheme.outline;
    return Row(
      children: [
        Expanded(child: Divider(color: color.withOpacity(0.25), height: 1)),
        const SizedBox(width: 10),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _immersive ? Colors.white70 : AppTheme.zhuShaHong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: color.withOpacity(0.25), height: 1)),
      ],
    );
  }

  /// 作者行：小圆印 + 朝代 · 作者 · 体裁
  Widget _authorLine(Poem poem) {
    final isLight = !_immersive;
    final fg = _immersive
        ? Colors.white60
        : ShiciColors.of(context).inkSoft;
    final parts = <String>[
      if ((poem.dynastyName ?? '').isNotEmpty) _t(poem.dynastyName!),
      _t(poem.authorName ?? '佚名'),
      if ((poem.type ?? '').isNotEmpty) _t(poem.type!),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isLight
                  ? AppTheme.zhuShaHong
                  : Colors.white.withOpacity(0.6),
              width: 1.2,
            ),
          ),
          child: Text(
            '雅',
            style: ShiciText.calligraphy.copyWith(
              fontSize: 10,
              height: 1.0,
              color: isLight ? AppTheme.zhuShaHong : Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          parts.join(' · '),
          style: TextStyle(
            fontSize: 13,
            color: fg,
            fontFamily: _fontFamily,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
      ThemeData theme, String title, Object icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(title),
        const SizedBox(height: 10),
        content,
      ],
    );
  }

  /// 区块小标签：朱砂 11 号 + 字间距 2（画布上「译 文」「赏 析」的写法）
  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: ShiciText.caption.copyWith(
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
        color: _immersive ? Colors.white70 : AppTheme.zhuShaHong,
      ),
    );
  }

  /// 在每行汉字上方显示拼音（每个字符拼音在上，字符在下）
  Widget _buildPinyinText(String text, ThemeData theme) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: lines.map((line) => _buildPinyinLine(line, theme)).toList(),
    );
  }

  Widget _buildPinyinLine(String line, ThemeData theme) {
    if (line.trim().isEmpty) return const SizedBox(height: 8);
    final pairs = PinyinHelper.splitWithPinyin(line);
    final textColor =
        _immersive ? Colors.white : theme.colorScheme.onSurface;
    final pinyinColor =
        _immersive ? Colors.white70 : theme.colorScheme.primary;
    // 计算拼音字号：取最长拼音动态缩放，确保不截断
    double pinyinFontSize = _fontSize * 0.48;
    final maxPyLen = pairs
        .where((p) => p.py.isNotEmpty)
        .fold<int>(0, (mx, p) => p.py.length > mx ? p.py.length : mx);
    if (maxPyLen > 5) pinyinFontSize = _fontSize * 0.42;
    if (maxPyLen > 6) pinyinFontSize = _fontSize * 0.38;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 0,
          runSpacing: 0,
          children: pairs.map((p) {
            if (p.py.isEmpty) {
              // 标点/空格：只显示字符，高度与汉字行对齐
              return Text(p.ch,
                  style: TextStyle(
                    fontSize: _fontSize,
                    fontFamily: _fontFamily,
                    color: textColor,
                  ));
            }
            // 汉字：拼音在上，字在下，自然宽度
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.py,
                      style: TextStyle(
                        fontSize: pinyinFontSize,
                        color: pinyinColor,
                        height: 1.0,
                      )),
                  Text(p.ch,
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontFamily: _fontFamily,
                        color: textColor,
                      )),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCollapsibleSection(ThemeData theme, String title, Object icon,
      bool expanded, VoidCallback onToggle, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              _sectionLabel(title),
              const Spacer(),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color:
                      _immersive ? Colors.white60 : theme.colorScheme.outline),
            ],
          ),
        ),
        if (expanded) ...[const SizedBox(height: 10), content],
      ],
    );
  }

  /// 底部操作条：一个主按钮 + 两个圆形次按钮（对齐画布）
  Widget _buildActionBar(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _startRecite,
              child: const Text('开始背诵'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _CircleAction(
          icon: PoemIcons.note,
          tooltip: '笔记',
          onTap: _focusNote,
        ),
        const SizedBox(width: 12),
        _CircleAction(
          icon: PoemIcons.share,
          tooltip: '分享',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PoemCardPage(poem: _poem!)),
          ),
        ),
      ],
    );
  }

  /// 长按诗体：收纳画布上没有画、但功能上需要的两个动作
  void _showPoemActions() {
    final c = ShiciColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.silk,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ShiciSize.rLg)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: PoemIcon(PoemIcons.goal, color: c.ink),
              title: Text('加入学习计划',
                  style: ShiciText.heading.copyWith(color: c.ink)),
              onTap: () {
                Navigator.of(ctx).pop();
                _addToPlan();
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: c.ink, size: 22),
              title: Text('复制全文',
                  style: ShiciText.heading.copyWith(color: c.ink)),
              onTap: () {
                Navigator.of(ctx).pop();
                _copyPoemText();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 开始背诵：把当前这首丢进背诵自测
  void _startRecite() {
    final poem = _poem;
    if (poem == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecallQuizPage(title: '背诵 · ${poem.title}', poemIds: <int>[poem.id]),
    ));
  }

  /// 笔记：滚到笔记区并把焦点交给输入框
  void _focusNote() {
    _noteFocusNode.requestFocus();
  }

  Widget _buildNavButtons(ThemeData theme) {
    return Row(
      children: [
        if (_prevId != null)
          Expanded(
            child: ShadButton.ghost(
              onPressed: () => _navigateTo(_prevId!),
              icon: const Icon(Icons.chevron_left),
              child: const Text('上一篇'),
            ),
          )
        else
          const Spacer(),
        if (_nextId != null)
          Expanded(
            child: ShadButton.ghost(
              onPressed: () => _navigateTo(_nextId!),
              icon: const Icon(Icons.chevron_right),
              child: const Text('下一篇'),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }

  Widget _buildTtsBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          const PoemIcon(PoemIcons.tts,
              color: AppTheme.zhuShaHong, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('正在朗读...', style: theme.textTheme.bodySmall),
          ),
          // 倍速选择
          PopupMenuButton<double>(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${_ttsRate}x',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurface)),
            ),
            onSelected: (r) {
              setState(() => _ttsRate = r);
              _tts.setRate(r);
            },
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                .map((r) => PopupMenuItem(value: r, child: Text('${r}x')))
                .toList(),
          ),
          IconButton(
            icon: Icon(_ttsPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleTts,
            tooltip: _ttsPlaying ? '暂停朗读' : '开始朗读',
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stopTts,
            tooltip: '停止朗读',
          ),
        ],
      ),
    );
  }

  /// 一键复制诗词原文到剪贴板
  void _copyPoemText() {
    if (_poem == null) return;
    final poem = _poem!;
    final text = '《${poem.title}》\n'
        '${poem.authorName ?? ''}\n\n'
        '${poem.content}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleTts() async {
    if (_poem == null) return;
    if (_ttsPlaying) {
      await _tts.stop();
      setState(() => _ttsPlaying = false);
    } else {
      await _tts.setRate(_ttsRate);
      await _tts.speak('${_poem!.title}。${_poem!.content}');
      setState(() => _ttsPlaying = true);
    }
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() => _ttsPlaying = false);
  }

  Future<void> _toggleFavorite() async {
    if (_poem == null) return;
    if (_isFavorite) {
      await DatabaseHelper.removeFavorite(_poem!.id);
    } else {
      await DatabaseHelper.addFavorite(_poem!.id);
    }
    setState(() => _isFavorite = !_isFavorite);
    AchievementService.instance.sync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isFavorite ? '已加入收藏' : '已取消收藏'),
            duration: const Duration(seconds: 1)),
      );
    }
  }

  /// 把当前诗词加入学习计划
  ///
  /// 弹出计划列表供选择；也可直接跳到创建页新建（并把本诗预选上）。
  Future<void> _addToPlan() async {
    final poem = _poem;
    if (poem == null) return;
    final plans = await DatabaseHelper.getStudyPlans();
    if (!mounted) return;

    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '加入到学习计划',
                style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
            if (plans.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有学习计划，可以先新建一个'),
              )
            else
              ...plans.map((p) {
                final alreadyIn = p.poemIds.contains(poem.id);
                return ListTile(
                  leading: PoemIcon(
                    alreadyIn ? PoemIcons.done : PoemIcons.goal,
                    color: alreadyIn ? AppTheme.songLv : AppTheme.daiLan,
                  ),
                  title: Text(p.name),
                  subtitle: Text(alreadyIn ? '已在计划中' : '${p.poemIds.length} 首'),
                  onTap: () => Navigator.pop(ctx, p.id),
                );
              }),
            ListTile(
              leading: const Icon(Icons.add, color: AppTheme.zhuShaHong),
              title: const Text('新建学习计划',
                  style: TextStyle(color: AppTheme.zhuShaHong)),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;

    // -1 表示「新建计划」
    if (target == -1) {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => CreatePlanPage(initialPoemIds: [poem.id])),
      );
      return;
    }

    final added = await DatabaseHelper.addPoemsToPlan(target, [poem.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0 ? '已加入学习计划' : '该计划中已有这首诗'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _markAsStudied() async {
    if (_poem == null) return;
    await DatabaseHelper.markPoemStudied(_poem!.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已标记为已学，继续加油！'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _navigateTo(int id) {
    _stopTts();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: id)),
    );
  }

  Widget _buildNotesSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PoemIcon(PoemIcons.note,
                  size: 20, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text('学习笔记',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                      fontFamily: 'serif')),
              const SizedBox(width: 8),
              if (_notes.isNotEmpty)
                ShadBadge.secondary(
                  child: Text('${_notes.length}'),
                ),
              const Spacer(),
              Text(_notes.isEmpty ? '添加第一条感悟吧' : '${_notes.length}条',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          // 新增输入
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ShadInput(
                  controller: _noteController,
                  maxLines: 3,
                  minLines: 2,
                  placeholder: const Text('写下你的学习感悟、批注、感想……'),
                ),
              ),
              const SizedBox(width: 8),
              ShadButton(
                onPressed: _saveNote,
                icon: const Icon(Icons.send, size: 16),
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('还没有笔记',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
            )
          else
            ..._notes.map((note) => _buildNoteCard(note, theme)),
        ],
      ),
    );
  }

  Widget _buildNoteCard(StudyNote note, ThemeData theme) {
    final date = note.updatedAt ?? note.createdAt;
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(note.content),
            style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: theme.colorScheme.onSurface,
                fontFamily: _fontFamily),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              PoemIcon(PoemIcons.duration,
                  size: 12, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(date.length > 16 ? date.substring(0, 16) : date,
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.outline))),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _editNote(note, theme),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PoemIcon(PoemIcons.edit,
                        size: 13, color: theme.colorScheme.outline),
                    const SizedBox(width: 2),
                    Text('编辑',
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline)),
                  ]),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _delNote(note),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline,
                        size: 13, color: AppTheme.zhuShaHong),
                    SizedBox(width: 2),
                    Text('删除',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.zhuShaHong)),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveNote() async {
    if (_poem == null) return;
    final content = _noteController.text.trim();
    if (content.isEmpty) return;
    await DatabaseHelper.addNote(_poem!.id, content);
    _noteController.clear();
    final newNotes = await DatabaseHelper.getNotesByPoem(_poem!.id);
    if (mounted) {
      setState(() => _notes = newNotes);
      AchievementService.instance.sync();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('笔记已保存'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _editNote(StudyNote note, ThemeData theme) async {
    final outcome = await runEditFlow(
      context,
      noteId: note.id,
      currentContent: note.content,
      onSave: DatabaseHelper.updateNote,
      maxLines: 5,
    );
    if (outcome == EditOutcome.changed && _poem != null && mounted) {
      final newNotes = await DatabaseHelper.getNotesByPoem(_poem!.id);
      setState(() => _notes = newNotes);
    }
  }

  Future<void> _delNote(StudyNote note) async {
    final deleted = await runDeleteFlow(
      context,
      noteId: note.id,
      onDelete: DatabaseHelper.deleteNote,
    );
    if (deleted == true && _poem != null && mounted) {
      final newNotes = await DatabaseHelper.getNotesByPoem(_poem!.id);
      setState(() => _notes = newNotes);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }
}

/// 圆形次按钮：52×52 绢白圆 + 描边 + 自有图标（画布底部操作条的两个次按钮）
class _CircleAction extends StatelessWidget {
  final Object icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleAction(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.silk,
            border: Border.all(color: c.line),
          ),
          child: Center(child: PoemIcon(icon, size: 22, color: c.ink)),
        ),
      ),
    );
  }
}

// 键盘快捷键 Intent 类
class _PrevIntent extends Intent {
  const _PrevIntent();
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _TtsIntent extends Intent {
  const _TtsIntent();
}

class _FavIntent extends Intent {
  const _FavIntent();
}

class _ExitIntent extends Intent {
  const _ExitIntent();
}
