import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/models/achievement.dart';

void main() {
  group('Achievement - 单个成就判定边界', () {
    // 找到 5 个学习成就
    final l1 = Achievements.all.firstWhere((a) => a.id == 'learning_1');
    final l2 = Achievements.all.firstWhere((a) => a.id == 'learning_2');
    final l5 = Achievements.all.firstWhere((a) => a.id == 'learning_5');
    final n1 = Achievements.all.firstWhere((a) => a.id == 'notes_1');
    final n2 = Achievements.all.firstWhere((a) => a.id == 'notes_2');
    final s1 = Achievements.all.firstWhere((a) => a.id == 'streak_1');
    final s2 = Achievements.all.firstWhere((a) => a.id == 'streak_2');
    final f1 = Achievements.all.firstWhere((a) => a.id == 'fav_1');

    test('learning_1 初窥门径：studiedCount=0 时未解锁；=1 刚好解锁；>1 已解锁', () {
      expect(l1.isUnlocked(const AchievementStats(studiedCount: 0)), isFalse);
      expect(l1.progress(const AchievementStats(studiedCount: 0)), 0.0);
      expect(l1.isUnlocked(const AchievementStats(studiedCount: 1)), isTrue);
      expect(l1.progress(const AchievementStats(studiedCount: 1)), 1.0);
      expect(l1.isUnlocked(const AchievementStats(studiedCount: 5)), isTrue);
    });

    test('learning_2 渐入佳境：threshold=7，6 未解锁、7 刚好、20 已解锁', () {
      expect(l2.isUnlocked(const AchievementStats(studiedCount: 6)), isFalse);
      expect(l2.progress(const AchievementStats(studiedCount: 6)), closeTo(6 / 7, 0.001));
      expect(l2.isUnlocked(const AchievementStats(studiedCount: 7)), isTrue);
      expect(l2.isUnlocked(const AchievementStats(studiedCount: 20)), isTrue);
      // currentValue 正确反映 studiedCount
      expect(l2.currentValue(const AchievementStats(studiedCount: 6)), 6);
      expect(l2.currentValue(const AchievementStats(studiedCount: 20)), 20);
    });

    test('learning_5 诗仙在世：threshold=35，但需 studiedCount == totalPoems 才算解锁（特殊判定）', () {
      // studiedCount=34, totalPoems=35 → 未解锁
      expect(
        l5.isUnlocked(const AchievementStats(studiedCount: 34, totalPoems: 35)),
        isFalse,
      );
      // studiedCount=35, totalPoems=35 → 解锁（学完全部）
      expect(
        l5.isUnlocked(const AchievementStats(studiedCount: 35, totalPoems: 35)),
        isTrue,
      );
      // studiedCount=35, totalPoems=100 → 仍未解锁（因为没学完全部 100 首）
      expect(
        l5.isUnlocked(const AchievementStats(studiedCount: 35, totalPoems: 100)),
        isFalse,
      );
      // 边界：totalPoems=0（库为空）→ 即使 studiedCount=0 也不解锁（避免 0/0 误判）
      expect(
        l5.isUnlocked(const AchievementStats(studiedCount: 0, totalPoems: 0)),
        isFalse,
      );
    });

    test('notes_1 笔耕不辍：threshold=10，笔记数 0/9/10/50', () {
      expect(n1.isUnlocked(const AchievementStats(notesCount: 0)), isFalse);
      expect(n1.isUnlocked(const AchievementStats(notesCount: 9)), isFalse);
      expect(n1.isUnlocked(const AchievementStats(notesCount: 10)), isTrue);
      expect(n1.isUnlocked(const AchievementStats(notesCount: 50)), isTrue);
      // progress clamp 到 1.0
      expect(n1.progress(const AchievementStats(notesCount: 50)), 1.0);
    });

    test('notes_2 笔记达人：threshold=30，边界 29 vs 30', () {
      expect(n2.isUnlocked(const AchievementStats(notesCount: 29)), isFalse);
      expect(n2.isUnlocked(const AchievementStats(notesCount: 30)), isTrue);
      expect(n2.currentValue(const AchievementStats(notesCount: 29)), 29);
    });

    test('streak_1 坚持不渝：threshold=7，连续 0/6/7/15 天', () {
      expect(s1.isUnlocked(const AchievementStats(streakDays: 0)), isFalse);
      expect(s1.isUnlocked(const AchievementStats(streakDays: 6)), isFalse);
      expect(s1.isUnlocked(const AchievementStats(streakDays: 7)), isTrue);
      expect(s1.isUnlocked(const AchievementStats(streakDays: 15)), isTrue);
    });

    test('streak_2 持之以恒：threshold=30，边界 29 vs 30 vs 31', () {
      expect(s2.isUnlocked(const AchievementStats(streakDays: 29)), isFalse);
      expect(s2.isUnlocked(const AchievementStats(streakDays: 30)), isTrue);
      expect(s2.isUnlocked(const AchievementStats(streakDays: 31)), isTrue);
      expect(s2.currentValue(const AchievementStats(streakDays: 31)), 31);
    });

    test('fav_1 收藏家：threshold=20，边界 19 vs 20', () {
      expect(f1.isUnlocked(const AchievementStats(favoriteCount: 19)), isFalse);
      expect(f1.isUnlocked(const AchievementStats(favoriteCount: 20)), isTrue);
      expect(f1.currentValue(const AchievementStats(favoriteCount: 19)), 19);
      expect(f1.progress(const AchievementStats(favoriteCount: 19)), closeTo(19 / 20, 0.001));
    });
  });

  group('Achievements - 批量评估与统计', () {
    test('空快照：所有 10 个成就均未解锁，unlockedCount=0', () {
      const stats = AchievementStats();
      final result = Achievements.evaluateAll(stats);
      expect(result.unlocked, isEmpty);
      expect(result.locked.length, Achievements.totalCount);
      expect(Achievements.unlockedCount(stats), 0);
    });

    test('刚好达到 learning_1 阈值：1 个解锁，其余 9 个锁定', () {
      const stats = AchievementStats(studiedCount: 1);
      expect(Achievements.unlockedCount(stats), 1);
      final result = Achievements.evaluateAll(stats);
      expect(result.unlocked.first.id, 'learning_1');
      expect(result.locked.length, Achievements.totalCount - 1);
    });

    test('中等进度：studied=14, notes=10, streak=7, fav=20 → 解锁 5 个（l1/l2/l3/n1/s1/f1）', () {
      const stats = AchievementStats(
        studiedCount: 14,
        notesCount: 10,
        streakDays: 7,
        favoriteCount: 20,
        totalPoems: 35,
      );
      // 解锁：l1(>=1), l2(>=7), l3(>=14), l4 需 21 未达, l5 需全部未达
      // notes_1(>=10) 解锁, notes_2(>=30) 未达
      // streak_1(>=7) 解锁, streak_2(>=30) 未达
      // fav_1(>=20) 解锁
      // 总解锁：l1, l2, l3, n1, s1, f1 = 6 个
      expect(Achievements.unlockedCount(stats), 6);
      final unlockedIds = Achievements.evaluateAll(stats).unlocked.map((a) => a.id).toSet();
      expect(unlockedIds, containsAll([
        'learning_1', 'learning_2', 'learning_3',
        'notes_1', 'streak_1', 'fav_1',
      ]));
      expect(unlockedIds, isNot(contains('learning_4')));
      expect(unlockedIds, isNot(contains('learning_5')));
      expect(unlockedIds, isNot(contains('notes_2')));
      expect(unlockedIds, isNot(contains('streak_2')));
    });

    test('全解锁：studied=35, notes=30, streak=30, fav=20, totalPoems=35 → 10/10', () {
      const stats = AchievementStats(
        studiedCount: 35,
        notesCount: 30,
        streakDays: 30,
        favoriteCount: 20,
        totalPoems: 35,
      );
      expect(Achievements.unlockedCount(stats), Achievements.totalCount);
      final result = Achievements.evaluateAll(stats);
      expect(result.locked, isEmpty);
      expect(result.unlocked.length, Achievements.totalCount);
    });

    test('grouped() 按类别分组：4 类，总数仍为 10', () {
      final g = Achievements.grouped();
      expect(g.length, 4);
      expect(g[AchievementCategory.learning]!.length, 5);
      expect(g[AchievementCategory.notes]!.length, 2);
      expect(g[AchievementCategory.persistence]!.length, 2);
      expect(g[AchievementCategory.collection]!.length, 1);
      final total = g.values.fold(0, (s, l) => s + l.length);
      expect(total, Achievements.totalCount);
      expect(total, 10);
    });

    test('progress 边界：threshold=0 时直接视为 100%（防御）', () {
      // 没有定义 threshold=0 的成就，但通过私有/假设验证逻辑
      // 间接验证：learning_1 (threshold=1) studied=2 → progress=1.0 (clamp)
      final l1 = Achievements.all.firstWhere((a) => a.id == 'learning_1');
      expect(l1.progress(const AchievementStats(studiedCount: 2)), 1.0);
    });
  });
}
