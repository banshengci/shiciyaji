import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/core/achievement_service.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/data/models/achievement.dart';

late Database _db;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _seed();
    AchievementService.instance.resetForTesting();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  /// 在测试内订阅解锁事件流，返回 (已接收列表, 取消函数)
  (List<Achievement>, StreamSubscription<Achievement>) collectEvents() {
    final received = <Achievement>[];
    final sub = AchievementService.instance.onUnlock.listen(received.add);
    return (received, sub);
  }

  group('AchievementService - 基线建立与广播', () {
    test('init() 满足的成就直接标记，但不弹横幅（基线不骚扰）', () async {
      final (received, sub) = collectEvents();
      addTearDown(sub.cancel);

      // 种子数据：studiedCount=1（满足 learning_1）、notes=10（满足 notes_1）
      await AchievementService.instance.init();

      // 已解锁集合里应包含这两个
      expect(AchievementService.instance.unlockedIds,
          containsAll(['learning_1', 'notes_1']));
      // 但因为没有"新解锁"，baseline 阶段不应有任何广播
      expect(received, isEmpty);
    });

    test('sync() 触发新解锁时广播，并持久化到 SharedPreferences', () async {
      final (received, sub) = collectEvents();
      addTearDown(sub.cancel);

      // 先建基线：仅 studiedCount=1（learning_1 已解锁），notes=0
      await _resetDbOnlyStudied();
      AchievementService.instance.resetForTesting();
      await AchievementService.instance.init();
      received.clear();

      // 用户写笔记 → notes 达到 10，notes_1 成为"新解锁"
      await _addNotes(10);
      await AchievementService.instance.sync();

      // 应只有 notes_1 被广播
      expect(received.map((a) => a.id), contains('notes_1'));
      expect(received.length, 1);

      // 持久化：再次 init 不应重复广播（基线逻辑）
      AchievementService.instance.resetForTesting();
      received.clear();
      await AchievementService.instance.init();
      expect(received, isEmpty);
    });

    test('多个成就同时解锁时，事件流逐个发射', () async {
      final received = <Achievement>[];
      final sub = AchievementService.instance.onUnlock.listen(received.add);
      addTearDown(sub.cancel);

      // 种子仅 studiedCount=1
      await _resetDbOnlyStudied();
      AchievementService.instance.resetForTesting();
      await AchievementService.instance.init();
      received.clear();

      // 一次性把 notes 加到 10 且 收藏加到 20 → 同时解锁 notes_1 与 fav_1
      await _addNotes(10);
      await _addFavorites(20);
      await AchievementService.instance.sync();

      final ids = received.map((a) => a.id).toSet();
      expect(ids, containsAll(['notes_1', 'fav_1']));
      expect(ids, isNot(contains('learning_1'))); // 已解锁过，不重复
    });

    test('init 幂等：多次 init 不会重复纳入或广播', () async {
      final (received, sub) = collectEvents();
      addTearDown(sub.cancel);

      await AchievementService.instance.init();
      final afterFirst = AchievementService.instance.unlockedIds.length;
      await AchievementService.instance.init();
      expect(AchievementService.instance.unlockedIds.length, afterFirst);
      expect(received, isEmpty);
    });
  });
}

/// 种子：dynasty/author/poem 各一条，外加 studied=1、notes=10、fav=0
Future<void> _seed() async {
  final batch = _db.batch();
  batch.rawInsert(
      'INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)',
      ['唐']);
  batch.rawInsert(
      'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)',
      ['李白']);
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [1, '静夜思', '床前明月光，疑是地上霜。', 1],
  );
  batch.rawInsert(
      'INSERT OR IGNORE INTO study_records (poem_id, study_date) VALUES (?, ?)',
      [1, '2026-01-01']);
  for (var i = 0; i < 10; i++) {
    batch.rawInsert(
        'INSERT OR IGNORE INTO study_notes (poem_id, content, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [1, 'note $i', '2026-01-01T00:00:0$i', '2026-01-01T00:00:0$i']);
  }
  await batch.commit();
}

/// 仅保留 studied=1（清空 study_notes/favorites/study_records）
Future<void> _resetDbOnlyStudied() async {
  await _db.delete('study_notes');
  await _db.delete('favorites');
  await _db.delete('study_records');
  await _db.insert('study_records', {
    'poem_id': 1,
    'study_date': '2026-01-01',
  });
}

Future<void> _addNotes(int n) async {
  for (var i = 0; i < n; i++) {
    await _db.insert('study_notes', {
      'poem_id': 1,
      'content': 'new note $i',
      'created_at': '2026-02-0${i % 9 + 1}T00:00:00',
      'updated_at': '2026-02-0${i % 9 + 1}T00:00:00',
    });
  }
}

Future<void> _addFavorites(int n) async {
  for (var i = 0; i < n; i++) {
    await _db.insert('favorites', {
      'poem_id': 1,
    });
  }
}
