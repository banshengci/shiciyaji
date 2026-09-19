import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/sleep_timer.dart';

void main() {
  group('SleepTimer 倒计时', () {
    test('start 后 active 且 remaining 等于设定值', () {
      final t = SleepTimer();
      t.start(const Duration(seconds: 5));
      expect(t.active, isTrue);
      expect(t.remaining, const Duration(seconds: 5));
    });

    test('tick 每秒递减 1 秒', () {
      final t = SleepTimer();
      t.start(const Duration(seconds: 3));
      t.tick();
      expect(t.remaining, const Duration(seconds: 2));
      t.tick();
      expect(t.remaining, const Duration(seconds: 1));
      t.tick();
      expect(t.remaining, Duration.zero);
    });

    test('归零的那一次 tick 触发 onElapsed 且仅一次', () {
      var calls = 0;
      final t = SleepTimer(onElapsed: () => calls++);
      t.start(const Duration(seconds: 1));
      t.tick(); // -> 0
      t.tick(); // 触发回调
      expect(calls, 1);
      t.tick();
      t.tick();
      expect(calls, 1, reason: '到点后不应再次回调');
    });

    test('cancel 后 remaining 为 null 且不再回调', () {
      var calls = 0;
      final t = SleepTimer(onElapsed: () => calls++);
      t.start(const Duration(seconds: 5));
      t.tick();
      t.cancel();
      expect(t.active, isFalse);
      expect(t.remaining, isNull);
      t.tick();
      t.tick();
      expect(calls, 0);
    });

    test('未启用时 tick 无副作用', () {
      var calls = 0;
      final t = SleepTimer(onElapsed: () => calls++);
      expect(t.active, isFalse);
      expect(t.remaining, isNull);
      t.tick();
      expect(calls, 0);
      expect(t.remaining, isNull);
    });

    test('0/负值边界视为立即到点：下一次 tick 即回调一次', () {
      var calls = 0;
      final t = SleepTimer(onElapsed: () => calls++);
      t.start(Duration.zero);
      expect(t.active, isTrue);
      expect(t.remaining, Duration.zero);
      t.tick(); // 立即触发
      expect(calls, 1);
      t.tick();
      expect(calls, 1, reason: '不应重复回调');

      final t2 = SleepTimer(onElapsed: () => calls++);
      t2.start(const Duration(seconds: -10));
      t2.tick();
      expect(calls, 2);
    });

    test('亚秒级剩余不会减成负数，而是夹到 0', () {
      final t = SleepTimer();
      t.start(const Duration(milliseconds: 500));
      t.tick();
      expect(t.remaining, Duration.zero);
    });
  });
}
