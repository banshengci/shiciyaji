import '../data/models/models.dart';

/// 一天的计划任务。
class PlanDay {
  /// 计划是否配了每日定量。为 false 时 [poemIds] 恒为空 ——
  /// 老计划（迁移前建的）没有定量，界面上的表现应该与从前完全一致，
  /// 不能突然显示一个「今日 0 首」把它说得像空计划。
  final bool hasSchedule;

  /// 今天该学的篇目（按计划里的原顺序，已跳过学过的）
  final List<int> poemIds;

  /// 整个计划还有多少首没学
  final int pendingCount;

  /// 计划是否已全部学完
  final bool finished;

  /// 计划尚未开始（起始日在未来）
  final bool notStartedYet;

  const PlanDay({
    required this.hasSchedule,
    required this.poemIds,
    required this.pendingCount,
    required this.finished,
    this.notStartedYet = false,
  });

  static const PlanDay none = PlanDay(
    hasSchedule: false,
    poemIds: <int>[],
    pendingCount: 0,
    finished: false,
  );
}

/// 计划进度
class PlanProgress {
  final int done;
  final int total;

  const PlanProgress(this.done, this.total);

  double get ratio => total == 0 ? 0 : done / total;
  int get remaining => total - done;
}

/// 学习计划排期 —— 把「一份清单」变成「今天该学这几首」。
///
/// ## 为什么不是「欠账模型」
///
/// 常见做法是 `今天该学 = 从起始日到今天 × 每日定量`，断卡三天回来就欠 9 首。
/// 那会直接把人劝退。这里用**按序推进**：每天取「尚未学过」的最前面 N 首，
/// 昨天没学完的不补，今天照旧的量走。少学一天，计划整体后移一天 —— 这是
/// 自学能接受的唯一代价。
///
/// 全部是把 [StudyPlan] + 已学集合算成结果的**纯函数**，不碰数据库，
/// 因此边界（篇目耗尽、超额、断卡、改定量、起始日在未来）都能直接测。
class PlanScheduler {
  PlanScheduler._();

  /// 今日任务。[now] 可注入以便测试。
  static PlanDay today(
    StudyPlan plan, {
    required Set<int> studiedIds,
    DateTime? now,
  }) {
    final today = dateKey(now ?? DateTime.now());
    final pending = pendingIds(plan, studiedIds);
    final finished = pending.isEmpty;

    final target = plan.dailyTarget;
    if (target == null || target <= 0) {
      // 没配定量：交给界面按老样子展示总进度
      return PlanDay(
        hasSchedule: false,
        poemIds: const <int>[],
        pendingCount: pending.length,
        finished: finished,
      );
    }

    final start = plan.startDate;
    if (start != null && start.isNotEmpty && start.compareTo(today) > 0) {
      return PlanDay(
        hasSchedule: true,
        poemIds: const <int>[],
        pendingCount: pending.length,
        finished: finished,
        notStartedYet: true,
      );
    }

    return PlanDay(
      hasSchedule: true,
      poemIds: pending.take(target).toList(),
      pendingCount: pending.length,
      finished: finished,
    );
  }

  /// 计划里尚未学过的篇目（保持计划中的原顺序）
  static List<int> pendingIds(StudyPlan plan, Set<int> studiedIds) {
    // 去重但保序：同一首选进计划两次时只留一次
    final seen = <int>{};
    final pending = <int>[];
    for (final id in plan.poemIds) {
      if (studiedIds.contains(id)) continue;
      if (seen.add(id)) pending.add(id);
    }
    return pending;
  }

  static PlanProgress progress(StudyPlan plan, Set<int> studiedIds) {
    final total = plan.poemIds.toSet().length;
    final done = plan.poemIds.toSet().where(studiedIds.contains).length;
    return PlanProgress(done, total);
  }

  /// 按当前定量估算完成日；没有定量或已学完时返回 null。
  ///
  /// 只在「今天之后再学」的假设下算，所以断卡不影响估算结果 ——
  /// 它回答的是「按这个节奏还要多少天」，不是「原本哪天能完成」。
  static DateTime? estimateFinishDate(
    StudyPlan plan, {
    required Set<int> studiedIds,
    DateTime? now,
  }) {
    final target = plan.dailyTarget;
    if (target == null || target <= 0) return null;
    final pending = pendingIds(plan, studiedIds).length;
    if (pending == 0) return null;
    final base = now ?? DateTime.now();
    final days = (pending / target).ceil();
    return DateTime(base.year, base.month, base.day + days);
  }

  /// `YYYY-MM-DD`
  static String dateKey(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
