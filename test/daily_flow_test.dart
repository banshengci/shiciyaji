import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/daily_flow.dart';
import 'package:shici_yaji/data/models/models.dart';

/// [buildDailyFlow] 是纯函数、无随机：同一份输入必须得到同一个次序，
/// 否则「一日一赏」分享出去的图在不同次打开会不一样（不可复现）。
Poem _p(int id, {int? authorId, int? dynastyId, String title = '诗'}) => Poem(
      id: id,
      title: title,
      content: '内容$id',
      authorId: authorId,
      dynastyId: dynastyId,
    );

void main() {
  test('首张必须是今日诗', () {
    final daily = _p(1, authorId: 10, dynastyId: 20);
    final all = <Poem>[
      daily,
      _p(2, authorId: 10, dynastyId: 20), // 同作者
      _p(3, authorId: 99, dynastyId: 20), // 同朝代
    ];
    final flow = buildDailyFlow(daily: daily, all: all);
    expect(flow.first.id, 1);
  });

  test('无重复（去重）', () {
    final daily = _p(1, authorId: 10, dynastyId: 20);
    final all = <Poem>[
      daily,
      _p(2, authorId: 10, dynastyId: 20),
      _p(3, authorId: 10, dynastyId: 20),
      _p(4, authorId: 99, dynastyId: 20),
      _p(1, authorId: 10, dynastyId: 20), // 与今日诗同 id，必须被去重
    ];
    final flow = buildDailyFlow(daily: daily, all: all);
    final ids = flow.map((p) => p.id).toList();
    expect(ids.length, ids.toSet().length, reason: '出现重复 id');
  });

  test('同作者先于同朝代（编排有先后）', () {
    final daily = _p(1, authorId: 10, dynastyId: 20);
    final all = <Poem>[
      daily,
      _p(2, authorId: 99, dynastyId: 20), // 仅同朝代
      _p(3, authorId: 10, dynastyId: 99), // 同作者不同朝代
    ];
    final flow = buildDailyFlow(daily: daily, all: all);
    // 首张是 daily；第二张应是与 daily 同作者的 3；第三张才是仅同朝代的 2
    expect(flow[0].id, 1);
    expect(flow[1].id, 3);
    expect(flow[2].id, 2);
  });

  test('数量受 authorLimit / dynastyLimit 约束', () {
    final daily = _p(1, authorId: 10, dynastyId: 20);
    final all = <Poem>[
      daily,
      for (int i = 2; i <= 11; i++) _p(i, authorId: 10, dynastyId: 20),
      for (int i = 12; i <= 21; i++) _p(i, authorId: 99, dynastyId: 20),
    ];
    final flow = buildDailyFlow(daily: daily, all: all,
        authorLimit: 3, dynastyLimit: 4);
    // 1(今日) + 3(同作者) + 4(同朝代) = 8
    expect(flow.length, 8);
  });

  test('确定性：同输入得到同次序', () {
    final daily = _p(5, authorId: 10, dynastyId: 20);
    final all = <Poem>[
      daily,
      _p(2, authorId: 10, dynastyId: 20),
      _p(8, authorId: 10, dynastyId: 20),
      _p(3, authorId: 99, dynastyId: 20),
    ];
    final a = buildDailyFlow(daily: daily, all: all);
    final b = buildDailyFlow(daily: daily, all: all);
    expect(a.map((p) => p.id).toList(), b.map((p) => p.id).toList());
  });

  test('缺作者/朝代信息时不报错（只返回今日诗）', () {
    final daily = _p(1);
    final all = <Poem>[daily, _p(2), _p(3)];
    final flow = buildDailyFlow(daily: daily, all: all);
    // 今日诗无作者/朝代信息，作者流与朝代流都空，只返回它自己，不应抛错
    expect(flow.length, 1);
    expect(flow.first.id, 1);
  });
}
