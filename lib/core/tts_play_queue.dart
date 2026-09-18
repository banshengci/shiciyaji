import 'dart:async';

import 'package:flutter/foundation.dart';

import 'listen_stats.dart';
import 'tts_service.dart';

/// 听诗队列里的一首
@immutable
class TtsQueueItem {
  final int poemId;
  final String title;
  final String content;

  const TtsQueueItem({
    required this.poemId,
    required this.title,
    required this.content,
  });

  /// 整段朗读用的合成文本（与详情页整段朗读一致）
  String get speechText => '$title。$content';
}

/// 睡前连播 / 听诗队列 —— 多首连续朗读，首尾不停顿到手动结束。
///
/// 全局单例（[instance]）：用户从计划页点「连播」后切到别的页面仍应继续播，
/// 因此不能挂在某个 Page 的 State 上。UI 用 [ChangeNotifier] 监听进度。
class TtsPlayQueue extends ChangeNotifier {
  TtsPlayQueue._();

  static final TtsPlayQueue instance = TtsPlayQueue._();

  final TtsService _tts = TtsService.instance;

  List<TtsQueueItem> _items = const [];
  int _index = 0;
  bool _playing = false;
  bool _disposed = false;

  /// 队列标题（如计划名），用于迷你条展示
  String _label = '';

  /// 篇与篇之间的静默间隙
  Duration gap = const Duration(milliseconds: 1200);

  /// 播完是否自动从头再来（睡前循环）
  bool loop = false;

  /// 播放令牌：停止 / 换队列时自增，旧循环对不上就退出
  int _token = 0;

  List<TtsQueueItem> get items => _items;
  int get index => _index;
  bool get isPlaying => _playing;
  String get label => _label;

  bool get hasQueue => _items.isNotEmpty;

  TtsQueueItem? get current =>
      (_index >= 0 && _index < _items.length) ? _items[_index] : null;

  /// 开始连播 [items]；[from] 为起始下标
  Future<void> start(
    List<TtsQueueItem> items, {
    int from = 0,
    required String label,
  }) async {
    if (items.isEmpty) return;
    try {
      await stop();
    } catch (_) {
      // 无 TTS 插件的测试环境不阻断队列状态更新
      _playing = false;
      _token++;
    }
    _items = List.unmodifiable(items);
    _label = label;
    _index = from.clamp(0, items.length - 1);
    _playing = true;
    _token++;
    _notify();
    unawaited(_safeRecord(ListenStats.recordSessionStart));
    unawaited(_run(_token));
  }

  static Future<void> _safeRecord(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      // 统计失败不影响听诗（测试环境可能没有 shared_preferences 插件）
    }
  }

  Future<void> _run(int token) async {
    while (_playing && token == _token) {
      final item = current;
      if (item == null) break;
      try {
        await _tts.setRate(_tts.rate);
        await _tts.speak(item.speechText);
        await _tts.waitPlayback(
          timeout: const Duration(minutes: 3),
        );
        if (token == _token && _playing) {
          unawaited(_safeRecord(ListenStats.recordPoemHeard));
        }
      } catch (_) {
        // 单篇失败不掐断整队
      }
      if (token != _token || !_playing) return;
      await Future<void>.delayed(gap);
      if (token != _token || !_playing) return;
      if (_index + 1 < _items.length) {
        _index++;
      } else if (loop) {
        _index = 0;
      } else {
        _playing = false;
        _index = _items.length - 1;
        _notify();
        return;
      }
      _notify();
    }
  }

  Future<void> pause() async {
    if (!_playing) return;
    _playing = false;
    _token++;
    try {
      await _tts.stop();
    } catch (_) {}
    _notify();
  }

  Future<void> resume() async {
    if (_playing || _items.isEmpty) return;
    _playing = true;
    _token++;
    _notify();
    unawaited(_run(_token));
  }

  Future<void> stop() async {
    _playing = false;
    _token++;
    try {
      await _tts.stop();
    } catch (_) {}
    _notify();
  }

  /// 清空队列并停止（迷你条关闭）
  Future<void> clear() async {
    await stop();
    _items = const [];
    _index = 0;
    _label = '';
    _notify();
  }

  Future<void> next() async {
    if (_items.isEmpty) return;
    if (_index + 1 < _items.length) {
      _index++;
    } else if (loop) {
      _index = 0;
    } else {
      await stop();
      return;
    }
    _notify();
    if (_playing) {
      _token++;
      unawaited(_run(_token));
    }
  }

  Future<void> previous() async {
    if (_items.isEmpty) return;
    _index = (_index - 1).clamp(0, _items.length - 1);
    _notify();
    if (_playing) {
      _token++;
      unawaited(_run(_token));
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
