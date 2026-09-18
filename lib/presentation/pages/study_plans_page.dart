import 'package:flutter/material.dart';

import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import '../widgets/empty_state.dart';
import '../../core/design_tokens.dart';
import '../../core/plan_scheduler.dart';
import '../../core/theme.dart';
import '../../core/tts_play_queue.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import 'poem_detail_page.dart';
import 'create_plan_page.dart';
import 'recall_quiz_page.dart';
import 'library_page.dart';

/// 学习计划：自「我的」菜单进入的独立页
///
/// 画布把学习计划的入口放在「我的」（S5 `3:1125` 菜单-学习计划），
/// 因此这里从收藏页中独立出来；收藏页据此回归纯收藏列表的版面。
class StudyPlansPage extends StatefulWidget {
  const StudyPlansPage({super.key});

  @override
  State<StudyPlansPage> createState() => _StudyPlansPageState();
}

class _StudyPlansPageState extends State<StudyPlansPage> {
  List<StudyPlan> _plans = <StudyPlan>[];
  Map<int, int> _planStudied = <int, int>{};

  /// 配了每日定量的计划「今日还剩几首」；0 表示没配定量或今天已学完
  Map<int, int> _planToday = <int, int>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // 先装载预设计划，否则首次进入看不到预设计划（需手动刷新才出现）
    await DatabaseHelper.ensurePresetPlans();
    await _loadData();
  }

  Future<void> _loadData() async {
    final plans = await DatabaseHelper.getStudyPlans();
    // 各计划的已学首数，并行拉取避免逐个等待
    final studiedCounts = await Future.wait(
      plans.map((p) => DatabaseHelper.getStudiedCountIn(p.poemIds)),
    );
    // 配了每日定量的计划再算一次「今日还剩几首」（没配的不显示，保持老样子）
    final todayCounts = await Future.wait(plans.map((p) async {
      if (p.dailyTarget == null || p.dailyTarget! <= 0) return 0;
      final studied = await DatabaseHelper.getStudiedIdsIn(p.poemIds);
      return PlanScheduler.today(p, studiedIds: studied).poemIds.length;
    }));
    if (mounted) {
      setState(() {
        _plans = plans;
        _planStudied = <int, int>{
          for (var i = 0; i < plans.length; i++) plans[i].id: studiedCounts[i],
        };
        _planToday = <int, int>{
          for (var i = 0; i < plans.length; i++) plans[i].id: todayCounts[i],
        };
        _loading = false;
      });
    }
  }

  Future<void> _createPlan() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreatePlanPage()),
    );
    if (result == true) await _loadData();
  }

  /// 用计划篇目开连播（睡前听 / 通勤听）
  Future<void> _listenPlan(StudyPlan plan) async {
    if (plan.poemIds.isEmpty) return;
    final poems = await DatabaseHelper.getPoemsByIds(plan.poemIds);
    if (poems.isEmpty || !mounted) return;
    final items = poems
        .map((p) => TtsQueueItem(
              poemId: p.id,
              title: p.title,
              content: p.content,
            ))
        .toList(growable: false);
    await TtsPlayQueue.instance.start(items, label: plan.name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始连播「${plan.name}」${items.length} 首'),
        duration: const Duration(seconds: 2),
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
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.cinnabar))
                  : _plans.isEmpty
                      ? EmptyState(
                          icon: PoemIcons.goal,
                          title: '还没有学习计划',
                          description: '新建计划，用艾宾浩斯曲线安排复习节奏',
                          actionLabel: '去诗词库选诗',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const LibraryPage()),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: c.cinnabar,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                            itemCount: _plans.length,
                            itemBuilder: (context, index) {
                              final plan = _plans[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _planCard(c, plan),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ShiciColors c) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.arrow_back_ios_new, size: 17, color: c.ink),
            ),
            const SizedBox(width: 14),
            Text(
              '学习计划',
              style: ShiciText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _createPlan,
              child: Icon(Icons.add, size: 22, color: c.cinnabar),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(ShiciColors c, StudyPlan plan) {
    final total = plan.poemIds.length;
    final studied = _planStudied[plan.id] ?? 0;

    return ShiciCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => _PlanDetailPage(plan: plan)))
          .then((_) => _loadData()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PoemIcon(PoemIcons.library, size: 20, color: c.indigo),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  plan.name,
                  style: ShiciText.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.cinnabar.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(ShiciSize.rSeal),
                ),
                child: Text(
                  '$total首',
                  style: ShiciText.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: c.cinnabar,
                  ),
                ),
              ),
              IconButton(
                tooltip: '连续听本计划',
                visualDensity: VisualDensity.compact,
                onPressed: plan.poemIds.isEmpty
                    ? null
                    : () => _listenPlan(plan),
                icon: Icon(Icons.headphones, size: 20, color: c.indigo),
              ),
              // 配了每日定量的计划多一枚「今日」标记，让「今天学几首」一眼可见
              if (plan.dailyTarget != null) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.pine.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(ShiciSize.rSeal),
                  ),
                  child: Text(
                    (_planToday[plan.id] ?? 0) > 0
                        ? '今日 ${_planToday[plan.id]} 首'
                        : '今日已学完',
                    style: ShiciText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.pine,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (plan.description != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              plan.description!,
              style: ShiciText.caption.copyWith(fontSize: 12, color: c.inkSoft),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total > 0 ? (studied / total).clamp(0.0, 1.0) : 0.0,
              minHeight: 4,
              backgroundColor: c.sand,
              color: c.cinnabar,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(
                studied > 0 ? '已学 $studied / $total 首' : '共 $total 首 · 点击开始学习',
                style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: c.inkFaint),
            ],
          ),
        ],
      ),
    );
  }
}

/// 计划详情：计划内诗词清单 + 背诵自测入口
class _PlanDetailPage extends StatefulWidget {
  final StudyPlan plan;

  const _PlanDetailPage({required this.plan});

  @override
  State<_PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<_PlanDetailPage> {
  List<Poem> _poems = <Poem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPoems();
  }

  Future<void> _loadPoems() async {
    // 批量查询，避免逐条 getPoemById 造成的 N 次往返
    final poems = await DatabaseHelper.getPoemsByIds(widget.plan.poemIds);
    if (mounted) {
      setState(() {
        _poems = poems;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        elevation: 0,
        title: Text(
          widget.plan.name,
          style: ShiciText.title.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        iconTheme: IconThemeData(color: c.ink),
        actions: <Widget>[
          if (_poems.isNotEmpty)
            IconButton(
              tooltip: '背诵自测',
              icon: PoemIcon(PoemIcons.recite, size: 20, color: c.ink),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecallQuizPage(
                    title: widget.plan.name,
                    poemIds: widget.plan.poemIds,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.cinnabar))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
              itemCount: _poems.length,
              itemBuilder: (context, index) {
                final poem = _poems[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ShiciCard(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => PoemDetailPage(poemId: poem.id)))
                        .then((_) => _loadPoems()),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${index + 1}',
                          style: ShiciText.numeral.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.cinnabar,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            poem.title,
                            style: ShiciText.title.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${poem.dynastyName ?? ''} · ${poem.authorName ?? '佚名'}',
                          style: ShiciText.caption
                              .copyWith(fontSize: 11, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
