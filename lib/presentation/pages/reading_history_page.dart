import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/empty_state.dart';
import 'poem_detail_page.dart';

/// 阅读历史页：最近20首已读诗词
class ReadingHistoryPage extends StatefulWidget {
  const ReadingHistoryPage({super.key});

  @override
  State<ReadingHistoryPage> createState() => _ReadingHistoryPageState();
}

class _ReadingHistoryPageState extends State<ReadingHistoryPage> {
  List<Poem> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await DatabaseHelper.getReadingHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读历史'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空历史',
              onPressed: () => _clearHistory(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const EmptyState(
                  icon: PoemIcons.duration,
                  title: '还没有阅读记录',
                  description: '阅读诗词后会自动记录在这里',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final poem = _history[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poem.id)),
                        ).then((_) => _loadHistory()),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 时间轴序号
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.daiLan.withOpacity(0.1),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.daiLan,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      poem.title,
                                      style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'serif'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${poem.dynastyName ?? ''} · ${poem.authorName ?? '佚名'}',
                                      style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      poem.content.split('\n').first,
                                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7), fontFamily: 'serif'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _clearHistory() async {
    final db = await DatabaseHelper.database();
    await db.delete('reading_history');
    setState(() => _history = []);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('阅读历史已清空'), duration: Duration(seconds: 1)),
      );
    }
  }
}
