import 'dart:async';

/// 睡眠定时（纯逻辑，可单测，无 Flutter / 真实时钟依赖）。
///
/// 固定步长 1 秒：由外部（如一个 1 秒 [Timer]）每秒调用一次 [tick] 推进倒计时。
/// 因为不依赖 [DateTime]/真实时钟，测试可以直接连调 [tick] 把倒计时走完，
/// 而不必真的等上 15 分钟。
///
/// 语义约定：
/// - [active]：是否正在倒计时。
/// - [remaining]：剩余时间；未启用时为 `null`。
/// - 倒计时归零的那一次 [tick] 会把状态置为未启用，并回调 [onElapsed]，**只回调一次**。
class SleepTimer {
  /// [onElapsed] 到点回调，归零时触发一次。可为空（纯计时场景不需要通知）。
  SleepTimer({this.onElapsed});

  final void Function()? onElapsed;

  Duration? _remaining;
  bool _elapsedFired = false;

  /// 是否正在倒计时。
  bool get active => _remaining != null;

  /// 剩余时间；未启用时为 null。
  Duration? get remaining => _remaining;

  /// 启动（或重置）一个倒计时。
  ///
  /// [d] 必须为正。传 `Duration.zero` 或负值视为「立即到点」：剩余记为 0 并保持
  /// 启用态，下一次 [tick] 即触发回调。该边界由 `test/sleep_timer_test.dart` 覆盖说明。
  void start(Duration d) {
    _elapsedFired = false;
    if (d.inMilliseconds <= 0) {
      _remaining = Duration.zero;
      return;
    }
    _remaining = d;
  }

  /// 取消倒计时：剩余置 null、启用态归 false，之后不再回调。
  void cancel() {
    _remaining = null;
    _elapsedFired = false;
  }

  /// 推进 1 秒。
  ///
  /// - 未启用（[remaining] 为 null）时直接返回，无副作用。
  /// - 剩余为 0 时：置未启用并回调 [onElapsed]（仅一次）。
  /// - 其余情况：减 1 秒（粒度比 1 秒更细时夹到 0，不会减成负数）。
  void tick() {
    final r = _remaining;
    if (r == null) return;
    if (r == Duration.zero) {
      _remaining = null;
      if (!_elapsedFired) {
        _elapsedFired = true;
        onElapsed?.call();
      }
      return;
    }
    final next = r - const Duration(seconds: 1);
    _remaining = next.isNegative ? Duration.zero : next;
  }
}
