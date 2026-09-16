import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/plan_scheduler.dart';
import 'package:shici_yaji/data/models/models.dart';

/// 计划排期守卫。
///
/// 排期的规则是「按序推进、不补欠账」，所以边界比主线更重要：
/// 断卡、篇目耗尽、改定量、起始日在未来、老计划没有定量 —— 这些一旦算错，
/// 用户看到的是「今天没有任务」或者「今天 12 首」，两种都会直接把习惯打断。
void main() {
  StudyPlan plan({
    List<int> ids = const [1, 2, 3, 4, 5, 6],
    int? dailyTarget,
    String? startDate,
  }) =>
      StudyPlan(
        id: 1,
        name: '测试计划',
        poemIds: ids,
        dailyTarget: dailyTarget,
        startDate: startDate,
      );

  final day = DateTime(2026, 9, 16);

  group('今日篇目', () {
    test('按顺序取每日定量，跳过学过的', () {
      final result = PlanScheduler.today(
        plan(dailyTarget: 3),
        studiedIds: {1},
        now: day,
      );

      expect(result.hasSchedule, isTrue);
      expect(result.poemIds, [2, 3, 4],
          reason: '应当跳过已学的 1，再按顺序取三首');
      expect(result.pendingCount, 5);
      expect(result.finished, isFalse);
    });

    test('断卡不补欠账：隔了十天回来，今天仍然只有定量的那么多', () {
      final first = PlanScheduler.today(
        plan(dailyTarget: 2),
        studiedIds: const {},
        now: day,
      );
      final afterGap = PlanScheduler.today(
        plan(dailyTarget: 2),
        studiedIds: const {},
        now: DateTime(2026, 9, 26),
      );

      expect(afterGap.poemIds.length, first.poemIds.length);
      expect(afterGap.poemIds, first.poemIds,
          reason: '断卡后应当照旧从最前面取，不累积成 20 首');
    });

    test('计划学完后不再给任务', () {
      final result = PlanScheduler.today(
        plan(dailyTarget: 3),
        studiedIds: {1, 2, 3, 4, 5, 6},
        now: day,
      );
      expect(result.finished, isTrue);
      expect(result.poemIds, isEmpty);
      expect(result.pendingCount, 0);
    });

    test('剩下的不足一天的量时只给剩下的', () {
      final result = PlanScheduler.today(
        plan(dailyTarget: 3),
        studiedIds: {1, 2, 3, 4},
        now: day,
      );
      expect(result.poemIds, [5, 6]);
      expect(result.pendingCount, 2);
    });

    test('没有每日定量的老计划不排期 —— 界面保持原样', () {
      final result = PlanScheduler.today(plan(), studiedIds: const {}, now: day);
      expect(result.hasSchedule, isFalse);
      expect(result.poemIds, isEmpty);
      expect(result.pendingCount, 6,
          reason: '不排期也要能报出还剩多少首，否则详情页拿不到进度');
    });

    test('定量为 0 或负数按「不排期」处理，不能变成「今天 0 首」', () {
      for (final target in <int>[0, -1]) {
        final result = PlanScheduler.today(
          plan(dailyTarget: target),
          studiedIds: const {},
          now: day,
        );
        expect(result.hasSchedule, isFalse, reason: 'target=$target');
      }
    });

    test('起始日在未来时不派任务', () {
      final result = PlanScheduler.today(
        plan(dailyTarget: 2, startDate: '2026-10-01'),
        studiedIds: const {},
        now: day,
      );
      expect(result.notStartedYet, isTrue);
      expect(result.poemIds, isEmpty);
      expect(result.hasSchedule, isTrue);
    });

    test('起始日就是今天（或更早）时正常派任务', () {
      for (final start in <String>['2026-09-16', '2026-01-01']) {
        final result = PlanScheduler.today(
          plan(dailyTarget: 2, startDate: start),
          studiedIds: const {},
          now: day,
        );
        expect(result.notStartedYet, isFalse, reason: 'start=$start');
        expect(result.poemIds, [1, 2]);
      }
    });

    test('从未学过的篇目保持计划中的原顺序；重复 id 只算一次', () {
      final p = plan(ids: const [5, 3, 5, 1], dailyTarget: 4);
      final result = PlanScheduler.today(p, studiedIds: {3}, now: day);
      expect(result.poemIds, [5, 1]);
      expect(PlanScheduler.progress(p, {3}).total, 3,
          reason: '进度里的总数也应当去重');
    });
  });

  group('进度与估算', () {
    test('进度：已学 / 总数（去重）', () {
      final p = plan(ids: const [1, 2, 3, 4], dailyTarget: 2);
      final progress = PlanScheduler.progress(p, {1, 3, 99});
      expect(progress.done, 2, reason: '99 不在计划里，不该被算进来');
      expect(progress.total, 4);
      expect(progress.remaining, 2);
      expect(progress.ratio, 0.5);
    });

    test('估算完成日 = 剩余 ÷ 每日定量，向上取整', () {
      final p = plan(ids: const [1, 2, 3, 4, 5], dailyTarget: 2);
      final eta = PlanScheduler.estimateFinishDate(p, studiedIds: {1}, now: day);
      expect(eta, DateTime(2026, 9, 18), reason: '剩 4 首、每天 2 首 → 两天后');
    });

    test('没有定量、或已学完时不估算', () {
      expect(
        PlanScheduler.estimateFinishDate(plan(), studiedIds: const {}, now: day),
        isNull,
      );
      expect(
        PlanScheduler.estimateFinishDate(
          plan(ids: const [1], dailyTarget: 2),
          studiedIds: {1},
          now: day,
        ),
        isNull,
      );
    });

    test('日期键固定为 YYYY-MM-DD（与数据库里的 start_date 同格式）', () {
      expect(PlanScheduler.dateKey(DateTime(2026, 9, 6)), '2026-09-06');
      expect(PlanScheduler.dateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
