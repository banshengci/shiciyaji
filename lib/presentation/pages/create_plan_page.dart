import 'package:flutter/material.dart';

import '../widgets/poem_icon.dart';
import '../../core/design_tokens.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';

/// 自定义学习计划创建页：从诗词库勾选诗词创建计划
class CreatePlanPage extends StatefulWidget {
  /// 预选的诗词 id（例如详情页「加入计划 → 新建计划」时带上当前这首）
  final List<int> initialPoemIds;

  const CreatePlanPage({super.key, this.initialPoemIds = const []});

  @override
  State<CreatePlanPage> createState() => _CreatePlanPageState();
}

class _CreatePlanPageState extends State<CreatePlanPage> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  List<Poem> _allPoems = [];
  final Set<int> _selected = {};
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadPoems();
  }

  Future<void> _loadPoems() async {
    final poems = await DatabaseHelper.getAllPoems();
    if (mounted) {
      setState(() {
        _allPoems = poems;
        _selected.addAll(widget.initialPoemIds);
        _loading = false;
      });
    }
  }

  List<Poem> get _filteredPoems {
    if (_filter.isEmpty) return _allPoems;
    final kw = _filter.toLowerCase();
    return _allPoems.where((p) {
      return p.title.toLowerCase().contains(kw) ||
          (p.authorName?.toLowerCase().contains(kw) ?? false) ||
          (p.dynastyName?.toLowerCase().contains(kw) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建学习计划'),
        actions: [
          TextButton.icon(
            onPressed: _selected.isEmpty ? null : _createPlan,
            icon: const Icon(Icons.check),
            label: Text('创建(${_selected.length})'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 计划信息输入
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '计划名称',
                          hintText: '如：每日精读五首',
                          border: OutlineInputBorder(),
                          prefixIcon: PoemIcon(PoemIcons.bookmark),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descController,
                        decoration: const InputDecoration(
                          labelText: '计划描述（可选）',
                          hintText: '简要描述学习目标',
                          border: OutlineInputBorder(),
                          prefixIcon: PoemIcon(PoemIcons.note),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                // 搜索框
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '筛选诗词（标题/作者/朝代）...',
                      prefixIcon: const PoemIcon(PoemIcons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                // 全选/取消全选
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text('已选 ${_selected.length} 首', style: theme.textTheme.bodySmall),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selected.length == _filteredPoems.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll(_filteredPoems.map((p) => p.id));
                            }
                          });
                        },
                        child: Text(
                          _selected.length == _filteredPoems.length && _filteredPoems.isNotEmpty
                              ? '取消全选'
                              : '全选当前',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 诗词列表（带勾选）
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredPoems.length,
                    itemBuilder: (context, index) {
                      final poem = _filteredPoems[index];
                      final isSelected = _selected.contains(poem.id);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? c.cinnabar
                              : theme.colorScheme.surfaceContainerHighest,
                          child: isSelected
                              ? Icon(Icons.check, color: c.onAccent, size: 18)
                              : Text('${poem.sortOrder}', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                        ),
                        title: Text(poem.title, style: const TextStyle(fontFamily: 'serif')),
                        subtitle: Text(
                          '${poem.dynastyName ?? ''} · ${poem.authorName ?? '佚名'}',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                        ),
                        trailing: Text(poem.type ?? '', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
                        selected: isSelected,
                        selectedTileColor: c.cinnabar.withOpacity(0.05),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(poem.id);
                            } else {
                              _selected.add(poem.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _createPlan() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入计划名称')),
      );
      return;
    }
    final ids = _allPoems.where((p) => _selected.contains(p.id)).map((p) => p.id).toList();
    await DatabaseHelper.createStudyPlan(name, _descController.text.trim(), ids);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('学习计划创建成功！'), duration: Duration(seconds: 2)),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }
}
