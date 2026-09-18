import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/tts_play_queue.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolated_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('听诗连播队列', () {
    test('item.speechText 为「标题。正文」', () {
      const item = TtsQueueItem(
        poemId: 1,
        title: '静夜思',
        content: '床前明月光',
      );
      expect(item.speechText, '静夜思。床前明月光');
    });

    test('start 后队列索引与标签正确（不依赖真实 TTS 播完）', () async {
      final items = [
        for (var i = 0; i < 3; i++)
          TtsQueueItem(poemId: i, title: '诗$i', content: '正文$i'),
      ];
      final q = TtsPlayQueue.instance;
      // 不真正依赖 TTS 引擎：start 会调 speak，在测试环境可能立刻失败，
      // 但队列结构应先就位
      await q.start(items, from: 1, label: '单元计划');
      expect(q.hasQueue, isTrue);
      expect(q.items.length, 3);
      expect(q.index, 1);
      expect(q.label, '单元计划');
      expect(q.current?.title, '诗1');
      await q.clear();
      expect(q.hasQueue, isFalse);
      expect(q.label, '');
    });

    test('previous / next 越界保护', () async {
      final q = TtsPlayQueue.instance;
      await q.start(
        [
          TtsQueueItem(poemId: 1, title: 'A', content: 'a'),
          TtsQueueItem(poemId: 2, title: 'B', content: 'b'),
        ],
        label: 't',
      );
      await q.pause();
      await q.previous();
      expect(q.index, 0);
      await q.next();
      expect(q.index, 1);
      await q.next(); // 到末尾再 next 应停止
      expect(q.isPlaying, isFalse);
      await q.clear();
    });
  });

  group('教材同步预设计划', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('小学包切段 + 必背主题会生成教材同步计划', () async {
      final iso = await openIsolatedTestDatabase('textbook_plans');
      final db = iso.db;
      await DatabaseHelper.setDatabaseForTesting(db);

      await db.execute(
          'CREATE TABLE IF NOT EXISTS dynasties (id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY, name TEXT, type TEXT, icon TEXT, sort_order INTEGER)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS poems (id INTEGER PRIMARY KEY, title TEXT, content TEXT, author_id INTEGER, dynasty_id INTEGER, type TEXT, notes TEXT, translation TEXT, appreciation TEXT, background TEXT, source TEXT, sort_order INTEGER)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS poem_categories (poem_id INTEGER, category_id INTEGER)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS study_plans (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, description TEXT, poem_ids TEXT, daily_target INTEGER, start_date TEXT)');

      await db.insert('dynasties', {'id': 1, 'name': '唐'});
      await db.insert('categories', {
        'id': 1,
        'name': '必背',
        'type': '学习',
        'icon': 'school',
        'sort_order': 1,
      });
      // 模拟小学包 id 段 10000+
      for (var i = 0; i < 30; i++) {
        final id = 10000 + i;
        await db.insert('poems', {
          'id': id,
          'title': i.isEven ? '山行$i' : '春晓$i',
          'content': i.isEven ? '远上寒山石径斜' : '春眠不觉晓',
          'dynasty_id': 1,
          'sort_order': i,
        });
        await db.insert('poem_categories',
            {'poem_id': id, 'category_id': 1});
      }

      await DatabaseHelper.ensurePresetPlans();
      await DatabaseHelper.ensurePresetPlans();

      final plans = await db.query('study_plans');
      final names = plans.map((p) => p['name'] as String).toList();
      expect(names, contains('教材同步 · 小学第1单元'));
      expect(names, contains('教材同步 · 小学第2单元'));
      expect(names.where((n) => n == '教材同步 · 小学第1单元').length, 1);

      final unit1 = plans.firstWhere(
          (p) => p['name'] == '教材同步 · 小学第1单元');
      final ids =
          (jsonDecode(unit1['poem_ids'] as String) as List).cast<int>();
      expect(ids.length, 25);
      expect(ids.first, 10000);

      await iso.dispose();
    });
  });
}
