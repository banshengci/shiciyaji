import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/empty_state.dart';
import '../widgets/poem_card_styles.dart';
import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import 'authors_page.dart';
import 'poem_detail_page.dart';

/// 诗词库 —— 版面对齐设计稿画布节点 `3:626`（S5 界面-诗词库）。
///
/// 顶栏（标题 + 搜索/筛选）→ 分段控件（全部 / 唐诗 / 宋词 / 小学必背）
/// → 定高 62 的诗行列表（诗名 15 Medium + 作者·朝代 11）。
///
/// 分段控件与筛选面板写入**同一组状态**，所以分段高亮永远反映真实筛选条件，
/// 不会出现「点了唐诗、又改朝代，分段还亮着唐诗」这种假状态。
class LibraryPage extends StatefulWidget {
  /// 切到底部导航的搜索 tab
  final ValueChanged<int>? onNavigate;

  const LibraryPage({super.key, this.onNavigate});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Dynasty> _dynasties = [];
  List<Category> _categories = [];
  List<Poem> _poems = [];
  int? _selectedDynastyId;
  int? _selectedCategoryId;
  String _selectedType = '全部';
  bool _loading = true;
  bool _isGridView = false;

  /// 当前卡片样式 —— 02 朝代色带 / 03 题材标签 / 07 紧凑列表
  /// 默认取 07 紧凑列表：单行 62 高，诗词库这种长列表最划算
  PoemCardStyle _cardStyle = PoemCardStyleStore.fallback;

  /// 卡片附加数据：题材标签映射与收藏态，与列表一同刷新
  Map<int, List<String>> _poemTags = const <int, List<String>>{};
  Set<int> _favoriteIds = const <int>{};

  /// 分段控件对应的固定条件（从数据里按名字查出来，不写死 ID）
  int? _tangDynastyId;
  int? _songDynastyId;
  int? _bibeiCategoryId;

  /// 体裁选项 —— 从库里实际出现过的 `poems.type` 取值生成。
  ///
  /// 早先这里写死过一份（含「乐府」「散文」这类库里根本没有的选项），
  /// 点了筛不出东西；现在改为随数据走，次序由 [sortPoemTypes] 固定。
  List<String> _types = const <String>[];

  static const _segments = <String>['全部', '唐诗', '宋词', '小学必背'];

  @override
  void initState() {
    super.initState();
    _loadCardStyle();
    _loadFilters();
  }

  /// 恢复上次选择的卡片样式（与收藏夹 / 搜索页共享同一份偏好）
  Future<void> _loadCardStyle() async {
    final style = await PoemCardStyleStore.load();
    if (mounted) setState(() => _cardStyle = style);
  }

