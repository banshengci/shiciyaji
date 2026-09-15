import 'package:flutter/material.dart';

import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import '../widgets/empty_state.dart';
import '../widgets/poem_card_styles.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import 'poem_detail_page.dart';
import 'library_page.dart';

/// 我的收藏：分段（全部 / 唐诗 / 宋词）+ 收藏列表
///
/// 版面严格对齐设计稿画布节点 `3:1856`：顶栏 56（标题 + 收藏夹入口）、
/// 分段 44、列表行定高 58 / 圆角 14 / 内衬 16（左诗名 15、右「朝代 · 作者」11）。
/// 画布是「分段 + 列表」两层，原先的三层（TabBar + 收藏夹 chip + 列表）按此收敛，
/// 学习计划另立独立页（入口在「我的」），收藏夹改由顶栏图标进入。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Poem> _favorites = <Poem>[];
  List<Map<String, dynamic>> _collections = <Map<String, dynamic>>[];
  String? _selectedCollection; // null = 全部收藏
  int _segment = 0; // 0 全部 / 1 唐诗 / 2 宋词
  bool _loading = true;

  /// 当前卡片样式 —— 与诗词库 / 搜索页共享同一份偏好
  PoemCardStyle _cardStyle = PoemCardStyleStore.fallback;

  /// 题材标签映射，供 03 题材标签卡使用
  Map<int, List<String>> _poemTags = const <int, List<String>>{};

  static const List<String> _segments = <String>['全部', '唐诗', '宋词'];

  @override
  void initState() {
    super.initState();
    _loadStyle();
    _loadData();
  }

  /// 恢复上次选择的卡片样式（样式是跨页偏好，不随页面重置）
  Future<void> _loadStyle() async {
    final style = await PoemCardStyleStore.load();
    if (mounted) setState(() => _cardStyle = style);
  }

  Future<void> _loadData() async {
    final collections = await DatabaseHelper.getCollections();
    final favs = _selectedCollection == null
        ? await DatabaseHelper.getFavoritePoems()
        : await DatabaseHelper.getFavoritePoemsByCollection(_selectedCollection!);
    final tags = await DatabaseHelper.getPoemCategoryMap();
    if (mounted) {
      setState(() {
        _collections = collections;
        _favorites = favs;
        _poemTags = tags;
        _loading = false;
      });
    }
  }

  /// 当前可见列表：收藏夹已在 SQL 层过滤，朝代在前端筛（收藏量级小）
  List<Poem> get _visible {
    if (_segment == 0) return _favorites;
    final kw = _segment == 1 ? '唐' : '宋';
    return _favorites
        .where((p) => (p.dynastyName ?? '').contains(kw))
        .toList();
  }

  Future<void> _selectCollection(String? name) async {
    final favs = name == null
        ? await DatabaseHelper.getFavoritePoems()
        : await DatabaseHelper.getFavoritePoemsByCollection(name);
    if (mounted) {
      setState(() {
        _selectedCollection = name;
        _favorites = favs;
      });
    }
  }

  /// 取消收藏（滑动删除与长按菜单共用）
  ///
  /// 单独抽成方法：此处使用的是 State 自己的 context，与 mounted 检查同源，
  /// 避免跨异步间隙误用 itemBuilder 的 context 触发 use_build_context_synchronously。
  Future<void> _unfavorite(Poem poem) async {
    if (_selectedCollection != null) {
      await DatabaseHelper.removeFavoriteFromCollection(
          poem.id, _selectedCollection!);
    } else {
      await DatabaseHelper.removeFavorite(poem.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _createCollection() async {
    final name = await _showInputDialog('新建收藏夹', '请输入收藏夹名称');
    if (name == null || name.trim().isEmpty) return;
    await DatabaseHelper.createCollection(name.trim());
    await _loadData();
  }

  Future<void> _renameCollection(String oldName) async {
    final newName =
        await _showInputDialog('重命名收藏夹', '请输入新名称', initial: oldName);
    if (newName == null || newName.trim().isEmpty || newName.trim() == oldName) {
      return;
    }
    await DatabaseHelper.renameCollection(oldName, newName.trim());
    if (_selectedCollection == oldName) _selectedCollection = newName.trim();
    await _loadData();
  }

  Future<void> _deleteCollection(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('确定删除收藏夹"$name"及其下所有收藏？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: ShiciColors.of(context).cinnabar)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.deleteCollection(name);
    if (_selectedCollection == name) _selectedCollection = null;
    await _loadData();
  }

  Future<String?> _showInputDialog(String title, String hint,
      {String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _topBar(c),
            if (!_loading) ...<Widget>[
              const SizedBox(height: 8),
              ShiciSegmented(
                options: _segments,
                selectedIndex: _segment,
                onChanged: (i) => setState(() => _segment = i),
              ),
            ],
            Expanded(child: _buildList(c)),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ShiciColors c) {
    final label = _selectedCollection ?? '我的收藏';
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                style: ShiciText.title.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '卡片样式：${_cardStyle.label}',
              icon: PoemIcon(PoemIcons.sort, size: 18, color: c.inkSoft),
              onPressed: _showCardStyleSheet,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showCollectionSheet,
              child: Row(
                children: <Widget>[
                  PoemIcon(PoemIcons.category, size: 18, color: c.ink),
                  const SizedBox(width: 4),
                  Text('收藏夹',
                      style: ShiciText.caption
                          .copyWith(fontSize: 12, color: c.inkSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ShiciColors c) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.cinnabar));
    }
    final items = _visible;
    if (items.isEmpty) {
      final isEmptyJar = _selectedCollection != null;
      final segFiltered = _favorites.isNotEmpty && _segment != 0;
      return EmptyState(
        icon: PoemIcons.bookmark,
        title: segFiltered
            ? '这一类还没有收藏'
            : (isEmptyJar ? '这个收藏夹还是空的' : '收藏夹还是空的'),
        description: segFiltered
            ? '换个分段看看，或去诗词库继续挑'
            : '遇到喜欢的句子，轻点书签即可收藏，随时回来重读',
        actionLabel: '去诗词库看看',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LibraryPage()),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: c.cinnabar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final poem = items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: Key('fav_${poem.id}_${_selectedCollection ?? "all"}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: c.cinnabar,
                  borderRadius: BorderRadius.circular(ShiciSize.rMd),
                ),
                child: Icon(Icons.delete, color: c.onAccent, size: 20),
              ),
              onDismissed: (_) {
                setState(() => _favorites.removeWhere((p) => p.id == poem.id));
                _unfavorite(poem);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showFavItemMenu(poem),
                child: PoemListCard(
                  poem: poem,
                  style: _cardStyle,
                  tags: poemTagsFor(poem, _poemTags),
                  // 收藏夹里每一条都是已收藏，收藏态恒为真
                  favorite: true,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => PoemDetailPage(poemId: poem.id)))
                      .then((_) => _loadData()),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 卡片样式切换：收藏夹条目多，紧凑列表最划算，这里只是把选择权交回用户
  Future<void> _showCardStyleSheet() async {
    final picked = await showPoemCardStylePicker(context, current: _cardStyle);
    if (picked == null || picked == _cardStyle) return;
    setState(() => _cardStyle = picked);
    await PoemCardStyleStore.save(picked);
  }

  /// 收藏夹面板：切换 / 新建 / 长按重命名或删除
  void _showCollectionSheet() {
    final c = ShiciColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: <Widget>[
                  Text('收藏夹',
                      style: ShiciText.title.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.ink)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _createCollection();
                    },
                    child: Text('新建',
                        style: ShiciText.caption.copyWith(
                            fontSize: 12, color: c.cinnabar)),
                  ),
                ],
              ),
            ),
            _collectionTile(
              name: '全部收藏',
              count: _collections.fold<int>(
                  0, (sum, e) => sum + (e['cnt'] as int? ?? 0)),
              selected: _selectedCollection == null,
              onTap: () {
                Navigator.pop(sheetCtx);
                _selectCollection(null);
              },
              onLongPress: null,
            ),
            for (final col in _collections)
              _collectionTile(
                name: col['name'] as String,
                count: col['cnt'] as int? ?? 0,
                selected: _selectedCollection == col['name'],
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _selectCollection(col['name'] as String);
                },
                onLongPress: () {
                  Navigator.pop(sheetCtx);
                  _showCollectionMenu(col['name'] as String);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _collectionTile({
    required String name,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback? onLongPress,
  }) {
    final c = ShiciColors.of(context);
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Icon(
        selected ? Icons.check_circle : Icons.folder_outlined,
        size: 20,
        color: selected ? c.cinnabar : c.inkSoft,
      ),
      title: Text(name,
          style: ShiciText.body.copyWith(
              fontSize: 14,
              color: selected ? c.cinnabar : c.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      trailing: Text('$count',
          style: ShiciText.numeral.copyWith(fontSize: 12, color: c.inkSoft)),
    );
  }

  /// 长按收藏夹弹出操作菜单（重命名/删除）
  void _showCollectionMenu(String name) {
    final c = ShiciColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name,
                  style: ShiciText.title.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, size: 20, color: c.inkSoft),
              title: const Text('重命名收藏夹'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _renameCollection(name);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, size: 20, color: c.cinnabar),
              title: Text('删除收藏夹',
                  style: TextStyle(color: c.cinnabar)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _deleteCollection(name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 长按收藏项：移动到其他夹 / 取消收藏
  void _showFavItemMenu(Poem poem) {
    final c = ShiciColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(poem.title,
                  style: ShiciText.title.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
            ),
            ListTile(
              leading:
                  Icon(Icons.drive_file_move_outline, size: 20, color: c.inkSoft),
              title: const Text('移动到收藏夹'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showMoveTarget(poem);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, size: 20, color: c.cinnabar),
              title: Text('取消收藏', style: TextStyle(color: c.cinnabar)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _unfavorite(poem);
                await _loadData();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 选择目标收藏夹（移动）
  void _showMoveTarget(Poem poem) {
    final c = ShiciColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('选择目标收藏夹',
                  style: ShiciText.title.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
            ),
            for (final col in _collections)
              ListTile(
                leading: Icon(
                  col['name'] == _selectedCollection
                      ? Icons.check_circle
                      : Icons.folder_outlined,
                  size: 20,
                  color: c.indigo,
                ),
                title: Text(col['name'] as String),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await DatabaseHelper.removeFavorite(poem.id);
                  await DatabaseHelper.addFavorite(poem.id,
                      collection: col['name'] as String);
                  await _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('已移动到「${col['name']}」'),
                          duration: const Duration(seconds: 1)),
                    );
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.add, size: 20, color: c.cinnabar),
              title: Text('新建收藏夹', style: TextStyle(color: c.cinnabar)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final name = await _showInputDialog('新建收藏夹', '请输入收藏夹名称');
                if (name == null || name.trim().isEmpty) return;
                await DatabaseHelper.createCollection(name.trim());
                await DatabaseHelper.removeFavorite(poem.id);
                await DatabaseHelper.addFavorite(poem.id,
                    collection: name.trim());
                await _loadData();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
