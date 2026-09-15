import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../widgets/poem_icon.dart';
import '../../core/design_tokens.dart';
import '../../data/database/database_helper.dart';

/// 离线包商店：列出可用的诗词包，并提供安装/卸载
class PackStorePage extends StatefulWidget {
  const PackStorePage({super.key});

  @override
  State<PackStorePage> createState() => _PackStorePageState();
}

class _PackStorePageState extends State<PackStorePage> {
  bool _loading = true;
  // 离线包元信息（启动时从 assets 读取元数据）
  final List<_PackMeta> _packs = const [
    _PackMeta(
      name: 'tangshi',
      title: '唐诗扩充',
      subtitle: '600 首 · 预置之外的全唐诗名篇',
      description:
          '在预置诗词之外扩充 600 首唐诗：李白、杜甫、白居易、王维等大家代表作。名篇含白话译文、赏析与创作背景，其余诗文完整可读，安装后离线可用。',
      assetPath: 'assets/data/packs/tangshi.json',
      icon: PoemIcons.dynasty,
      color: Color(0xFFC41A1A),
    ),
    _PackMeta(
      name: 'songci',
      title: '宋词扩充',
      subtitle: '500 首 · 豪放婉约大家词作',
      description:
          '在预置诗词之外扩充 500 首宋词：苏轼、辛弃疾、李清照、陆游、欧阳修等大家作品。名篇含白话译文、赏析与创作背景，其余词作完整可读。',
      assetPath: 'assets/data/packs/songci.json',
      icon: PoemIcons.edit,
      color: Color(0xFF1A6B5C),
    ),
    _PackMeta(
      name: 'xiaoxue',
      title: '小学补充',
      subtitle: '150 首 · 教材常见而预置未收录',
      description:
          '部编教材常见而预置未收录的古诗 150 首：别董大、枫桥夜泊、题临安邸等。名篇含白话译文、赏析与创作背景，适合小学阶段拓展阅读。',
      assetPath: 'assets/data/packs/xiaoxue.json',
      icon: PoemIcons.goal,
      color: Color(0xFFB8860B),
    ),
  ];
  final Map<String, bool> _installed = {};
  final Map<String, int> _counts = {};
  final Map<String, bool> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadInstalledStatus();
  }

  Future<void> _loadInstalledStatus() async {
    final installed = await DatabaseHelper.getInstalledPacks();
    final map = {for (final r in installed) r['pack_name'] as String: true};
    final counts = {
      for (final r in installed) r['pack_name'] as String: r['count'] as int,
    };
    if (mounted) {
      setState(() {
        _installed
          ..clear()
          ..addAll(map);
        _counts
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    }
  }

  Future<void> _install(_PackMeta pack) async {
    setState(() => _busy[pack.name] = true);
    try {
      final jsonString = await rootBundle.loadString(pack.assetPath);
      final inserted = await DatabaseHelper.importPack(jsonString);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已安装《${pack.title}》${inserted > 0 ? " · 新增 $inserted 首" : ""}'),
            duration: const Duration(seconds: 3)),
      );
      await _loadInstalledStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy[pack.name] = false);
    }
  }

  Future<void> _uninstall(_PackMeta pack) async {
    final c = ShiciColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text('确定要卸载《${pack.title}》吗？\n该包导入的诗词、收藏、笔记将被一并删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('卸载', style: TextStyle(color: c.cinnabar))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy[pack.name] = true);
    try {
      final removed = await DatabaseHelper.uninstallPack(pack.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸载《${pack.title}》· 删除 $removed 首')),
      );
      await _loadInstalledStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('卸载失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy[pack.name] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线包管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loadInstalledStatus,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 说明卡片
                ShadCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          color: c.indigo, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('诗词离线包',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'serif')),
                            const SizedBox(height: 4),
                            Text(
                              '从 chinese-poetry 开源库（MIT 协议）预置，安装后即可离线阅读。',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final pack in _packs) ...[
                  _buildPackCard(pack, theme),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '数据源：chinese-poetry/ chinese-poetry · MIT 协议',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline, fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPackCard(_PackMeta pack, ThemeData theme) {
    final c = ShiciColors.of(context);
    final installed = _installed[pack.name] ?? false;
    final busy = _busy[pack.name] ?? false;
    final count = _counts[pack.name] ?? 0;
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: pack.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PoemIcon(pack.icon, color: pack.color, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(pack.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'serif')),
                        ),
                        if (installed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.indigo.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('已安装',
                                style: TextStyle(
                                    color: c.indigo,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(pack.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(pack.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              if (installed)
                Expanded(
                  child: Text(
                    '已添加 $count 首到本地数据库',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: c.indigo, fontWeight: FontWeight.w500),
                  ),
                )
              else
                const Spacer(),
              if (installed)
                ShadButton.outline(
                  onPressed: busy ? null : () => _uninstall(pack),
                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('卸载'),
                )
              else
                ShadButton(
                  onPressed: busy ? null : () => _install(pack),
                  icon: busy
                      ? null
                      : const PoemIcon(PoemIcons.download, size: 18),
                  child: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.onAccent))
                      : const Text('安装'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackMeta {
  final String name;
  final String title;
  final String subtitle;
  final String description;
  final String assetPath;
  final Object icon;
  final Color color;

  const _PackMeta({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.assetPath,
    required this.icon,
    required this.color,
  });
}
