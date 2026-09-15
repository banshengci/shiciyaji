import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/poem_icon.dart';
import '../../core/s2t_converter.dart';
import '../../core/design_tokens.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import 'poem_detail_page.dart';

/// 诗人详情页：生平简介 + 该诗人全部作品
///
/// 补上原先的导航断点：以前作者只是详情页里的一段静态文字，
/// 无法「顺着作者看他的其他作品」。
class AuthorDetailPage extends StatefulWidget {
  const AuthorDetailPage({super.key, required this.authorId, this.authorName});

  final int authorId;

  /// 可选：先行显示的名字，避免加载期间标题闪烁
  final String? authorName;

  @override
  State<AuthorDetailPage> createState() => _AuthorDetailPageState();
}

class _AuthorDetailPageState extends State<AuthorDetailPage> {
  Author? _author;
  List<Poem> _poems = const [];
  String? _dynastyName;
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
    final author = await DatabaseHelper.getAuthorById(widget.authorId);
    final poems = await DatabaseHelper.getPoemsByAuthor(widget.authorId);
    String? dynastyName;
    if (author?.dynastyId != null) {
      final dynasties = await DatabaseHelper.getAllDynasties();
      for (final d in dynasties) {
        if (d.id == author!.dynastyId) {
          dynastyName = d.name;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _traditional = prefs.getBool('traditional_chinese') ?? false;
      _author = author;
      _poems = poems;
      _dynastyName = dynastyName;
      _loading = false;
    });
  }

  /// 生卒年展示：两端都可能缺失，缺失用 ? 占位；全缺则不显示
  String? get _lifeSpan {
    final b = _author?.birthYear;
    final d = _author?.deathYear;
    if ((b == null || b.isEmpty) && (d == null || d.isEmpty)) return null;
    final bs = (b == null || b.isEmpty) ? '?' : b;
    final ds = (d == null || d.isEmpty) ? '?' : d;
    return '$bs — $ds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);
    final name = _author?.name ?? widget.authorName ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(_t(name.isEmpty ? '诗人' : name))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _author == null
              ? Center(
                  child: Text('未找到该诗人', style: theme.textTheme.bodyLarge),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(theme, name),
                    if (_author!.bio != null && _author!.bio!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildBio(theme),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        PoemIcon(PoemIcons.library, size: 18, color: c.pine),
                        const SizedBox(width: 6),
                        Text('作品 ${_poems.length} 首',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_poems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('暂无收录作品',
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center),
                      )
                    else
                      ..._poems.map((p) => _buildPoemTile(theme, p)),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _buildHeader(ThemeData theme, String name) {
    final c = ShiciColors.of(context);
    final span = _lifeSpan;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.pine.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          // 朱砂圆章式头像：取姓氏首字
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.cinnabar.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              name.isEmpty
                  ? '？'
                  : _t(String.fromCharCode(name.runes.first)),
              style: TextStyle(
                color: c.onAccent,
                fontSize: 26,
                fontFamily: 'serif',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(name),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'serif',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (_dynastyName != null) _t(_dynastyName!),
                    if (span != null) span,
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBio(ThemeData theme) {
    final c = ShiciColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PoemIcon(PoemIcons.profile, size: 18, color: c.pine),
            const SizedBox(width: 6),
            Text('生平',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _t(_author!.bio!),
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
        ),
      ],
    );
  }

  Widget _buildPoemTile(ThemeData theme, Poem poem) {
    // 取正文首句做副标题（去掉换行，截断过长）
    final firstLine = poem.content.split('\n').first;
    final preview =
        firstLine.length > 22 ? '${firstLine.substring(0, 22)}…' : firstLine;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(
          _t(poem.title),
          style: const TextStyle(fontFamily: 'serif', fontSize: 16),
        ),
        subtitle: Text(
          _t(preview),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: poem.type == null
            ? null
            : Text(_t(poem.type!), style: theme.textTheme.bodySmall),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poem.id)),
        ),
      ),
    );
  }
}
