import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/s2t_converter.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/presentation/widgets/poem_parallel_card.dart';
import 'package:shici_yaji/presentation/widgets/poem_vertical_body.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolated_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('竖排阅读模式', () {
    test('枚举含三种读法', () {
      expect(PoemReadingMode.values.length, 3);
      expect(PoemReadingMode.vertical.label, '竖排');
      expect(PoemReadingMode.vertical.hint, isNotEmpty);
      expect(PoemReadingModeStore.fallback, PoemReadingMode.plain);
    });

    test('竖排正文按行拆列', () {
      const body = PoemVerticalBody(
        content: '床前明月光\n疑是地上霜',
        fontSize: 18,
        fontFamily: 'serif',
        textColor: Color(0xFF222222),
      );
      expect(body.content.split('\n').length, 2);
    });

    test('繁简偏好开关可切换', () {
      S2TConverter.preferTraditional = true;
      expect(S2TConverter.apply('云想衣裳'), isNot('云想衣裳'));
      S2TConverter.preferTraditional = false;
      expect(S2TConverter.apply('云想衣裳'), '云想衣裳');
    });
  });

  group('节气/节日预设计划', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('ensurePresetPlans 创建基础计划与专题计划，且幂等', () async {
      final iso = await openIsolatedTestDatabase('vertical_topic_plans');
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
      await db.insert('categories', {
        'id': 12,
        'name': '节日',
        'type': '题材',
        'icon': 'celebration',
        'sort_order': 12,
      });
      await db.insert('poems', {
        'id': 1,
        'title': '静夜思',
        'content': '床前明月光，疑是地上霜。',
        'dynasty_id': 1,
        'sort_order': 1,
      });
      await db.insert('poems', {
        'id': 2,
        'title': '清明',
        'content': '清明时节雨纷纷。',
        'dynasty_id': 1,
        'sort_order': 2,
      });
      await db.insert('poem_categories', {'poem_id': 1, 'category_id': 1});
      await db.insert('poem_categories', {'poem_id': 2, 'category_id': 12});

      await DatabaseHelper.ensurePresetPlans();
      await DatabaseHelper.ensurePresetPlans();

      final plans = await db.query('study_plans', orderBy: 'id');
      final names = plans.map((p) => p['name'] as String).toList();
      expect(names, contains('唐诗三百首'));
      expect(names, contains('小学必背'));
      expect(names, contains('节日诗选'));
      expect(names, contains('清明'));
      expect(names.where((n) => n == '清明').length, 1, reason: '应幂等');

      final festival = plans.firstWhere((p) => p['name'] == '节日诗选');
      expect(festival['poem_ids'], contains('2'));

      await iso.dispose();
    });
  });
}
