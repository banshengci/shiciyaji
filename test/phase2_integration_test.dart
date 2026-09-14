import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/data/models/achievement.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database _db;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _seed(_db);
  });

  tearDown(() => DatabaseHelper.resetForTesting());

  // ═══════════════════════════════════════════════════════════
  // Phase 2 端到端集成测试：学习→打卡→统计→成就全流程
  // ═══════════════════════════════════════════════════════════

  group('Phase 2 全流程集成', () {
    test('1. 学习→打卡→统计 基础流程', () async {
      // 初始状态
      expect(await DatabaseHelper.getStudiedCount(), 0);
      expect(await DatabaseHelper.getStreakDays(), 0);

      // 标记学习 3 首
      await DatabaseHelper.markPoemStudied(1, status: '学习中');
      await DatabaseHelper.markPoemStudied(2, status: '学习中');
      await DatabaseHelper.markPoemStudied(3, status: '已掌握');

      expect(await DatabaseHelper.getStudiedCount(), 3);
      expect(await DatabaseHelper.getStreakDays(), 1); // 今天打卡了

      // study_records 应有 3 条
      final records = await DatabaseHelper.getStudyRecords();
      expect(records.length, 3);
    });

    test('2. 连续打卡 streak 验证（模拟多日）', () async {
      // 模拟连续 3 天学习
      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        final date = today.subtract(Duration(days: 2 - i));
        final dateStr = date.toIso8601String().substring(0, 10);
        await _db.insert('study_records', {
          'poem_id': i + 1,
          'study_date': dateStr,
          'status': '学习中',
        });
      }
      expect(await DatabaseHelper.getStudiedCount(), 3);
      expect(await DatabaseHelper.getStreakDays(), 3);

      // 热力图数据
      final heatmap = await DatabaseHelper.getStudyDatesCount();
      expect(heatmap.length, 3);
    });

    test('3. 笔记→统计 联动', () async {
      // 学习 2 首诗 + 写 3 条笔记（2 首在第 1 首诗，1 首在第 2 首）
      await DatabaseHelper.markPoemStudied(1);
      await DatabaseHelper.markPoemStudied(2);

      await DatabaseHelper.addNote(1, '静夜思的月光意象分析');
      await DatabaseHelper.addNote(1, '李白思乡之情');
      await DatabaseHelper.addNote(2, '望庐山瀑布的夸张手法');

      expect(await DatabaseHelper.getNotesCount(), 3);
      expect(await DatabaseHelper.getNotedPoemsCount(), 2);

      // 按诗查询笔记
      final notesPoem1 = await DatabaseHelper.getNotesByPoem(1);
      expect(notesPoem1.length, 2);
      expect(notesPoem1.every((n) => n.poemTitle == '静夜思'), isTrue);

      // 全量笔记含诗词信息
      final allNotes = await DatabaseHelper.getAllNotes();
      expect(allNotes.length, 3);
      expect(allNotes.every((n) => n.poemTitle != null), isTrue);
      expect(allNotes.every((n) => n.authorName == '李白'), isTrue);
    });

    test('4. 收藏→统计 联动', () async {
      // 收藏 3 首诗
      await DatabaseHelper.addFavorite(1);
      await DatabaseHelper.addFavorite(2);
      await DatabaseHelper.addFavorite(3);

      expect(await DatabaseHelper.getFavoriteCount(), 3);
      expect(await DatabaseHelper.isFavorite(1), isTrue);
      expect(await DatabaseHelper.isFavorite(4), isFalse);

      // 收藏列表
      final favPoems = await DatabaseHelper.getFavoritePoems();
      expect(favPoems.length, 3);

      // 取消收藏
      await DatabaseHelper.removeFavorite(1);
      expect(await DatabaseHelper.getFavoriteCount(), 2);
      expect(await DatabaseHelper.isFavorite(1), isFalse);
    });

    test('5. 收藏夹分组管理', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗精选');
      await DatabaseHelper.addFavorite(2, collection: '唐诗精选');
      await DatabaseHelper.addFavorite(3, collection: '必背');

      final collections = await DatabaseHelper.getCollections();
      expect(collections.any((c) => c['name'] == '唐诗精选'), isTrue);
      expect(collections.any((c) => c['name'] == '必背'), isTrue);

      // 按收藏夹查询
      final tangShi = await DatabaseHelper.getFavoritePoemsByCollection('唐诗精选');
      expect(tangShi.length, 2);

      // 重命名收藏夹
      await DatabaseHelper.renameCollection('唐诗精选', '唐诗必读');
      final renamed = await DatabaseHelper.getFavoritePoemsByCollection('唐诗必读');
      expect(renamed.length, 2);
      final oldName = await DatabaseHelper.getFavoritePoemsByCollection('唐诗精选');
      expect(oldName, isEmpty);

      // 删除收藏夹（级联移除收藏）
      await DatabaseHelper.deleteCollection('必背');
      expect(await DatabaseHelper.getFavoriteCount(), 2); // 唐诗必读的 2 条仍在
    });

    test('6. 阅读历史', () async {
      await DatabaseHelper.addReadingHistory(1);
      await DatabaseHelper.addReadingHistory(2);
      await DatabaseHelper.addReadingHistory(3);

      expect(await DatabaseHelper.getReadingHistoryCount(), 3);

      final history = await DatabaseHelper.getReadingHistory();
      expect(history.length, 3);
      // 最近阅读的排前面
      expect(history.first.id, 3);
    });

    test('7. 统计图表数据', () async {
      // 学习 3 首
      await DatabaseHelper.markPoemStudied(1);
      await DatabaseHelper.markPoemStudied(2);
      await DatabaseHelper.markPoemStudied(3);

      // 朝代分布（全部唐代）
      final dynastyDist = await DatabaseHelper.getStudiedDynastyDistribution();
      expect(dynastyDist['唐'], 3);

      // 作者分布
      final authorDist = await DatabaseHelper.getStudiedAuthorDistribution();
      expect(authorDist['李白'], 3);
    });

    test('8. 艾宾浩斯复习调度', () async {
      // 模拟 2 天前学习第 1 首（review_count=1，下次复习=+1天 → 昨天 → 今天应该复习）
      final twoDaysAgo = DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .substring(0, 10);
      await _db.insert('study_records', {
        'poem_id': 1,
        'study_date': twoDaysAgo,
        'status': '学习中',
      });

      // 今天应该有 1 首待复习
      final reviewItems = await DatabaseHelper.getTodayReviewItems();
      expect(reviewItems.length, 1);
      expect(reviewItems.first['title'], '静夜思');
      expect(reviewItems.first['review_count'], 1);

      // 复习计数
      expect(await DatabaseHelper.getTodayReviewCount(), 1);

      // 模拟今天复习 → review_count 变为 2，下次复习=+2天
      await DatabaseHelper.markPoemStudied(1, status: '复习');
      // 今天复习后不应再出现在待复习列表（last_date == today）
      final afterReview = await DatabaseHelper.getTodayReviewItems();
      expect(afterReview, isEmpty);
    });

    test('9. 成就从零到逐步解锁全流程', () async {
      // 初始：0 解锁
      var stats = const AchievementStats(totalPoems: 5);
      expect(Achievements.unlockedCount(stats), 0);

      // 学习 1 首 → 解锁 learning_1
      await DatabaseHelper.markPoemStudied(1);
      stats = AchievementStats(
        studiedCount: await DatabaseHelper.getStudiedCount(),
        totalPoems: 5,
      );
      expect(stats.studiedCount, 1);
      expect(Achievements.unlockedCount(stats), 1);
      final r1 = Achievements.evaluateAll(stats);
      expect(r1.unlocked.first.id, 'learning_1');

      // 再学 4 首（共 5 首 = 全部）→ 解锁 learning_2(7) + learning_5(全部)
      // 但只有 5 首诗，learning_2 threshold=7，studiedCount=5 < 7，未解锁
      // learning_5：studiedCount(5) >= totalPoems(5) → 解锁
      for (var i = 2; i <= 5; i++) {
        await DatabaseHelper.markPoemStudied(i);
      }
      stats = AchievementStats(
        studiedCount: await DatabaseHelper.getStudiedCount(),
        totalPoems: 5,
      );
      expect(stats.studiedCount, 5);
      // 解锁：learning_1(>=1), learning_5(全部) = 2 个
      // learning_2(>=7) 未达, learning_3(>=14) 未达, learning_4(>=21) 未达
      expect(Achievements.unlockedCount(stats), 2);

      // 写 10 条笔记 → 解锁 notes_1
      for (var i = 0; i < 10; i++) {
        await DatabaseHelper.addNote(1, '笔记 $i');
      }
      stats = AchievementStats(
        studiedCount: await DatabaseHelper.getStudiedCount(),
        notesCount: await DatabaseHelper.getNotesCount(),
        totalPoems: 5,
      );
      expect(stats.notesCount, 10);
      // 解锁：learning_1, learning_5, notes_1 = 3
      expect(Achievements.unlockedCount(stats), 3);

      // 连续 7 天 → 解锁 streak_1
      final today = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final date = today.subtract(Duration(days: 6 - i));
        await _db.insert('study_records', {
          'poem_id': 1,
          'study_date': date.toIso8601String().substring(0, 10),
          'status': '复习',
        });
      }
      stats = AchievementStats(
        studiedCount: await DatabaseHelper.getStudiedCount(),
        notesCount: await DatabaseHelper.getNotesCount(),
        streakDays: await DatabaseHelper.getStreakDays(),
        totalPoems: 5,
      );
      expect(stats.streakDays, 7);
      // 解锁：learning_1, learning_5, notes_1, streak_1 = 4
      expect(Achievements.unlockedCount(stats), 4);

      // 收藏 20 首（数据库只有 5 首，但可以重复 addFavorite 不同诗）
      // 由于只有 5 首诗，先 addFavorite 5 首
      for (var i = 1; i <= 5; i++) {
        await DatabaseHelper.addFavorite(i);
      }
      stats = AchievementStats(
        studiedCount: await DatabaseHelper.getStudiedCount(),
        notesCount: await DatabaseHelper.getNotesCount(),
        streakDays: await DatabaseHelper.getStreakDays(),
        favoriteCount: await DatabaseHelper.getFavoriteCount(),
        totalPoems: 5,
      );
      expect(stats.favoriteCount, 5);
      // fav_1 需要 20，只有 5，未解锁
      // 总解锁仍为 4
      expect(Achievements.unlockedCount(stats), 4);
    });

    test('10. 全部解锁边界验证', () {
      // 构造全满数据快照
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
      expect(result.unlocked.length, 10);
    });

    test('11. 数据导出边界（笔记+收藏联动查询）', () async {
      // 准备数据
      await DatabaseHelper.addNote(1, '导出测试笔记1');
      await DatabaseHelper.addNote(2, '导出测试笔记2');
      await DatabaseHelper.addFavorite(1, collection: '导出测试夹');

      // 全量笔记可按关键词搜索（模拟导出时筛选）
      final searched = await DatabaseHelper.getAllNotes(keyword: '导出');
      expect(searched.length, 2);

      // 收藏夹列表完整
      final collections = await DatabaseHelper.getCollections();
      expect(collections.any((c) => c['name'] == '导出测试夹'), isTrue);

      // 按收藏夹查询诗词
      final poems = await DatabaseHelper.getFavoritePoemsByCollection('导出测试夹');
      expect(poems.length, 1);
      expect(poems.first.title, '静夜思');
    });
  });
}

Future<void> _seed(Database db) async {
  final batch = db.batch();
  batch.rawInsert('INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)', ['唐']);
  batch.rawInsert('INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)', ['李白']);
  // 5 首诗，前 2 首有真实标题（测试中考验标题匹配）
  final titles = ['静夜思', '望庐山瀑布', '赠汪伦', '早发白帝城', '独坐敬亭山'];
  final contents = [
    '床前明月光\n疑是地上霜',
    '日照香炉生紫烟\n遥看瀑布挂前川',
    '李白乘舟将欲行',
    '朝辞白帝彩云间',
    '众鸟高飞尽',
  ];
  for (var i = 0; i < 5; i++) {
    batch.rawInsert(
      'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
      [i + 1, titles[i], contents[i], i + 1],
    );
  }
  await batch.commit();
}
