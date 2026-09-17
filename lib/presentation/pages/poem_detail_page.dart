import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/design_tokens.dart';
import '../../core/content_quality.dart';
import '../../core/tts_service.dart';
import '../../core/s2t_converter.dart';
import '../../core/achievement_service.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart' show Poem, Author, StudyNote;
import '../../utils/pinyin_helper.dart';
import '../../utils/verse_splitter.dart';
import '../widgets/poem_icon.dart';
import '../widgets/poem_parallel_card.dart';
import '../widgets/note_dialogs.dart'
    show runEditFlow, runDeleteFlow, EditOutcome;
import 'author_detail_page.dart';
import 'create_plan_page.dart';
import 'recall_quiz_page.dart';
import 'poem_card_page.dart';
import 'copy_practice_page.dart';

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

  /// 阅读模式 —— 通读（分节展开） / 对照（05 赏析 · 注释卡）
  PoemReadingMode _readingMode = PoemReadingModeStore.fallback;
  String _fontFamily = 'serif';
  bool _traditionalChinese = false;
  bool _showPinyin = false;

  /// 根据繁简设置转换文本
  /// 默认模式（简体）：先确保简体（兜底旧数据可能含繁体字）
  /// 繁体模式：简体→繁体
  String _t(String text) => _traditionalChinese
      ? S2TConverter.toTraditional(text)
      : S2TConverter.toSimplified(text);

  /// 用户对译文/赏析/背景的本地补写，键为 [ContentField.name]。
  ///
  /// 与 `poems` 表里的内容分开存：后者是 assets 播种 + 离线包导入的可再生数据，
  /// 升级时会整块重建；用户写的东西必须活过那些迁移。
  Map<String, String> _overrides = const {};

  /// 展示用文本：本地补写优先，其次包内内容。
  ///
  /// 返回 null 表示这一项确实没有内容（既不显示区块，也不给徽标）。
  String? _contentOf(ContentField field, String? builtIn) {
    final own = _overrides[field.name];
    if (own != null && own.trim().isNotEmpty) return own;
    final v = builtIn?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  /// 这一项的等级：本地补写过就算「自己的」，否则交给分级表。
  ContentLevel _levelOf(ContentField field, String? builtIn) {
    if (_overrides[field.name]?.trim().isNotEmpty ?? false) {
      return ContentLevel.curated;
    }
    return ContentQuality.levelOf(widget.poemId, field);
  }

  // TTS
  final _tts = TtsService.instance;
  bool _ttsPlaying = false;
  double _ttsRate = 1.0;

  // 逐句跟读
  /// 当前正在念的句（由 [splitVerses] 断出来的片段）
  List<String> _verses = const [];
  int _verseIndex = 0;
  bool _following = false;

  /// 单句循环：适合「这一句读不顺，反复跟读」
  bool _loopVerse = false;

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
    // 阅读模式走自己的 store（全局偏好，与篇目无关）
    final mode = await PoemReadingModeStore.load();
    if (mounted) setState(() => _readingMode = mode);
  }

  /// 是否按对照读法渲染。
  ///
  /// 沉浸模式优先渲染「只有诗」，所以那里不叠对照卡。
  bool get _parallel =>
      _readingMode == PoemReadingMode.parallel && !_immersive;

  Future<void> _pickReadingMode() async {
    final picked =
        await showPoemReadingModePicker(context, current: _readingMode);
    if (picked == null || picked == _readingMode) return;
    setState(() => _readingMode = picked);
    await PoemReadingModeStore.save(picked);
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
    // 内容分级表与本地补写：都在首帧前读完，否则会先渲染没有徽标的版本再跳变
    await ContentQuality.load();
    final overrides = await DatabaseHelper.getPoemOverrides(widget.poemId);
    if (mounted) {
      setState(() {
        _poem = poem;
        _author = author;
        _isFavorite = fav;
        _prevId = prevId;
        _nextId = nextId;
        _notes = notes;
        _overrides = overrides;
        _loading = false;
      });
    }
  }

  /// 开始逐句跟读（[from] 为起始句下标）。
  ///
  /// 每次调用都会先停掉上一段朗读：切句、点「再念一遍」都走这里，
  /// 不必再单独实现一套「重读某句」的路径。
  Future<void> _startFollow({int from = 0}) async {
    final poem = _poem;
    if (poem == null) return;
    final verses = splitVerses(poem.content);
    if (verses.isEmpty) return;

    setState(() {
      _verses = verses;
      _verseIndex = from.clamp(0, verses.length - 1);
      _following = true;
      _ttsPlaying = false;
    });

    await _tts.speakVerses(
      verses,
      from: _verseIndex,
      onVerse: (i) {
        if (mounted) setState(() => _verseIndex = i);
      },
      loopAt: (i) => _loopVerse && i == _verseIndex,
      onFinished: () {
        if (mounted) setState(() => _following = false);
      },
    );
  }

  Future<void> _stopFollow() async {
    await _tts.stop();
    if (mounted) setState(() => _following = false);
  }

  /// 上一句 / 下一句：停下当前句，从目标句重新开始
  void _jumpVerse(int delta) {
    if (_verses.isEmpty) return;
    final next =
        (_verseIndex + delta).clamp(0, _verses.length - 1);
    _startFollow(from: next);
  }

  /// 跟读中高亮：正文的哪一行包含当前句
  bool _isCurrentVerseLine(String line) {
    if (!_following || _verseIndex >= _verses.length) return false;
    return verseMatchesLine(_verses[_verseIndex], line);
  }

  // ── 点字查字 ──────────────────────────────────────────────────────
  //
  // 每个汉字一个 TapGestureRecognizer，按**字符**缓存复用（同一首诗里「月」出现
  // 十次也只建一个）。晚于 build 创建、在 dispose 统一释放 —— 在 build 里现建现用
  // 会每次重建都漏一批 recognizer。
  final Map<String, TapGestureRecognizer> _charRecognizers = {};

  TapGestureRecognizer _recognizerFor(String ch) {
    return _charRecognizers.putIfAbsent(ch, () {
      final recognizer = TapGestureRecognizer();
      recognizer.onTap = () => _lookupChar(ch);
      return recognizer;
    });
  }

  /// 点字查字：拼音 + 该字在别处的用例。
  ///
  /// 只给拼音与用例、**不给释义** —— 我们手上没有可离线分发的词典数据，
  /// 编不出来就不假装有（见 README「关于内容质量」）。
  Future<void> _lookupChar(String ch) async {
    final hits = await DatabaseHelper.searchVerses(ch, limit: 8);
    final poemCount = await DatabaseHelper.countPoemsContaining(ch);
    if (!mounted) return;

    final pinyin = PinyinHelper.pinyinOf(ch);
    final c = ShiciColors.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ShiciSize.rLg)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    ch,
                    style: TextStyle(
                      fontSize: 40,
                      height: 1.1,
                      fontFamily: _fontFamily,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      pinyin.isEmpty ? '（无读音）' : pinyin,
                      style: ShiciText.numeral.copyWith(
                        fontSize: 16,
                        color: c.cinnabar,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$poemCount 首诗用到过',
                      style: ShiciText.caption
                          .copyWith(fontSize: 11, color: c.inkSoft),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (hits.isEmpty)
                Text('没有找到用到这个字的诗句。',
                    style: ShiciText.caption.copyWith(color: c.inkSoft))
              else ...[
                Text('用例',
                    style: ShiciText.heading
                        .copyWith(fontSize: 13, color: c.ink)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: hits.length,
                    itemBuilder: (_, i) {
                      final hit = hits[i];
                      return InkWell(
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  PoemDetailPage(poemId: hit.poemId)));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                hit.verse,
                                style: ShiciText.body.copyWith(
                                    fontSize: 15, height: 1.7, color: c.ink),
                              ),
                              Text(
                                '——《${hit.title}》'
                                '${(hit.authorName ?? '').isEmpty ? '' : ' · ${hit.authorName}'}',
                                style: ShiciText.caption.copyWith(
                                    fontSize: 11, color: c.inkSoft),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  /// 正文里的汉字可点（标点、空白保持不可点：免得点个逗号弹出空卡）
  Widget _buildTappableBody(Poem poem, ThemeData theme) {
    final base = TextStyle(
      fontSize: _fontSize,
      height: 2.0,
      fontFamily: _fontFamily,
      color: !_immersive ? theme.colorScheme.onSurface : Colors.white, // keep: fixed-block
    );
    return Column(
      children: <Widget>[
        for (final line in _t(poem.content).split('\n'))
          if (line.trim().isEmpty)
            const SizedBox(height: 6)
          else
            Text.rich(
              TextSpan(style: base, children: _charSpans(line)),
              textAlign: TextAlign.center,
            ),
      ],
    );
  }

  List<InlineSpan> _charSpans(String line) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }

    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      if (isChineseChar(ch)) {
        flush();
        spans.add(TextSpan(text: ch, recognizer: _recognizerFor(ch)));
      } else {
        buffer.write(ch);
      }
    }
    flush();
    return spans;
  }

  /// 跟读时的正文：按行渲染，当前句所在的行转朱砂加粗。
  ///
  /// 只在跟读时改成分行渲染，不常开：平时整段 `Text` 的排版更紧凑，
  /// 折行位置交给字体决定；拆成逐行会让长句的换行点变化，属于无谓的视觉改动。
  Widget _buildFollowBody(Poem poem, ThemeData theme) {
    final c = ShiciColors.of(context);
    final base = TextStyle(
      fontSize: _fontSize,
      height: 2.0,
      fontFamily: _fontFamily,
      color: !_immersive ? theme.colorScheme.onSurface : Colors.white, // keep: fixed-block
    );
    return Column(
      children: <Widget>[
        for (final line in _t(poem.content).split('\n'))
          if (line.trim().isEmpty)
            const SizedBox(height: 6)
          else
            Text(
              line,
              textAlign: TextAlign.center,
              style: _isCurrentVerseLine(line)
                  ? base.copyWith(
                      color: c.cinnabar,
                      fontWeight: FontWeight.w600,
                    )
                  : base,
            ),
      ],
    );
  }

  /// 打开「补写这一段」编辑器。
  ///
  /// 存空字符串等于删除覆盖（DAO 里就这么实现的），所以「清空后保存」
  /// 会自然回到包内原文，不需要额外交代用户。
  Future<void> _editOverride(ContentField field, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('补写${_fieldLabel(field)}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '写下你自己的理解。清空内容保存即可恢复包内原文。',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;

    await DatabaseHelper.savePoemOverride(
        widget.poemId, field.name, saved);
    final overrides = await DatabaseHelper.getPoemOverrides(widget.poemId);
    if (!mounted) return;
    setState(() => _overrides = overrides);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved.trim().isEmpty ? '已恢复包内原文' : '已保存你的补写')),
    );
  }

  static String _fieldLabel(ContentField field) => switch (field) {
        ContentField.translation => '译文',
        ContentField.appreciation => '赏析',
        ContentField.background => '创作背景',
      };

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

    // 三个内容区块的最终文本：本地补写优先，其次包内原文
    final translation =
        _contentOf(ContentField.translation, poem.translation);
    final appreciation =
        _contentOf(ContentField.appreciation, poem.appreciation);
    final background = _contentOf(ContentField.background, poem.background);

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
            backgroundColor: _immersive ? Colors.black : null, // keep: fixed-block
            appBar: _immersive
                ? null
                : AppBar(
                    // 画布顶栏不放诗题（诗题在内容区以大字号居中呈现），
                    // 只保留「返回 / 朗读 / 收藏」
                    actions: [
                      // 阅读模式入口：通读 / 对照，选中对照时图标转为朱砂
                      IconButton(
                        onPressed: _pickReadingMode,
                        icon: PoemIcon(
                          PoemIcons.parallel,
                          color: _readingMode == PoemReadingMode.parallel
                              ? pal.cinnabar
                              : null,
                        ),
                        tooltip: '阅读模式：${_readingMode.label}',
                      ),
                      IconButton(
                        onPressed: _toggleTts,
                        icon: PoemIcon(
                          PoemIcons.tts,
                          color: _ttsPlaying ? pal.cinnabar : null,
                        ),
                        tooltip: '朗读',
                      ),
                      // 逐句跟读：念一句高亮一句，可单句循环
                      IconButton(
                        onPressed: () =>
                            _following ? _stopFollow() : _startFollow(),
                        icon: PoemIcon(
                          PoemIcons.recite,
                          color: _following ? pal.cinnabar : null,
                        ),
                        tooltip: _following ? '结束跟读' : '逐句跟读',
                      ),
                      IconButton(
                        onPressed: () => _toggleFavorite(),
                        icon: PoemIcon(
                          PoemIcons.bookmark,
                          color: _isFavorite ? pal.cinnabar : null,
                        ),
                        tooltip: _isFavorite ? '取消收藏' : '收藏',
                      ),
                      // 抄写 / 练字：把这首诗铺成米字格字帖
                      IconButton(
                        onPressed: _poem == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CopyPracticePage(poem: _poem!),
                                  ),
                                ),
                        icon: const Icon(Icons.brush, size: 22),
                        tooltip: '抄写',
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
                            color: _immersive ? Colors.white : pal.ink, // keep: fixed-block
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
                      // ── 对照读法（05 赏析 · 注释卡）─────────────────────────────
                      // 整块换掉「正文 + 注释 / 译文 / 赏析」这套分节：05 卡本身就是
                      // 「逐联原文 + 译文 + 赏析 + 注释」的一体化排版，两套并存只会重复。
                      if (_parallel) ...[
                        GestureDetector(
                          onLongPress: _showPoemActions,
                          // 换一份带覆盖内容的 Poem：对照卡是自己拆译文/赏析的，
                          // 不这么做的话「补写过的内容」在对照读法里会看不到
                          child: PoemParallelCard(
                            poem: poem.copyWithContent(
                              translation: translation,
                              appreciation: appreciation,
                              background: background,
                            ),
                            transform: _t,
                            showHeader: false,
                          ),
                        ),
                      ] else ...[
                        // 诗体：居中、行距 2.0。
                        // 手势分工：轻点**汉字**查读音与用例（见 _lookupChar），
                        // 长按出诗词操作，进沉浸走正文下方那个明确按钮 ——
                        // 原先「点正文进沉浸」会与点字冲突，二者只能留一个明确的。
                        GestureDetector(
                          onLongPress: _immersive ? null : _showPoemActions,
                          child: Center(
                            child: _showPinyin
                                ? _buildPinyinText(_t(poem.content), theme)
                                : _following
                                    ? _buildFollowBody(poem, theme)
                                    : _buildTappableBody(poem, theme),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildDivider(theme),
                        // 正文下方的操作提示：轻点查字 + 明确的沉浸入口。
                        // 沉浸入口摆在正文附近而不是顶栏 —— 画布把顶栏留给「返回/朗读/收藏」，
                        // 而这里离正文更近，反而更好找。
                        if (!_immersive && !_parallel) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '轻点正文里的字，可查读音与用例',
                                  style: ShiciText.caption.copyWith(
                                      fontSize: 11, color: theme.colorScheme.outline),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _immersive = true),
                                icon: const PoemIcon(PoemIcons.immersive, size: 16),
                                label: const Text('沉浸阅读',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
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
                        if (translation != null) ...[
                          const SizedBox(height: 24),
                          _buildCollapsibleSection(
                            theme,
                            '译 文',
                            PoemIcons.recite,
                            _showTranslation,
                            () => setState(
                                () => _showTranslation = !_showTranslation),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _display(translation,
                                      ContentField.translation),
                                  style: TextStyle(
                                      fontSize: _fontSize - 2,
                                      height: 1.8,
                                      color: _immersive
                                          ? Colors.white70
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.85)),
                                ),
                                if (!_immersive)
                                  _overrideRow(theme,
                                      ContentField.translation,
                                      poem.translation),
                              ],
                            ),
                            badge: _immersive
                                ? null
                                : _levelBadge(theme, ContentField.translation,
                                    poem.translation),
                          ),
                        ],
                        // 赏析
                        if (appreciation != null) ...[
                          const SizedBox(height: 24),
                          _buildCollapsibleSection(
                            theme,
                            '赏 析',
                            PoemIcons.star,
                            _showAppreciation,
                            () => setState(
                                () => _showAppreciation = !_showAppreciation),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _display(appreciation,
                                      ContentField.appreciation),
                                  style: TextStyle(
                                      fontSize: _fontSize - 2,
                                      height: 1.8,
                                      color: _immersive
                                          ? Colors.white70
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.85)),
                                ),
                                if (!_immersive)
                                  _overrideRow(theme,
                                      ContentField.appreciation,
                                      poem.appreciation),
                              ],
                            ),
                            badge: _immersive
                                ? null
                                : _levelBadge(theme, ContentField.appreciation,
                                    poem.appreciation),
                          ),
                        ],
                  ],
                      // 创作背景
                      if (background != null) ...[
                        const SizedBox(height: 24),
                        _buildCollapsibleSection(
                          theme,
                          '创作背景',
                          PoemIcons.dynasty,
                          _showBackground,
                          () => setState(
                              () => _showBackground = !_showBackground),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _display(background, ContentField.background),
                                style: TextStyle(
                                    fontSize: _fontSize - 2,
                                    height: 1.8,
                                    color: _immersive
                                        ? Colors.white70
                                        : theme.colorScheme.onSurface
                                            .withOpacity(0.85)),
                              ),
                              if (!_immersive)
                                _overrideRow(theme, ContentField.background,
                                    poem.background),
                            ],
                          ),
                          badge: _immersive
                              ? null
                              : _levelBadge(theme, ContentField.background,
                                  poem.background),
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
                  // TTS 控制条（整段朗读 / 逐句跟读共用）
                  if ((_ttsPlaying || _following) && !_immersive)
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
    final c = ShiciColors.of(context);
    // 沉浸模式是纯黑底（固定色块，不随模式变），白色前景恒成立
    final color = !_immersive
        ? theme.colorScheme.outline
        : Colors.white; // keep: fixed-block
    return Row(
      children: [
        Expanded(child: Divider(color: color.withOpacity(0.25), height: 1)),
        const SizedBox(width: 10),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _immersive ? Colors.white70 : c.cinnabar, // keep: fixed-block
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
    final c = ShiciColors.of(context);
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
                  ? c.cinnabar
                  : Colors.white.withOpacity(0.6), // keep: fixed-block
              width: 1.2,
            ),
          ),
          child: Text(
            '雅',
            style: ShiciText.calligraphy.copyWith(
              fontSize: 10,
              height: 1.0,
              color: isLight ? c.cinnabar : Colors.white, // keep: fixed-block
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
    final c = ShiciColors.of(context);
    return Text(
      title,
      style: ShiciText.caption.copyWith(
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
        color: _immersive ? Colors.white70 : c.cinnabar, // keep: fixed-block
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
        _immersive ? Colors.white : theme.colorScheme.onSurface; // keep: fixed-block
    final pinyinColor =
        _immersive ? Colors.white70 : theme.colorScheme.primary; // keep: fixed-block
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
      bool expanded, VoidCallback onToggle, Widget content,
      {Widget? badge}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              _sectionLabel(title),
              // 徽标放在标题行而不是正文里：折叠时也要看得见 ——
              // 「这一段不是专门写的赏析」这件事，用户有权在点开之前就知道
              if (badge != null) ...[const SizedBox(width: 8), badge],
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

  /// 内容可信度徽标：精校 / 说明性补充 / 我补写的。
  ///
  /// 颜色全部取自语义令牌，深色模式下会自动换成适合墨底的那一档。
  Widget _levelBadge(ThemeData theme, ContentField field, String? builtIn) {
    final c = ShiciColors.of(context);
    final own = _isOwnOverride(field);
    final level = _levelOf(field, builtIn);
    final color = switch (level) {
      // 「我的」与「精校」都是可信内容，同色；区分靠文案
      ContentLevel.curated => c.pine,
      ContentLevel.generated => c.ochre,
      ContentLevel.missing => c.inkSoft,
    };
    final label = own ? '我补写的' : ContentQuality.labelOf(level);

    return Tooltip(
      message: own
          ? '这段是你自己补写的，升级离线包不会覆盖它。'
          : ContentQuality.hintOf(level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(ShiciSize.rSm),
          border: Border.all(color: color.withOpacity(0.35), width: 0.5),
        ),
        child: Text(
          label,
          style: ShiciText.tag.copyWith(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 区块底部：一句来源说明 + 「我来写 / 修改」入口。
  Widget _overrideRow(ThemeData theme, ContentField field, String? builtIn) {
    final own = _isOwnOverride(field);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              own
                  ? '来自你的补写'
                  : ContentQuality.hintOf(
                      _levelOf(field, builtIn)),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: () => _editOverride(
                field, own ? _overrides[field.name] : builtIn),
            icon: Icon(own ? Icons.edit_outlined : Icons.add, size: 15),
            label: Text(own ? '修改' : '我来写',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  bool _isOwnOverride(ContentField field) =>
      _overrides[field.name]?.trim().isNotEmpty ?? false;

  /// 展示用文本：自己补写的内容原样显示（不做繁简转换，那是用户的字）
  String _display(String raw, ContentField field) =>
      _isOwnOverride(field) ? raw : _t(raw);

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
    final c = ShiciColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1), // keep: fixed-block
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 当前句：跟读时把它放大摆在眼前，比在正文里找一个高亮更省事，
          // 长词一屏放不下时也不用滚动去追
          if (_following && _verseIndex < _verses.length) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _t(_verses[_verseIndex]),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: 1.6,
                  fontFamily: _fontFamily,
                  color: c.cinnabar,
                ),
              ),
            ),
          ],
          Row(
            children: [
              PoemIcon(_following ? PoemIcons.recite : PoemIcons.tts,
                  color: c.cinnabar, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _following
                      ? '跟读 ${_verseIndex + 1}/${_verses.length}'
                          '${_loopVerse ? ' · 单句循环' : ''}'
                      : '正在朗读...',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (_following) ...[
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed:
                      _verseIndex == 0 ? null : () => _jumpVerse(-1),
                  tooltip: '上一句',
                ),
                IconButton(
                  icon: Icon(_loopVerse
                      ? Icons.repeat_on_outlined
                      : Icons.repeat),
                  color: _loopVerse ? c.cinnabar : null,
                  onPressed: () =>
                      setState(() => _loopVerse = !_loopVerse),
                  tooltip: _loopVerse ? '关闭单句循环' : '单句循环',
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _verseIndex >= _verses.length - 1
                      ? null
                      : () => _jumpVerse(1),
                  tooltip: '下一句',
                ),
              ],
              // 倍速选择
              PopupMenuButton<double>(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  // 跟读中调语速：把当前句重新开始，新语速立刻生效
                  if (_following) _startFollow(from: _verseIndex);
                },
                itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((r) => PopupMenuItem(value: r, child: Text('${r}x')))
                    .toList(),
              ),
              if (!_following)
                IconButton(
                  icon: Icon(_ttsPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _toggleTts,
                  tooltip: _ttsPlaying ? '暂停朗读' : '开始朗读',
                ),
              IconButton(
                icon: const Icon(Icons.stop),
                onPressed: _following ? _stopFollow : _stopTts,
                tooltip: _following ? '结束跟读' : '停止朗读',
              ),
            ],
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
      // 整段朗读与逐句跟读互斥：不先停跟读，两段声音会叠在一起
      if (_following) setState(() => _following = false);
      await _tts.setRate(_ttsRate);
      await _tts.speak('${_poem!.title}。${_poem!.content}');
      setState(() => _ttsPlaying = true);
    }
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() {
      _ttsPlaying = false;
      _following = false;
    });
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
                    color: alreadyIn
                        ? ShiciColors.of(ctx).pine
                        : ShiciColors.of(ctx).indigo,
                  ),
                  title: Text(p.name),
                  subtitle: Text(alreadyIn ? '已在计划中' : '${p.poemIds.length} 首'),
                  onTap: () => Navigator.pop(ctx, p.id),
                );
              }),
            ListTile(
              leading: Icon(Icons.add, color: ShiciColors.of(ctx).cinnabar),
              title: Text('新建学习计划',
                  style: TextStyle(color: ShiciColors.of(ctx).cinnabar)),
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
    final c = ShiciColors.of(context);
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline, size: 13, color: c.cinnabar),
                    const SizedBox(width: 2),
                    Text('删除',
                        style: TextStyle(fontSize: 11, color: c.cinnabar)),
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
    for (final recognizer in _charRecognizers.values) {
      recognizer.dispose();
    }
    _charRecognizers.clear();
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
