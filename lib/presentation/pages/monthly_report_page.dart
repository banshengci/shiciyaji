import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/report_builder.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/card_exporter.dart';
import '../widgets/poem_icon.dart';
import '../widgets/report_share_cards.dart';

/// 学习月报：看一个月的沉淀，并导出成一张长图。
///
/// 统计页解决「总数是多少」，月报解决「这个月我读了什么」——
/// 后者才有留存感，也是唯一值得分享出去的统计形态。
class MonthlyReportPage extends StatefulWidget {
  /// 起始展示的月份，默认上一个自然月
  final DateTime? initialMonth;

  const MonthlyReportPage({super.key, this.initialMonth});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  final _cardKey = GlobalKey();

  late int _year;
  late int _month;

  bool _loading = true;
  bool _sharing = false;
  MonthlyReport? _report;

  // 三个数据源只读一次，切月份时本地重算 —— 月报是纯函数，切月不必再查库
  List<StudyRecord> _records = const [];
  List<StudyNote> _notes = const [];
  Map<int, Poem> _poemById = const {};

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? DateTime.now();
    final prev = ReportBuilder.previousMonth(base);
    _year = prev.year;
    _month = prev.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await DatabaseHelper.getStudyRecords();
    final notes = await DatabaseHelper.getAllNotes();
    final poems = await DatabaseHelper.getAllPoems();
    if (!mounted) return;
    setState(() {
      _records = records;
      _notes = notes;
      _poemById = {for (final p in poems) p.id: p};
      _rebuild();
      _loading = false;
    });
  }

  void _rebuild() {
    _report = ReportBuilder.build(
      year: _year,
      month: _month,
      records: _records,
      notes: _notes,
      poemById: _poemById,
    );
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    // 不允许翻到未来：空月份没有意义
    final now = DateTime.now();
    if (y > now.year || (y == now.year && m > now.month)) return;
    setState(() {
      _year = y;
      _month = m;
      _rebuild();
    });
  }

  Future<void> _share(BuildContext anchorContext) async {
    if (_sharing || _report == null) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final message = await CardExporter.exportAndShare(
      key: _cardKey,
      fileName: 'study_report_${_year}_$_month.png',
      subject: '诗词雅集 · ${_report!.label}学习月报',
      text: '${_report!.label}：学过 ${_report!.studiedCount} 首、'
          '打卡 ${_report!.studyDays} 天 —— 来自「诗词雅集」',
      shareOrigin: origin,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('学习月报',
            style: TextStyle(fontFamily: ShiciFont.serif)),
        actions: [
          Builder(
            builder: (btnCtx) => IconButton(
              onPressed: _report == null ? null : () => _share(btnCtx),
              icon: const PoemIcon(PoemIcons.share),
              tooltip: '导出并分享',
            ),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.cinnabar))
          : Column(
              children: <Widget>[
                _monthBar(c),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Center(
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: MonthlyReportCard(
                          report: _report!,
                          width: 340,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : () => _share(context),
                      style: FilledButton.styleFrom(backgroundColor: c.pine),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: Text(_sharing ? '生成中…' : '导出长图'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _monthBar(ShiciColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一个月',
          ),
          Expanded(
            child: Text(
              '$_year 年 $_month 月',
              textAlign: TextAlign.center,
              style: ShiciText.title
                  .copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
            ),
          ),
          IconButton(
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一个月',
          ),
        ],
      ),
    );
  }
}
