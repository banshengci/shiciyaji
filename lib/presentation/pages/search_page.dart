import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/empty_state.dart';
import '../widgets/poem_icon.dart';
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
  List<String> _history = [];
  bool _searching = false;
  bool _hasSearched = false;

  // debounce 实时搜索
  Timer? _debounce;

  // 高级筛选
  List<Dynasty> _dynasties = [];
  int? _selectedDynastyId; // null = 不限朝代
  String? _selectedType; // null = 不限体裁
  final _types = ['五言绝句', '七言绝句', '五言律诗', '七言律诗', '词', '曲', '乐府', '散文'];

  // 热门搜索词
  final _hotWords = ['李白', '苏轼', '静夜思', '春', '月', '乡', '边塞', '豪放', '婉约'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadDynasties();
  }

  Future<void> _loadDynasties() async {
    final dynasties = await DatabaseHelper.getAllDynasties();
    if (mounted) {
      setState(() => _dynasties = dynasties);
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
    final results = await DatabaseHelper.searchPoems(
      keyword.trim(),
      dynastyId: _selectedDynastyId,
      type: _selectedType,
    );
    if (mounted) {
      setState(() {
        _results = results;
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
          Expanded(child: _hasSearched ? _buildResults(theme) : _buildSuggestions(theme)),
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

  Widget _buildResults(ThemeData theme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: PoemIcons.search,
        title: '未找到相关诗词',
        description: '试试「李白」「月」，或拼音「cqmyg」',
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
              ShiciSize.pagePadding, 10, ShiciSize.pagePadding, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('找到 ${_results.length} 首诗词',
                style: ShiciText.caption.copyWith(
                    color: ShiciColors.of(context).inkSoft)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final poem = _results[index];
              final keyword = _controller.text;
              final c = ShiciColors.of(context);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ShiciCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PoemDetailPage(poemId: poem.id)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题（高亮）
                      _highlightText(poem.title, keyword, theme, isTitle: true),
                      const SizedBox(height: 4),
                      Text(
                        '${poem.dynastyName ?? ''} · ${poem.authorName ?? '佚名'}',
                        style: ShiciText.caption.copyWith(color: c.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      // 内容片段（高亮）
                      _highlightText(
                        poem.content.split('\n').take(2).join('\n'),
                        keyword,
                        theme,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _highlightText(String text, String keyword, ThemeData theme, {bool isTitle = false, int maxLines = 1}) {
    if (keyword.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: isTitle ? 16 : 13,
          fontWeight: isTitle ? FontWeight.w600 : FontWeight.normal,
          color: isTitle ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.5),
          fontFamily: 'serif',
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerKeyword, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + keyword.length),
        style: TextStyle(
          color: AppTheme.zhuShaHong,
          backgroundColor: AppTheme.zhuShaHong.withOpacity( 0.1),
        ),
      ));
      start = index + keyword.length;
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: isTitle ? 16 : 13,
          fontWeight: isTitle ? FontWeight.w600 : FontWeight.normal,
          color: isTitle ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.5),
          fontFamily: 'serif',
          height: 1.6,
        ),
        children: spans,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
