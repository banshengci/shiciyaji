import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, ValueNotifier;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sleep_timer.dart';

/// 一个可选音色（系统 TTS 引擎提供的嗓音）。
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  /// 系统音色名（引擎相关，可能含设备/语言特征）
  final String name;

  /// 区域标签，如 `zh-CN` / `cmn-CN` / `yue-HK`
  final String locale;

  /// 展示名：能识别成中文的给「普通话 / 粤语 …」这类友好名，否则回退为 `名字 · 区域`。
  String get label {
    final zh = _chineseLocaleLabel(locale);
    if (zh != null) return '$name（$zh）';
    return '$name · $locale';
  }

  static String? _chineseLocaleLabel(String locale) {
    final l = locale.toLowerCase();
    if (l.contains('yue') || l.contains('cantonese')) return '粤语';
    if (l.startsWith('zh') ||
        l.contains('cmn') ||
        l.contains('chinese')) {
      if (l.contains('tw') || l.contains('hk') || l.contains('hant')) {
        return '普通话（港澳台）';
      }
      return '普通话';
    }
    return null;
  }
}

/// TTS 朗读服务：封装系统 TTS，支持播放/暂停/停止/倍速，
/// 以及逐句跟读（[speakVerses]）。
///
/// **插件缺失时降级为静默**：部分平台（以及单元测试环境）没有注册 TTS 插件，
/// 调用会抛 [MissingPluginException]。此时 [isAvailable] 变为 false，
/// 所有朗读方法变成空操作，而不是把异常抛给界面。
class TtsService {
  static TtsService? _instance;
  late FlutterTts _tts;
  bool _initialized = false;

  /// 运行环境是否真的有可用的 TTS 插件。初始化时探测，失败即置 false。
  bool _available = true;
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

  // —— 睡眠定时（倒计时逻辑在 SleepTimer，这里负责用 1 秒 Timer 驱动它） ——
  Timer? _sleepTickDriver;
  SleepTimer? _sleepTimerObj;
  final ValueNotifier<Duration?> _sleepRemainingNotifier =
      ValueNotifier<Duration?>(null);

  TtsService._();

  static TtsService get instance {
    _instance ??= TtsService._();
    return _instance!;
  }

  Future<void> init() async {
    if (_initialized) return;
    // 先占位：即便初始化失败也不再重试（插件不会中途出现），
    // 否则每次调用都会重新抛一次 MissingPluginException。
    _initialized = true;
    try {
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

      // 读回已保存的音色（失败不影响其它朗读能力）
      try {
        await _applySavedVoice();
      } catch (e) {
        debugPrint('恢复已保存音色失败：$e');
      }
    } on MissingPluginException {
      // 平台/测试环境没有 TTS 插件：降级为静默，不把异常抛给界面
      _available = false;
      debugPrint('TTS 插件不可用，朗读降级为静默');
    } catch (e) {
      _available = false;
      debugPrint('TTS 初始化失败，朗读降级为静默：$e');
    }
  }

  /// 当前环境是否真的有可用的 TTS（界面据此决定要不要显示朗读入口）
  bool get isAvailable => _available;

  bool get isPlaying => _isPlaying;
  double get rate => _rate;
  String? get currentText => _currentText;

  /// 是否正在逐句跟读
  bool get isFollowing => _sequenceToken != 0;

