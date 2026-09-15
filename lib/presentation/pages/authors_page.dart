import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/poem_icon.dart';
import '../../core/s2t_converter.dart';
import '../../core/design_tokens.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/empty_state.dart';
import 'author_detail_page.dart';

/// 诗人列表页：按作品数排序，可按朝代筛选、按名字搜索
class AuthorsPage extends StatefulWidget {
  const AuthorsPage({super.key});

  @override
  State<AuthorsPage> createState() => _AuthorsPageState();
}

class _AuthorsPageState extends State<AuthorsPage> {
  List<({Author author, int poemCount})> _all = const [];
  List<Dynasty> _dynasties = const [];
  int? _dynastyId;
  String _query = '';
  bool _loading = true;
  bool _traditional = false;

  String _t(String text) => _traditional
      ? S2TConverter.toTraditional(text)
      : S2TConverter.toSimplified(text);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dynasties = await DatabaseHelper.getAllDynasties();
    final authors =
        await DatabaseHelper.getAuthorsWithPoemCount(dynastyId: _dynastyId);
    if (!mounted) return;
    setState(() {
      _traditional = prefs.getBool('traditional_chinese') ?? false;
      _dynasties = dynasties;
      _all = authors;
      _loading = false;
    });
  }

  /// 搜索只在已加载列表上做内存过滤（诗人量级小，无需再查库）
  List<({Author author, int poemCount})> get _filtered {
    if (_query.isEmpty) return _all;
    return _all.where((e) => e.author.name.contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('诗人')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索诗人',
                      prefixIcon: const PoemIcon(PoemIcons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                _buildDynastyFilter(theme),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('共 ${list.length} 位诗人',
                          style: theme.textTheme.bodySmall),
                      const Spacer(),
                      Text('按作品数排序', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.person_off_outlined,
                          title: '没有匹配的诗人',
                          description: '换个关键词或朝代筛选试试',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _buildTile(theme, list[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildDynastyFilter(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(theme, '全部', _dynastyId == null, () {
            setState(() => _dynastyId = null);
            _load();
          }),
          ..._dynasties.map((d) => _chip(theme, _t(d.name), _dynastyId == d.id,
                  () {
                setState(() => _dynastyId = d.id);
                _load();
              })),
        ],
      ),
    );
  }

  Widget _chip(
      ThemeData theme, String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 13)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: ShiciColors.ofOr(theme.brightness).pine.withOpacity(0.2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _buildTile(ThemeData theme, ({Author author, int poemCount}) e) {
    final c = ShiciColors.of(context);
    final name = e.author.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.cinnabar.withOpacity(0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name.isEmpty ? '？' : _t(String.fromCharCode(name.runes.first)),
            style: TextStyle(
                color: c.onAccent,
                fontSize: 18,
                fontFamily: 'serif',
                fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(_t(name),
            style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        subtitle: e.author.bio == null || e.author.bio!.isEmpty
            ? null
            : Text(_t(e.author.bio!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
        trailing: Text('${e.poemCount} 首',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: c.pine, fontWeight: FontWeight.bold)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AuthorDetailPage(authorId: e.author.id, authorName: name),
          ),
        ),
      ),
    );
  }
}
