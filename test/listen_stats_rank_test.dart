import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/listen_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('听诗统计与飞花段位', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('ListenStats 记录局次与篇次，并按月汇总', () async {
      final now = DateTime(2026, 9, 17);
      await ListenStats.recordSessionStart();
      await ListenStats.recordSessionStart();
      await ListenStats.recordPoemHeard();
      await ListenStats.recordPoemHeard();
      await ListenStats.recordPoemHeard();

      expect(await ListenStats.totalSessions(), 2);
      expect(await ListenStats.totalPoems(), 3);
      expect(await ListenStats.monthPoems(now), 3);
      expect(await ListenStats.monthSessions(now), 2);
      // 其他月份为 0
      expect(await ListenStats.monthPoems(DateTime(2026, 8, 1)), 0);
    });

    test('飞花令段位随最高分晋升', () {
      expect(FlyingFlowerRank.rankOfScore(0), '童生');
      expect(FlyingFlowerRank.rankOfScore(40), '秀才');
      expect(FlyingFlowerRank.rankOfScore(80), '举人');
      expect(FlyingFlowerRank.rankOfScore(150), '进士');
      expect(FlyingFlowerRank.rankOfScore(220), '翰林');
      expect(FlyingFlowerRank.rankOfScore(400), '状元');
    });

    test('FlyingFlowerRank.recordGame 更新最佳分与局数', () async {
      await FlyingFlowerRank.recordGame(50);
      await FlyingFlowerRank.recordGame(90);
      await FlyingFlowerRank.recordGame(30);
      expect(await FlyingFlowerRank.bestScore(), 90);
      expect(await FlyingFlowerRank.gameCount(), 3);
      expect(await FlyingFlowerRank.currentRank(), '举人');
    });
  });
}
