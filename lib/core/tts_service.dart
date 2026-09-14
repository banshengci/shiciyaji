import 'package:flutter_tts/flutter_tts.dart';

/// TTS 朗读服务：封装系统 TTS，支持播放/暂停/停止/倍速
class TtsService {
  static TtsService? _instance;
  late FlutterTts _tts;
  bool _initialized = false;
  bool _isPlaying = false;
  double _rate = 1.0; // 0.5 - 2.0
  String? _currentText;

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
    });
    _tts.setErrorHandler((msg) {
      _isPlaying = false;
      _currentText = null;
    });

    _initialized = true;
  }

  bool get isPlaying => _isPlaying;
  double get rate => _rate;
  String? get currentText => _currentText;

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

  /// 暂停/恢复
  Future<void> pause() async {
    await init();
    await _tts.pause();
    _isPlaying = false;
  }

  /// 停止
  Future<void> stop() async {
    await init();
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
