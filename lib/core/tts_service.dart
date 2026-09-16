import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// TTS 朗读服务：封装系统 TTS，支持播放/暂停/停止/倍速，
/// 以及逐句跟读（[speakVerses]）。
class TtsService {
  static TtsService? _instance;
  late FlutterTts _tts;
  bool _initialized = false;
  bool _isPlaying = false;
  double _rate = 1.0; // 0.5 - 2.0
  String? _currentText;

  /// 逐句朗读的「令牌」：每次开始/停止都自增，循环里对不上就退出。
  ///
  /// 用它而不是 bool 标志，是因为「停掉再立刻开一段新的」时，
  /// 旧循环可能正卡在 await 上，醒来后会把新的一段误判成自己还在跑。
  int _sequenceToken = 0;

  /// 当前这一句的完成信号。由 TTS 的 completion / error 回调完成。
  Completer<void>? _utteranceDone;

  TtsService._();

  static TtsService get instance {
    _instance ??= TtsService._();
    return _instance!;
  }

  Future<void> init() async {
    if (_initialized) return;
    _tts = FlutterTts();
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5); // 系统默认速率（0.0-1.0，我们映射为0.5x-2.0x）
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isPlaying = true;
    });
    _tts.setCompletionHandler(() {
      _isPlaying = false;
      _currentText = null;
      // 逐句模式靠这个信号推进到下一句
      if (_utteranceDone?.isCompleted == false) _utteranceDone!.complete();
    });
    _tts.setErrorHandler((msg) {
      _isPlaying = false;
      _currentText = null;
      // 出错也必须放行，否则跟读会卡在这一句上等到超时
      if (_utteranceDone?.isCompleted == false) _utteranceDone!.complete();
    });

    _initialized = true;
  }

  bool get isPlaying => _isPlaying;
  double get rate => _rate;
  String? get currentText => _currentText;

  /// 是否正在逐句跟读
  bool get isFollowing => _sequenceToken != 0;

  /// 朗读文本
  Future<void> speak(String text) async {
    await init();
    if (_isPlaying) {
      await _tts.stop();
    }
    _currentText = text;
    // 清理文本：去掉注释标记、特殊符号
    final cleanText = text
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\n+'), '，')
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5，。！？、；：""''（）]')
            , ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // 速率映射：0.5x -> 0.0, 1.0x -> 0.5, 2.0x -> 1.0
    final ttsRate = (_rate - 0.5) * 1.0; // 0.5-2.0 映射到 0.0-1.5
    await _tts.setSpeechRate(ttsRate.clamp(0.0, 1.0));
    await _tts.speak(cleanText);
    _isPlaying = true;
  }

  /// 逐句朗读 [verses]（由 `splitVerses` 断句得到）。
  ///
  /// 实现刻意**不依赖** `awaitSpeakCompletion(true)`：那会把 [speak] 变成阻塞调用，
  /// 现有的整段朗读 UI 会在念完之后才把「正在播放」点亮。这里改用 completion 回调
  /// 驱动的逐句 await，整段朗读的语义一点没变。
  ///
  /// - [from] 起始句下标（点某一句从那里开始）
  /// - [onVerse] 每句开始前回调，界面据此高亮
  /// - [loopAt] 该句读完后是否原地重读（单句循环）。做成**回调**而不是固定下标，
  ///   是为了让用户在朗读过程中开关循环能立刻生效
  /// - [onFinished] 全部读完（或被取消时不会回调）
  Future<void> speakVerses(
    List<String> verses, {
    int from = 0,
    void Function(int index)? onVerse,
    bool Function(int index)? loopAt,
    void Function()? onFinished,
  }) async {
    await init();
    final token = ++_sequenceToken;
    await _tts.stop();
    _isPlaying = false;

    final ttsRate = (_rate - 0.5).clamp(0.0, 1.0);
    await _tts.setSpeechRate(ttsRate);

    var i = from.clamp(0, verses.isEmpty ? 0 : verses.length - 1);
    while (i < verses.length) {
      if (token != _sequenceToken) return;

      final text = verses[i].trim();
      if (text.isEmpty) {
        i++;
        continue;
      }

      onVerse?.call(i);
      _currentText = text;
      _utteranceDone = Completer<void>();
      await _tts.speak(text);
      _isPlaying = true;

      try {
        // 兜底超时：个别平台不回调 completion（桌面端尤其），
        // 没有它跟读会永远停在第一句。宁可提前收尾，也不要假装还在念。
        await _utteranceDone!.future.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        if (token == _sequenceToken) {
          _sequenceToken = 0;
          _isPlaying = false;
          onFinished?.call();
        }
        return;
      }

      if (token != _sequenceToken) return;
      // 单句循环：原地重来，不推进下标
      if (loopAt?.call(i) ?? false) continue;
      i++;
    }

    if (token == _sequenceToken) {
      _sequenceToken = 0;
      _isPlaying = false;
      _currentText = null;
      onFinished?.call();
    }
  }

  /// 暂停/恢复
  Future<void> pause() async {
    await init();
    await _tts.pause();
    _isPlaying = false;
  }

  /// 停止
  Future<void> stop() async {
    await init();
    _sequenceToken++; // 取消逐句循环
    await _tts.stop();
    _isPlaying = false;
    _currentText = null;
  }

  /// 设置倍速
  Future<void> setRate(double r) async {
    _rate = r;
    if (_isPlaying && _currentText != null) {
      await speak(_currentText!);
    }
  }
}
