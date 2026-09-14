import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/poem_icon.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_dialogs.dart' show runEditFlow, runDeleteFlow, EditOutcome;
import 'poem_detail_page.dart';

/// 笔记总览：按诗词分组 + 搜索 + 编辑/删除 + 跳转详情
class MyNotesPage extends StatefulWidget {
  const MyNotesPage({super.key});

  @override
  State<MyNotesPage> createState() => _MyNotesPageState();
}

class _MyNotesPageState extends State<MyNotesPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<StudyNote> _allNotes = [];
  int _totalCount = 0;
  int _notedPoemsCount = 0;
  bool _loading = true;

  // 按 poemId 分组展开状态
  final Set<int> _expandedPoems = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _loadData);
    });
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final kw = _searchController.text.trim();
    final results = await Future.wait([
      DatabaseHelper.getAllNotes(keyword: kw),
      DatabaseHelper.getNotesCount(),
      DatabaseHelper.getNotedPoemsCount(),
    ]);
    if (mounted) {
      setState(() {
        _allNotes = List<StudyNote>.from(results[0] as List);
        _totalCount = results[1] as int;
        _notedPoemsCount = results[2] as int;
        _loading = false;
      });
    }
  }

  /// 按诗词分组（注意同一首诗的多条笔记）
  List<List<StudyNote>> get _groups {
    final map = <int, List<StudyNote>>{};
    for (final n in _allNotes) {
      map.putIfAbsent(n.poemId, () => []).add(n);
    }
    return map.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的笔记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 搜索 + 统计
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索笔记/诗词/作者',
                            prefixIcon: const PoemIcon(PoemIcons.search, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () { _searchController.clear(); _loadData(); })
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _tag('笔记总数', '$_totalCount', AppTheme.zhuShaHong, theme),
                      const SizedBox(width: 8),
                      _tag('记有笔记的诗词', '$_notedPoemsCount', AppTheme.daiLan, theme),
                      if (_searchController.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _tag('当前结果', '${_allNotes.length}', AppTheme.songLv, theme),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _allNotes.isEmpty
                      ? _buildEmpty(theme)
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _groups.length,
                            itemBuilder: (context, idx) => _buildGroup(_groups[idx], theme),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _tag(String label, String value, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: theme.colorScheme.outline, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final searching = _searchController.text.isNotEmpty;
    return EmptyState(
      icon: PoemIcons.note,
      title: searching ? '没有匹配的笔记' : '还没有笔记',
      description: searching ? '换个关键词试试' : '去诗词详情页写下你的感悟吧',
    );
  }

  Widget _buildGroup(List<StudyNote> group, ThemeData theme) {
    final head = group.first;
    final poemId = head.poemId;
    final title = head.poemTitle ?? '诗 $poemId';
    final authorName = head.authorName ?? '佚名';
    final dynastyName = head.dynastyName ?? '';
    final expanded = _expandedPoems.contains(poemId) || group.length == 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (group.length == 1) return; // 单条不用折叠
              setState(() {
                if (_expandedPoems.contains(poemId)) {
                  _expandedPoems.remove(poemId);
                } else {
                  _expandedPoems.add(poemId);
                }
              });
            },
            onLongPress: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poemId)),
            ).then((_) => _loadData()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.daiLan.withOpacity(0.15),
                    child: Text('${group.length}', style: const TextStyle(color: AppTheme.daiLan, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$dynastyName · $authorName', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                  if (group.length > 1)
                    Icon(expanded ? Icons.expand_less : Icons.expand_more, color: theme.colorScheme.outline, size: 22),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: (expanded ? group : [group.first]).map((n) => _buildNoteTile(n, theme, group.length)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteTile(StudyNote note, ThemeData theme, int totalInGroup) {
    final date = note.updatedAt ?? note.createdAt;
    final dateStr = date.length >= 16 ? date.substring(0, 16) : date;
    return Padding(
      padding: EdgeInsets.only(bottom: totalInGroup > 1 ? 8 : 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.content, style: TextStyle(fontSize: 14, height: 1.7, fontFamily: 'serif', color: theme.colorScheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                PoemIcon(PoemIcons.duration, size: 12, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(child: Text(dateStr, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline))),
                _miniBtn(PoemIcons.edit, '编辑', theme.colorScheme.outline, () => _editNote(note, theme)),
                const SizedBox(width: 4),
                _miniBtn(Icons.delete_outline, '删除', AppTheme.zhuShaHong, () => _delNote(note)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(Object icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PoemIcon(icon, size: 13, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }

  Future<void> _editNote(StudyNote note, ThemeData theme) async {
    final outcome = await runEditFlow(
      context,
      noteId: note.id,
      currentContent: note.content,
      onSave: DatabaseHelper.updateNote,
      maxLines: 6,
    );
    if (outcome == EditOutcome.changed && mounted) {
      _loadData();
    }
  }

  Future<void> _delNote(StudyNote note) async {
    final deleted = await runDeleteFlow(
      context,
      noteId: note.id,
      onDelete: DatabaseHelper.deleteNote,
    );
    if (deleted == true && mounted) {
      _loadData();
    }
  }
}
