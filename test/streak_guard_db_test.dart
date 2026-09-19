import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/core/streak_guard.dart';
import 'package:shici_yaji/data/database/database_helper.dart';

import 'support/isolated_db.dart';

/// 打卡韧性的**集成**测试：覆盖日真的能让 `getStreakDays()` 把断档接回、
/// 额度真的被扣、重复覆盖真的被拒。
///
/// 覆盖只写 SharedPreferences，不写 `study_records` —— 这里同时守住
/// 「不伪造学习记录」这条线。
late Database _db;
late IsolatedTestDb _iso;

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _iso = await openIsolatedTestDatabase('streak_guard_db');
    _db = _iso.db;
    await DatabaseHelper.setDatabaseForTesting(_db);
    // 最小可插入数据：朝代 / 作者 / 诗词（study_records 引用它们）
    await _db.insert('dynasties', {'id': 1, 'name': '唐', 'sort_order': 1});
    await _db.insert('authors', {'id': 1, 'name': '李白', 'dynasty_id': 1});
    await _db.insert('poems', {
      'id': 1,
      'title': '静夜思',
      'content': '床前明月光，疑是地上霜。',
      'author_id': 1,
      'dynasty_id': 1,
      'sort_order': 1,
    });
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    await _iso.dispose();
  });

  Future<void> study(DateTime day) async {
    await _db.insert('study_records', {
      'poem_id': 1,
      'study_date': _fmt(day),
      'status': '已掌握',
    });
  }

  test('无覆盖时，连续天数与真实记录一致', () async {
    final today = DateTime.now();
    await study(today);
    await study(today.subtract(const Duration(days: 1)));
    expect(await DatabaseHelper.getStreakDays(), 2);
  });

  test('补签昨天 → 连续天数接回，且补签卡真的被扣 1 张', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final dayBefore = today.subtract(const Duration(days: 2));
    await study(today);
    await study(dayBefore);
    expect(await DatabaseHelper.getStreakDays(), 1, reason: '昨天是断档，连续应为 1');

    final before = await DatabaseHelper.getStreakGuardState();
    expect(before.repairCards, StreakGuard.initialRepairCards);

    final res = await DatabaseHelper.coverDay(yesterday, useFreeze: false);
    expect(res.success, isTrue, reason: res.reason);
    expect(await DatabaseHelper.getStreakDays(), 3, reason: '断档补上后应接回 3 天');

    final after = await DatabaseHelper.getStreakGuardState();
    expect(after.repairCards, StreakGuard.initialRepairCards - 1);
    expect(after.repaired.contains(StreakGuard.dayOnly(yesterday)), isTrue);

    // 不伪造学习记录：study_records 里没有多出这一天
    final rows = await _db.query('study_records',
        where: 'study_date = ?', whereArgs: [_fmt(yesterday)]);
    expect(rows, isEmpty, reason: '覆盖不得写入 study_records');
  });

  test('冻结不消耗补签卡，但占用本月额度', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    await study(today);

    final res = await DatabaseHelper.coverDay(yesterday, useFreeze: true);
    expect(res.success, isTrue, reason: res.reason);

    final st = await DatabaseHelper.getStreakGuardState();
    expect(st.repairCards, StreakGuard.initialRepairCards, reason: '冻结不该扣卡');
    expect(st.frozen.contains(StreakGuard.dayOnly(yesterday)), isTrue);
    expect(
      StreakGuard.freezesLeftThisMonth(today: today, freezesUsed: st.frozen),
      StreakGuard.freezesPerMonth - 1,
    );
  });

  test('重复覆盖同一天被拒，且状态不变', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final first = await DatabaseHelper.coverDay(yesterday, useFreeze: false);
    expect(first.success, isTrue);

    final second = await DatabaseHelper.coverDay(yesterday, useFreeze: false);
    expect(second.success, isFalse);
    expect(second.reason, isNotEmpty);

    final st = await DatabaseHelper.getStreakGuardState();
    expect(st.repaired.length, 1);
    expect(st.repairCards, StreakGuard.initialRepairCards - 1,
        reason: '失败的那次不得扣卡');
  });

  test('不能覆盖今天', () async {
    final res = await DatabaseHelper.coverDay(DateTime.now(), useFreeze: false);
    expect(res.success, isFalse);
    expect(res.reason, contains('今天'));
  });

  test('当天已有真实打卡 → 不可覆盖', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await study(yesterday);
    final res = await DatabaseHelper.coverDay(yesterday, useFreeze: false);
    expect(res.success, isFalse);
  });

  test('冻结额度用尽后拒绝（每月上限）', () async {
    final today = DateTime.now();
    final days = List<DateTime>.generate(
        3, (i) => today.subtract(Duration(days: i + 1)));
    expect((await DatabaseHelper.coverDay(days[0], useFreeze: true)).success,
        isTrue);
    expect((await DatabaseHelper.coverDay(days[1], useFreeze: true)).success,
        isTrue);
    final third = await DatabaseHelper.coverDay(days[2], useFreeze: true);
    expect(third.success, isFalse);
    expect(third.reason, contains('冻结'));
  });

  test('候选空档日：排除今天、真实打卡日与被覆盖日', () async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final dayBefore = today.subtract(const Duration(days: 2));
    await study(dayBefore);
    await DatabaseHelper.coverDay(yesterday, useFreeze: false);

    final cands = await DatabaseHelper.getCandidateCoverDays(window: 7);
    final days = cands.map(StreakGuard.dayOnly).toSet();
    expect(days.contains(StreakGuard.dayOnly(today)), isFalse);
    expect(days.contains(StreakGuard.dayOnly(dayBefore)), isFalse);
    expect(days.contains(StreakGuard.dayOnly(yesterday)), isFalse);
  });

  test('补签卡按规则发放：连续 7 天 +1，且只发一次', () async {
    final today = DateTime.now();
    for (var i = 0; i < 7; i++) {
      await study(today.subtract(Duration(days: i)));
    }
    expect(await DatabaseHelper.getStreakDays(), 7);

    final n1 = await DatabaseHelper.grantRepairCardsIfDue(streakDays: 7);
    expect(n1, StreakGuard.initialRepairCards + 1);

    final n2 = await DatabaseHelper.grantRepairCardsIfDue(streakDays: 7);
    expect(n2, n1, reason: '同一里程碑不得重复发放');
  });
}
