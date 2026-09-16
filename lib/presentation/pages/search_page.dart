import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/empty_state.dart';
import '../widgets/poem_icon.dart';
import '../widgets/poem_card_styles.dart';
import '../widgets/shici_kit.dart';
import 'poem_detail_page.dart';

/// 全文搜索页：标题/内容/作者搜索，历史记录，结果高亮
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Poem> _results = [];
  List<VerseHit> _verseHits = const <VerseHit>[];
  List<String> _history = [];
  bool _searching = false;
  bool _hasSearched = false;

  // debounce 实时搜索
  Timer? _debounce;

  // 高级筛选
  List<Dynasty> _dynasties = [];
  int? _selectedDynastyId; // null = 不限朝代
  String? _selectedType; // null = 不限体裁
  /// 体裁选项 —— 与诗词库同源，从库里实际出现过的 `poems.type` 取值生成。
  ///
  /// 早先这里写死过一份，含「乐府」「散文」两个库里根本没有的选项，
  /// 选了只会搜出 0 条；现在随数据走，次序由 [sortPoemTypes] 固定。
  List<String> _types = const <String>[];

  // 热门搜索词
  final _hotWords = ['李白', '苏轼', '静夜思', '春', '月', '乡', '边塞', '豪放', '婉约'];

  /// 当前卡片样式 —— 与诗词库 / 收藏夹共享同一份偏好
  PoemCardStyle _cardStyle = PoemCardStyleStore.fallback;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadFilters();
    _loadStyle();
  }

  /// 恢复上次选择的卡片样式
  Future<void> _loadStyle() async {
    final style = await PoemCardStyleStore.load();
    if (mounted) setState(() => _cardStyle = style);
  }

  Future<void> _loadFilters() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      DatabaseHelper.getAllDynasties(),
      DatabaseHelper.getPoemTypes(),
    ]);
    if (mounted) {
      setState(() {
        _dynasties = results[0] as List<Dynasty>;
        _types = sortPoemTypes(results[1] as List<String>);
      });
    }
  }

  /// debounce 触发实时搜索（输入即搜，300ms 防抖）
  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doSearch(value);
    });
  }

  /// 筛选项变化时，若已有关键词则重新搜索
  void _onFilterChanged() {
    if (_controller.text.trim().isNotEmpty) {
      _doSearch(_controller.text);
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _saveHistory(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    history.remove(keyword);
    history.insert(0, keyword);
    if (history.length > 10) {
      history.removeLast();
    }
    await prefs.setStringList('search_history', history);
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    setState(() => _history = []);
  }

  Future<void> _doSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _hasSearched = true;
    });
    final kw = keyword.trim();
    final results = await DatabaseHelper.searchPoems(
      kw,
      dynastyId: _selectedDynastyId,
      type: _selectedType,
    );
    // 诗句命中：单独一条一条地看「这个字落在哪句」，是「按字查诗」的核心姿态。
    // 只在输入足够短（1~4 字）时查 —— 输入一整句时诗词结果已经够准，
    // 再叠一份诗句列表只是噪音。
    final wantVerses = kw.runes.length <= 4 && !kw.contains(RegExp(r'\s'));
    final verses =
        wantVerses ? await DatabaseHelper.searchVerses(kw, limit: 20) : <VerseHit>[];
    if (mounted) {
      setState(() {
        _results = results;
        _verseHits = verses;
        _searching = false;
      });
    }
  }

  /// 回车提交搜索：保存历史 + 搜索
  void _submitSearch(String keyword) {
    if (keyword.trim().isNotEmpty) {
      _saveHistory(keyword.trim());
    }
    _debounce?.cancel();
    _doSearch(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: ShiciSize.pagePadding,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: '搜诗词、作者，或拼音 cqmyg',
            isDense: true,
            prefixIcon: const PoemIcon(PoemIcons.search, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 20),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: theme.colorScheme.outline),
                    onPressed: () {
                      _controller.clear();
                      _debounce?.cancel();
                      setState(() {
                        _results = [];
                        _hasSearched = false;
                      });
                    },
                  )
                : null,
          ),
          onSubmitted: _submitSearch,
          onChanged: _onChanged,
        ),
        // 画布上搜索框右侧有「取消」
        actions: <Widget>[
          // 卡片样式入口放在顶栏：它是「怎么看结果」的偏好，不该只在
          // 出结果之后才出现（早先挂在筛选栏里），也不该混进「筛什么」的条件栏。
          IconButton(
            tooltip: '卡片样式：${_cardStyle.label}',
            icon: PoemIcon(PoemIcons.sort,
                size: 20, color: ShiciColors.of(context).inkSoft),
            onPressed: _showCardStyleSheet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          TextButton(
            onPressed: () {
              _controller.clear();
              _debounce?.cancel();
              _focusNode.unfocus();
              setState(() {
                _results = [];
                _hasSearched = false;
              });
            },
            child: Text('取消',
                style: ShiciText.caption
                    .copyWith(color: ShiciColors.of(context).inkSoft)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_hasSearched) _buildFilterBar(theme),
          Expanded(child: _hasSearched ? _buildResults() : _buildSuggestions(theme)),
        ],
      ),
    );
  }

  /// 高级筛选栏：朝代 + 体裁
  Widget _buildFilterBar(ThemeData theme) {
    final hasFilter = _selectedDynastyId != null || _selectedType != null;
    String dynastyName() {
      if (_selectedDynastyId == null) return '全部';
      for (final d in _dynasties) {
        if (d.id == _selectedDynastyId) return d.name;
      }
      return '全部';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.3))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            PopupMenuButton<int>(
              child: _filterLabel('朝代：${dynastyName()}', _selectedDynastyId != null, theme),
              onSelected: (id) {
                setState(() => _selectedDynastyId = id == -1 ? null : id);
                _onFilterChanged();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: -1, child: Text('全部')),
                ..._dynasties.map((d) => PopupMenuItem(value: d.id, child: Text(d.name))),
              ],
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              child: _filterLabel('体裁：${_selectedType ?? '全部'}', _selectedType != null, theme),
              onSelected: (t) {
                setState(() => _selectedType = t.isEmpty ? null : t);
                _onFilterChanged();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('全部')),
                ..._types.map((t) => PopupMenuItem(value: t, child: Text(t))),
              ],
            ),
            if (hasFilter) ...[
              const SizedBox(width: 8),
              ActionChip(
                label: const Text('清除', style: TextStyle(fontSize: 12)),
                avatar: const Icon(Icons.close, size: 14),
                onPressed: () {
                  setState(() {
                    _selectedDynastyId = null;
                    _selectedType = null;
                  });
                  _onFilterChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 卡片样式切换
  Future<void> _showCardStyleSheet() async {
    final picked = await showPoemCardStylePicker(context, current: _cardStyle);
    if (picked == null || picked == _cardStyle) return;
    setState(() => _cardStyle = picked);
    await PoemCardStyleStore.save(picked);
  }

  Widget _filterLabel(String text, bool active, ThemeData theme) {
    final c = ShiciColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? c.cinnabar.withOpacity(0.10) : c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
        border: Border.all(
            color: active ? c.cinnabar.withOpacity(0.4) : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              style: ShiciText.caption
                  .copyWith(color: active ? c.cinnabar : c.ink)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down,
              size: 16, color: active ? c.cinnabar : c.inkFaint),
        ],
      ),
    );
  }

  /// 建议区：热门搜索在前、最近搜索在后（对齐画布顺序）
  Widget _buildSuggestions(ThemeData theme) {
    final c = ShiciColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          ShiciSize.pagePadding, 8, ShiciSize.pagePadding, 24),
      children: <Widget>[
        Text('热门搜索', style: ShiciText.caption.copyWith(color: c.inkSoft)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotWords
              .map((w) => _buildSuggestionChip(w, theme, false))
              .toList(),
        ),
        if (_history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Text('最近搜索',
                  style: ShiciText.caption.copyWith(color: c.inkSoft)),
              const Spacer(),
              GestureDetector(
                onTap: _clearHistory,
                child: Text('清空',
                    style: ShiciText.caption.copyWith(color: c.cinnabar)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._history.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _historyRow(c, h),
              )),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.sand,
            borderRadius: BorderRadius.circular(ShiciSize.rSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.keyboard_alt_outlined, size: 18, color: c.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '想不起字怎么写？直接打拼音：全拼「chuangqian」或首字母「cqmyg」都能搜到《静夜思》。',
                  style:
                      ShiciText.caption.copyWith(height: 1.6, color: c.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 历史行：定高 40 的绢白行（画布上的「历史行」）
  Widget _historyRow(ShiciColors c, String keyword) {
    return ShiciCard(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      onTap: () {
        _controller.text = keyword;
        _submitSearch(keyword);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(keyword,
              style: ShiciText.caption.copyWith(fontSize: 13, color: c.ink)),
          PoemIcon(PoemIcons.duration, size: 13, color: c.inkFaint),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label, ThemeData theme, bool isHistory) {
    return ShiciPill(
      label: label,
      poemIcon: isHistory ? PoemIcons.duration : null,
      onTap: () {
        _controller.text = label;
        _submitSearch(label);
      },
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty && _verseHits.isEmpty) {
      return const EmptyState(
        icon: PoemIcons.search,
        title: '未找到相关诗词',
        description: '试试「李白」「月」，或拼音「cqmyg」',
      );
    }
    final c = ShiciColors.of(context);
    final verseCount = _verseHits.length;
    // 诗句区占 verseCount 个条目 + 1 个标题
    final offset = verseCount == 0 ? 0 : verseCount + 1;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
              ShiciSize.pagePadding, 10, ShiciSize.pagePadding, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _results.isEmpty
                  ? '没有整首匹配的诗，下面是含「${_controller.text.trim()}」的诗句'
                  : '找到 ${_results.length} 首诗词'
                      '${verseCount > 0 ? ' · $verseCount 处诗句' : ''}',
              style: ShiciText.caption.copyWith(color: c.inkSoft),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: offset + _results.length,
            itemBuilder: (context, index) {
              if (verseCount > 0) {
                if (index == 0) return _verseSectionHeader(c, verseCount);
                if (index <= verseCount) {
                  return _verseTile(c, _verseHits[index - 1]);
                }
              }
              final poem = _results[index - offset];
              final keyword = _controller.text.trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PoemListCard(
                  poem: poem,
                  style: _cardStyle,
                  // 命中高亮与上下文片段由卡片承载：
                  // 片段优先展示含关键词的那一句，直接回答「为什么搜到它」
                  keyword: keyword,
                  snippet: poemSnippet(poem, keyword),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PoemDetailPage(poemId: poem.id)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 诗句区标题：说明这一段的身份，并把「共几处」交代清楚
  Widget _verseSectionHeader(ShiciColors c, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: <Widget>[
          PoemIcon(PoemIcons.recite, size: 16, color: c.cinnabar),
          const SizedBox(width: 8),
          Text('含「${_controller.text.trim()}」的诗句',
              style: ShiciText.heading.copyWith(fontSize: 13, color: c.ink)),
          const SizedBox(width: 6),
          Text('$count 处',
              style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkFaint)),
        ],
      ),
    );
  }

  /// 一条诗句命中：诗句本身（命中词标朱砂）+ 出处
  Widget _verseTile(ShiciColors c, VerseHit hit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => PoemDetailPage(poemId: hit.poemId)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.silk,
            borderRadius: BorderRadius.circular(ShiciSize.rMd),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _highlighted(
                hit.verse,
                _controller.text.trim(),
                ShiciText.body.copyWith(
                  fontSize: 15,
                  height: 1.7,
                  color: c.ink,
                ),
                c,
              ),
              const SizedBox(height: 4),
              Text(
                '——《${hit.title}》'
                '${(hit.authorName ?? '').isEmpty ? '' : ' · ${hit.authorName}'}',
                style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 命中词标朱砂。与卡片里的高亮同一套语义：只有颜色，不加底色，
  /// 免得一屏几十条全都花掉。
  Widget _highlighted(
      String text, String keyword, TextStyle style, ShiciColors c) {
    if (keyword.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    final kw = keyword.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (true) {
      final at = lower.indexOf(kw, cursor);
      if (at < 0) break;
      if (at > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, at)));
      }
      spans.add(TextSpan(
        text: text.substring(at, at + kw.length),
        style: TextStyle(color: c.cinnabar, fontWeight: FontWeight.w600),
      ));
      cursor = at + kw.length;
    }
    if (spans.isEmpty) return Text(text, style: style);
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
