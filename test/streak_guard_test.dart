import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/streak_guard.dart';

/// 打卡韧性的**纯逻辑**测试：连续天数、可覆盖判定、月度冻结额度、补签卡发放。
///
/// 这一层不碰数据库、不读系统时钟（`today` 由用例传入），因此完全确定。
DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  final today = d(2026, 9, 19);
  DateTime ago(int days) => today.subtract(Duration(days: days));

  group('连续天数计算', () {
    test('没有任何记录 → 0', () {
      expect(
        StreakGuard.currentStreak(studied: {}, covered: {}, today: today),
        0,
      );
    });

    test('今天与昨天都学了 → 2', () {
      expect(
        StreakGuard.currentStreak(
          studied: {today, ago(1)},
          covered: const <DateTime>{},
          today: today,
        ),
        2,
      );
    });

    test('今天还没学、昨天学了 → 仍算 1（允许今天尚未学习）', () {
      expect(
        StreakGuard.currentStreak(
          studied: {ago(1)},
          covered: const <DateTime>{},
          today: today,
        ),
        1,
      );
    });

    test('时分秒不影响判定（按天归一）', () {
      expect(
        StreakGuard.currentStreak(
          studied: {DateTime(2026, 9, 19, 23, 59)},
          covered: const <DateTime>{},
          today: DateTime(2026, 9, 19, 0, 1),
        ),
        1,
      );
    });

    test('覆盖日参与计算：把断档补上后连续天数接回', () {
      // 今天、前天有真实记录，昨天是空档
      final studied = {today, ago(2)};
      expect(
        StreakGuard.currentStreak(
            studied: studied, covered: const <DateTime>{}, today: today),
        1,
      );
      expect(
        StreakGuard.currentStreak(
            studied: studied, covered: {ago(1)}, today: today),
        3,
      );
    });
  });

  group('可覆盖判定', () {
    test('今天与未来不可覆盖', () {
      expect(
        StreakGuard.canCover(
            day: today, studied: {}, covered: const <DateTime>{}, today: today),
        isFalse,
      );
      expect(
        StreakGuard.canCover(
            day: today.add(const Duration(days: 1)),
            studied: {},
            covered: const <DateTime>{},
            today: today),
        isFalse,
      );
    });

    test('当天已有真实打卡 → 不可覆盖', () {
      expect(
        StreakGuard.canCover(
            day: ago(1), studied: {ago(1)}, covered: const <DateTime>{}, today: today),
        isFalse,
      );
    });

    test('已被覆盖过 → 不可重复覆盖', () {
      expect(
        StreakGuard.canCover(
            day: ago(1), studied: {}, covered: {ago(1)}, today: today),
        isFalse,
      );
    });

    test('昨天是空档 → 可覆盖', () {
      expect(
        StreakGuard.canCover(
            day: ago(1), studied: {}, covered: const <DateTime>{}, today: today),
        isTrue,
      );
    });
  });

  group('月度冻结额度', () {
    test('本月未用 → 满额', () {
      expect(
        StreakGuard.freezesLeftThisMonth(
            today: today, freezesUsed: const <DateTime>{}),
        StreakGuard.freezesPerMonth,
      );
    });

    test('用掉 1 次 → 少 1 次', () {
      expect(
        StreakGuard.freezesLeftThisMonth(today: today, freezesUsed: {d(2026, 9, 10)}),
        StreakGuard.freezesPerMonth - 1,
      );
    });

    test('上个月的用量不占本月额度（跨月重置）', () {
      expect(
        StreakGuard.freezesLeftThisMonth(
            today: today, freezesUsed: {d(2026, 8, 30), d(2026, 8, 31)}),
        StreakGuard.freezesPerMonth,
      );
    });

    test('用超也不会变负', () {
      expect(
        StreakGuard.freezesLeftThisMonth(
            today: today,
            freezesUsed: {d(2026, 9, 1), d(2026, 9, 2), d(2026, 9, 3)}),
        0,
      );
    });
  });

  group('补签卡发放', () {
    test('连续不足一个周期 → 不发', () {
      final r = StreakGuard.grantRepairCards(
          streakDays: StreakGuard.repairCardEveryStreak - 1,
          grantedMilestones: const <String>{},
          repairCards: StreakGuard.initialRepairCards);
      expect(r.repairCards, StreakGuard.initialRepairCards);
      expect(r.newlyGranted, isEmpty);
    });

    test('达成一个周期 → +1 并记录里程碑', () {
      final r = StreakGuard.grantRepairCards(
          streakDays: 7,
          grantedMilestones: const <String>{},
          repairCards: StreakGuard.initialRepairCards);
      expect(r.repairCards, StreakGuard.initialRepairCards + 1);
      expect(r.newlyGranted, {'streak_7'});
    });

    test('同一里程碑只发一次', () {
      final r = StreakGuard.grantRepairCards(
          streakDays: 7,
          grantedMilestones: const {'streak_7'},
          repairCards: StreakGuard.initialRepairCards + 1);
      expect(r.repairCards, StreakGuard.initialRepairCards + 1);
      expect(r.newlyGranted, isEmpty);
    });

    test('一次跨多个里程碑，但封顶不超上限', () {
      final r = StreakGuard.grantRepairCards(
          streakDays: 21,
          grantedMilestones: const <String>{},
          repairCards: StreakGuard.initialRepairCards);
      expect(r.repairCards, StreakGuard.maxRepairCards);
      expect(r.newlyGranted, contains('streak_7'));
      expect(r.newlyGranted, contains('streak_14'));
    });

    test('已达上限 → 不再发', () {
      final r = StreakGuard.grantRepairCards(
          streakDays: 14,
          grantedMilestones: const <String>{},
          repairCards: StreakGuard.maxRepairCards);
      expect(r.repairCards, StreakGuard.maxRepairCards);
      expect(r.newlyGranted, isEmpty);
    });
  });
}