  Future<void> _loadFilters() async {
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        DatabaseHelper.getAllDynasties(),
        DatabaseHelper.getAllCategories(),
        DatabaseHelper.getPoemTypes(),
      ]);
      final dynasties = results[0] as List<Dynasty>;
      final categories = results[1] as List<Category>;
      final types = sortPoemTypes(results[2] as List<String>);
      if (mounted) {
        setState(() {
          _dynasties = dynasties;
          _categories = categories;
          _types = types;
          _tangDynastyId = _dynastyIdByName(dynasties, '唐');
          _songDynastyId = _dynastyIdByName(dynasties, '宋');
          _bibeiCategoryId = _categoryIdByName(categories, '必背');
        });
        _loadPoems();
      }
    } catch (e, st) {
      debugPrint('加载筛选数据失败: $e\n$st');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('数据加载失败: $e'),
              duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  static int? _dynastyIdByName(List<Dynasty> list, String name) {
    for (final d in list) {
      if (d.name == name) return d.id;
    }
    return null;
  }

  static int? _categoryIdByName(List<Category> list, String name) {
    for (final c in list) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  /// 由当前筛选条件反推分段下标 —— 单一数据源，不另存一份分段状态。
  ///
  /// 返回 **-1 表示「没有哪个分段对应当前条件」**（例如点了卡片上的
  /// 「七言绝句」标签）。早先这里在体裁筛选生效时返回 0，
  /// 于是「全部」会亮着 —— 一个明确在筛选的状态却显示成未筛选，是假状态。
  int get _segmentIndex {
    if (_selectedDynastyId != null &&
        _selectedDynastyId == _tangDynastyId &&
        _selectedCategoryId == null &&
        _selectedType == '全部') {
      return 1;
    }
    if (_selectedDynastyId != null &&
        _selectedDynastyId == _songDynastyId &&
        _selectedCategoryId == null &&
        _selectedType == '全部') {
      return 2;
    }
    if (_selectedCategoryId != null &&
        _selectedCategoryId == _bibeiCategoryId &&
        _selectedDynastyId == null &&
        _selectedType == '全部') {
      return 3;
    }
    if (_selectedDynastyId == null &&
        _selectedCategoryId == null &&
        _selectedType == '全部') {
      return 0;
    }
    // 其余组合（含卡片标签点出来的筛选）不属于任何分段
    return -1;
  }

  /// 当前生效的筛选标签文本集合 —— 卡片上命中它们的标签会亮起。
  ///
  /// 题材与体裁可能同时生效，所以是集合而不是单值。
  Set<String> get _activeTags {
    final out = <String>{};
    if (_selectedCategoryId != null) {
      for (final c in _categories) {
        if (c.id == _selectedCategoryId) out.add(c.name);
      }
    }
    if (_selectedType != '全部') out.add(_selectedType);
    return out;
  }

  /// 卡片标签被点击：题材走题材筛、体裁走体裁筛，再点一次取消。
  ///
  /// 靠名字分流是安全的 —— 离线包里 categories.name 与 poems.type
  /// 没有重名（已用数据校验过），所以文本能无歧义地映射到唯一条件。
  void _onTagTap(String tag) {
    final categoryId = _categoryIdByName(_categories, tag);
    setState(() {
      if (categoryId != null) {
        _selectedCategoryId =
            _selectedCategoryId == categoryId ? null : categoryId;
      } else {
        _selectedType = _selectedType == tag ? '全部' : tag;
      }
    });
    _loadPoems();
  }

  /// 移除单个生效条件 —— 筛选条上每个胶囊右侧的 ×
  void _clearFilter({bool dynasty = false, bool type = false, bool category = false}) {
    setState(() {
      if (dynasty) _selectedDynastyId = null;
      if (type) _selectedType = '全部';
      if (category) _selectedCategoryId = null;
    });
    _loadPoems();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedDynastyId = null;
      _selectedCategoryId = null;
      _selectedType = '全部';
    });
    _loadPoems();
  }

  void _selectSegment(int index) {
    setState(() {
      _selectedDynastyId = null;
      _selectedCategoryId = null;
      _selectedType = '全部';
      switch (index) {
        case 1:
          _selectedDynastyId = _tangDynastyId;
          break;
        case 2:
          _selectedDynastyId = _songDynastyId;
          break;
        case 3:
          _selectedCategoryId = _bibeiCategoryId;
          break;
      }
    });
    _loadPoems();
  }

  Future<void> _loadPoems() async {
    setState(() => _loading = true);
    try {
      // 三个数据源并行取：让卡片标签与收藏态不拖慢列表首屏
      final results = await Future.wait<Object>(<Future<Object>>[
        DatabaseHelper.getAllPoems(
          dynastyId: _selectedDynastyId,
          categoryId: _selectedCategoryId,
          type: _selectedType == '全部' ? null : _selectedType,
        ),
        DatabaseHelper.getPoemCategoryMap(),
        DatabaseHelper.getFavoritePoemIds(),
      ]);
      final poems = results[0] as List<Poem>;
      if (mounted) {
        setState(() {
          _poems = poems;
          _poemTags = results[1] as Map<int, List<String>>;
          _favoriteIds = results[2] as Set<int>;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('加载诗词失败: $e\n$st');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('诗词加载失败: $e'),
              duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: ShiciSize.pagePadding,
        toolbarHeight: 56,
        title: Text(
          '诗词库',
          style: ShiciText.title.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '搜索',
            icon: PoemIcon(PoemIcons.search, size: 22, color: c.ink),
            onPressed: () => widget.onNavigate?.call(2),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          IconButton(
            tooltip: '筛选',
            icon: PoemIcon(PoemIcons.filter, size: 22, color: c.ink),
            onPressed: () => _showFilterSheet(c),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: ShiciSize.pagePadding - 8),
        ],
      ),
      body: isWide
          ? Row(
              children: <Widget>[
                SizedBox(width: 260, child: _buildFilterPanel()),
                Container(width: 1, color: c.line),
                Expanded(child: _buildPoemList()),
              ],
            )
          : Column(
              children: <Widget>[
                _buildSegments(),
                _buildActiveFilterBar(),
                Expanded(
                  child: _isGridView ? _buildPoemGrid() : _buildPoemList(),
                ),
              ],
            ),
    );
  }

  // ── 分段控件：全部 / 唐诗 / 宋词 / 小学必背 ────────────────────────
  //
  // 右侧挂「卡片样式」入口：分段管「看什么」，样式管「怎么看」，
  // 两件事同处一行，筛选时视线不用来回跳。
  Widget _buildSegments() {
    final c = ShiciColors.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                  left: ShiciSize.pagePadding, right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < _segments.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 8),
                    ShiciPill(
                      label: _segments[i],
                      selected: _segmentIndex == i,
                      onTap: () => _selectSegment(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '卡片样式：${_cardStyle.label}',
            icon: PoemIcon(PoemIcons.sort, size: 20, color: c.inkSoft),
            onPressed: _showCardStyleSheet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: ShiciSize.pagePadding - 8),
        ],
      ),
    );
  }

  // ── 生效中筛选条 ─────────────────────────────────────────────────
  //
  // 分段控件只能表达 4 种「预设」，卡片标签点出来的题材 / 体裁组合不在其中。
  // 没有这条的时候，用户点了一枚标签，界面上找不到任何「现在筛了什么」的
  // 提示，也去不掉 —— 所以筛选条不只是一条状态显示，它是这些筛选的出口。
  Widget _buildActiveFilterBar() {
    final c = ShiciColors.of(context);
    final chips = <Widget>[];

    if (_selectedDynastyId != null) {
      for (final d in _dynasties) {
        if (d.id == _selectedDynastyId) {
          chips.add(_activeChip(
              '朝代 · ${d.name}', () => _clearFilter(dynasty: true)));
        }
      }
    }
    if (_selectedType != '全部') {
      chips.add(_activeChip(
          '体裁 · $_selectedType', () => _clearFilter(type: true)));
    }
    if (_selectedCategoryId != null) {
      for (final cat in _categories) {
        if (cat.id == _selectedCategoryId) {
          chips.add(_activeChip(
              '${cat.type} · ${cat.name}', () => _clearFilter(category: true)));
        }
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ShiciSize.pagePadding, 0, ShiciSize.pagePadding, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            PoemIcon(PoemIcons.filter, size: 13, color: c.inkSoft),
            const SizedBox(width: 6),
            ...chips.expand((w) => <Widget>[w, const SizedBox(width: 8)]),
            if (chips.length > 1)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearAllFilters,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '清除全部',
                    style: ShiciText.caption.copyWith(color: c.cinnabar),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onRemove) {
    final c = ShiciColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRemove,
      child: Semantics(
        button: true,
        label: '移除筛选 $label',
        child: Container(
          height: 24,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(
            color: c.indigo.withOpacity(0.08),
            borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
            border: Border.all(color: c.indigo.withOpacity(0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: ShiciText.tag.copyWith(fontSize: 11, color: c.indigo),
              ),
              const SizedBox(width: 3),
              Icon(Icons.close, size: 12, color: c.indigo),
            ],
          ),
        ),
      ),
    );
  }

  // ── 列表：定高 62 / 内衬 18 / 间距 10 ─────────────────────────────
  Widget _buildPoemList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_poems.isEmpty) {
      return const EmptyState(
        icon: PoemIcons.search,
        title: '暂无符合条件的诗词',
        description: '换个筛选条件，或到「诗库商店」安装更多诗集',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          ShiciSize.pagePadding, 12, ShiciSize.pagePadding, 20),
      itemCount: _poems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final poem = _poems[index];
        return PoemListCard(
          poem: poem,
          index: index + 1,
          style: _cardStyle,
          tags: poemTagsFor(poem, _poemTags),
          favorite: _favoriteIds.contains(poem.id),
          // 标签可点：题材筛题材、体裁筛体裁，生效中的会亮起
          onTagTap: _onTagTap,
          activeTags: _activeTags,
          onTap: () => _navigateToDetail(poem.id),
        );
      },
    );
  }

  Widget _buildPoemGrid() {
    final c = ShiciColors.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_poems.isEmpty) {
      return const EmptyState(
        icon: PoemIcons.search,
        title: '暂无符合条件的诗词',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
          ShiciSize.pagePadding, 12, ShiciSize.pagePadding, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _poems.length,
      itemBuilder: (context, index) {
        final poem = _poems[index];
        return ShiciCard(
          padding: const EdgeInsets.all(14),
          onTap: () => _navigateToDetail(poem.id),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Center(
                  child: Text(
                    poem.title,
                    textAlign: TextAlign.center,
                    style:
                        ShiciText.heading.copyWith(fontSize: 16, color: c.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 18, height: 2, color: c.cinnabar),
              const SizedBox(height: 8),
              Text(
                '${poem.authorName ?? '佚名'} · ${poem.dynastyName ?? ''}',
                style: ShiciText.tag.copyWith(color: c.inkSoft, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 宽屏侧栏（沿用同一套筛选逻辑） ───────────────────────────────
  Widget _buildFilterPanel() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _buildCategorySections((id) {
        setState(() => _selectedCategoryId = id);
        _loadPoems();
      }),
    );
  }

  Widget _buildSheetFilterPanel(void Function(void Function()) setSheetState) {
    void selectDynasty(int? id) => setSheetState(() => _selectedDynastyId = id);
    void selectType(String t) => setSheetState(() => _selectedType = t);
    void selectCategory(int? id) =>
        setSheetState(() => _selectedCategoryId = id);

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _sheetHeader('朝代'),
        _wrapChips(<Widget>[
          _filterChip(
              '全部', _selectedDynastyId == null, () => selectDynasty(null)),
          ..._dynasties.map((d) => _filterChip(d.name,
              _selectedDynastyId == d.id, () => selectDynasty(d.id))),
        ]),
        const SizedBox(height: 20),
        _sheetHeader('体裁'),
        _wrapChips(_types
            .map((t) => _filterChip(t, _selectedType == t, () => selectType(t)))
            .toList()),
        ..._buildCategorySections(selectCategory),
      ],
    );
  }

  Widget _sheetHeader(String text) {
    final c = ShiciColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: c.cinnabar,
              borderRadius: BorderRadius.circular(ShiciSize.rSeal / 2),
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: ShiciText.heading.copyWith(color: c.ink)),
        ],
      ),
    );
  }

  Widget _wrapChips(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);

  Widget _filterChip(String label, bool selected, VoidCallback onTap) =>
      ShiciPill(label: label, selected: selected, onTap: onTap);

  /// 按 categories 表的 type 字段动态生成分组筛选区
  ///
  /// 好处：以后往 poems.json 里加新 type 无需改代码。
  List<Widget> _buildCategorySections(ValueChanged<int?> onSelect) {
    final groups = <String, List<Category>>{};
    for (final c in _categories) {
      groups.putIfAbsent(c.type, () => <Category>[]).add(c);
    }
    final sections = <Widget>[];
    for (final entry in groups.entries) {
      sections.add(const SizedBox(height: 20));
      sections.add(_sheetHeader(entry.key));
      sections.add(_wrapChips(<Widget>[
        _filterChip('全部', _selectedCategoryId == null, () => onSelect(null)),
        ...entry.value.map((c) => _filterChip(
            c.name, _selectedCategoryId == c.id, () => onSelect(c.id))),
      ]));
    }
    return sections;
  }

  void _showFilterSheet(ShiciColors c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.silk,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ShiciSize.rLg)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final activeFilters = _activeFilterLabels();
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.78),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Text('筛选条件',
                          style: ShiciText.title.copyWith(color: c.ink)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            _selectedDynastyId = null;
                            _selectedCategoryId = null;
                            _selectedType = '全部';
                          });
                        },
                        child: Text('重置',
                            style:
                                ShiciText.caption.copyWith(color: c.cinnabar)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close, color: c.inkSoft, size: 20),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                  if (activeFilters.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.sand,
                        borderRadius: BorderRadius.circular(ShiciSize.rSm),
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          PoemIcon(PoemIcons.filter, size: 14, color: c.inkSoft),
                          Text('已选',
                              style: ShiciText.caption.copyWith(
                                  color: c.inkSoft,
                                  fontWeight: FontWeight.w600)),
                          ...activeFilters.map((f) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.indigo,
                                  borderRadius: BorderRadius.circular(
                                      ShiciSize.rCapsule),
                                ),
                                child: Text(f,
                                    style: ShiciText.tag
                                        .copyWith(color: c.onAccent)),
                              )),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Flexible(child: _buildSheetFilterPanel(setSheetState)),
                  const SizedBox(height: 14),
                  // 画布顶栏只留「搜索 / 筛选」两个图标，于是把原本的
                  // 「诗人入口」与「列表·网格切换」收纳到这里 —— 功能不丢、顶栏不挤
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ShiciPill(
                          label: '按诗人浏览',
                          poemIcon: PoemIcons.poet,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const AuthorsPage()));
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ShiciPill(
                          label: _isGridView ? '网格视图' : '列表视图',
                          poemIcon: PoemIcons.sort,
                          onTap: () {
                            setState(() => _isGridView = !_isGridView);
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {});
                        _loadPoems();
                      },
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<String> _activeFilterLabels() {
    final out = <String>[];
    if (_selectedDynastyId != null) {
      for (final d in _dynasties) {
        if (d.id == _selectedDynastyId) out.add('朝代:${d.name}');
      }
    }
    if (_selectedType != '全部') out.add('体裁:$_selectedType');
    if (_selectedCategoryId != null) {
      for (final c in _categories) {
        if (c.id == _selectedCategoryId) out.add('${c.type}:${c.name}');
      }
    }
    return out;
  }

  void _navigateToDetail(int poemId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poemId)),
    );
  }

  /// 卡片样式切换：选择面板与落库都走公共实现，三个列表页行为一致
  Future<void> _showCardStyleSheet() async {
    final picked = await showPoemCardStylePicker(context, current: _cardStyle);
    if (picked == null || picked == _cardStyle) return;
    setState(() => _cardStyle = picked);
    await PoemCardStyleStore.save(picked);
  }
}