  /// 列出本设备支持的中文音色。
  ///
  /// 无插件 / 解析失败 / 抛异常时一律降级为空列表（不崩、不假装能用）。
  Future<List<TtsVoice>> availableVoices() async {
    await init();
    if (!_available) return const [];
    try {
      final dynamic raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = item as Map<Object?, Object?>;
        final name = map['name'];
        final locale = map['locale'];
        if (name is! String || locale is! String) continue;
        if (!_isChineseLocale(locale)) continue;
        voices.add(TtsVoice(name: name, locale: locale));
      }
      return voices;
    } catch (e) {
      debugPrint('读取音色列表失败，降级为空：$e');
      return const [];
    }
  }

  bool _isChineseLocale(String locale) {
    final l = locale.toLowerCase();
    return l.contains('zh') ||
        l.contains('cmn') ||
        l.contains('chinese');
  }

  /// 选择并持久化一个音色。
  ///
  /// 无插件 / 失败时仅 [debugPrint]，不抛（沿用整体降级风格）。
  Future<void> selectVoice(TtsVoice v) async {
    await init();
    if (!_available) return;
    try {
      await _tts.setVoice(<String, String>{
        'name': v.name,
        'locale': v.locale,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_voice_name', v.name);
      await prefs.setString('tts_voice_locale', v.locale);
    } catch (e) {
      debugPrint('选择音色失败：$e');
    }
  }

  /// 读回已保存的音色并在可用时应用（[init] 内调用）。
  Future<void> _applySavedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('tts_voice_name');
    final locale = prefs.getString('tts_voice_locale');
    if (name == null || locale == null) return;
    if (_available) await _tts.setVoice({'name': name, 'locale': locale});
  }

  // ════════════════════════════════════════════════════════════════════
  // 睡眠定时
  // ════════════════════════════════════════════════════════════════════

  SleepTimer get _sleepTimer {
    _sleepTimerObj ??= SleepTimer(onElapsed: _onSleepElapsed);
    return _sleepTimerObj!;
  }

  void _onSleepElapsed() {
    // 先停掉驱动与显示，再淡出（淡出内部有 _available 守卫）。
    _sleepTickDriver?.cancel();
    _sleepTickDriver = null;
    _sleepRemainingNotifier.value = null;
    _fadeOutAndStop();
  }

  /// 供 UI 显示倒计时的可监听对象（[ValueListenableBuilder] 直接套）。
  ValueNotifier<Duration?> get sleepRemainingNotifier => _sleepRemainingNotifier;

  /// 当前剩余时间；未启用时为 null。
  Duration? get sleepRemaining =>
      _sleepTimerObj?.active == true ? _sleepTimerObj!.remaining : null;

  /// 启动睡眠定时。
  ///
  /// 注意：定时本身**不依赖** TTS 插件 —— 即使处于静默降级，倒计时与 UI 也照常工作
  /// （无插件环境，含单测，[sleepRemaining] 仍有值）；真正需要插件的「淡出并停止」
  /// 在 [_fadeOutAndStop] 内部再做 _available 守卫。
  void startSleepTimer(Duration d) {
    cancelSleepTimer();
    _sleepTimer.start(d);
    _sleepRemainingNotifier.value = _sleepTimer.remaining;
    _sleepTickDriver = Timer.periodic(
      const Duration(seconds: 1),
      _onSleepTick,
    );
  }

  void _onSleepTick(_) {
    _sleepTimer.tick();
    _sleepRemainingNotifier.value = _sleepTimer.remaining;
  }

  /// 取消睡眠定时。
  void cancelSleepTimer() {
    _sleepTickDriver?.cancel();
    _sleepTickDriver = null;
    _sleepTimerObj?.cancel();
    _sleepRemainingNotifier.value = null;
  }

  /// 到点：分约 10 步、约 5 秒内把音量从 1.0 降到 0，再停止并复位音量。
  ///
  /// 无插件时直接 return（静默降级，没有可淡出的声音）。
  Future<void> _fadeOutAndStop() async {
    if (!_available) return;
    const steps = 10;
    const stepMs = 500; // 10 * 500ms ≈ 5 秒
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      final volume = 1.0 - i / steps;
      try {
        await _tts.setVolume(volume);
      } catch (e) {
        debugPrint('睡眠定时淡出失败：$e');
      }
    }
    await stop();
    try {
      await _tts.setVolume(1.0);
    } catch (e) {
      debugPrint('睡眠定时复位音量失败：$e');
    }
  }

  /// 测试收尾：取消所有挂起的 Timer 与倒计时，避免套件里残留 pending timer。
  void disposeForTesting() {
    _sleepTickDriver?.cancel();
    _sleepTickDriver = null;
    _sleepTimerObj?.cancel();
    _sleepRemainingNotifier.value = null;
  }

  /// 朗读文本
  Future<void> speak(String text) async {
    await init();
    if (!_available) return;
    if (_isPlaying) {
      await _tts.stop();
    }
    _currentText = text;
    // 清理文本：去掉注释标记、特殊符号
    final cleanText = text
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\n+'), '，')
        .replaceAll(
            RegExp(r'[^\u4e00-\u9fa5，。！？、；：""''（）]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // 速率映射：0.5x -> 0.0, 1.0x -> 0.5, 2.0x -> 1.0
    final ttsRate = (_rate - 0.5) * 1.0; // 0.5-2.0 映射到 0.0-1.5
    await _tts.setSpeechRate(ttsRate.clamp(0.0, 1.0));
    _utteranceDone = Completer<void>();
    await _tts.speak(cleanText);
    _isPlaying = true;
  }

  /// 等待当前 [speak] / 逐句句读完（或超时、出错时放行）。
  ///
  /// 连播队列靠它串起「上一篇念完再念下一篇」；个别平台不回调 completion 时
  /// 走超时，避免整队卡死。
  Future<void> waitPlayback(
      {Duration timeout = const Duration(minutes: 3)}) async {
    final done = _utteranceDone;
    if (done == null || done.isCompleted) return;
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      // 超时视为本句结束，让调用方推进
    }
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
    // 无 TTS 时直接退出，且**不**回调 onFinished —— 不谎报「读完了」
    if (!_available) return;
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
    if (!_available) return;
    await _tts.pause();
    _isPlaying = false;
  }

  /// 停止
  Future<void> stop() async {
    await init();
    _sequenceToken++; // 取消逐句循环
    if (_available) await _tts.stop();
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
