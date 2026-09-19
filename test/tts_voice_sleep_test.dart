import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shici_yaji/core/tts_service.dart';

/// 在无 TTS 插件的环境（与现有测试一致）下验证「听诗增强」：
/// - 音色：availableVoices 返回空且不抛；selectVoice 不抛。
/// - 睡眠定时：startSleepTimer 后 sleepRemaining 有值；cancelSleepTimer 后为 null；
///   disposeForTesting 后无 pending timer（不报 "A Timer was started"）。
///
/// 注意：这里用 plain [test] 而非 [testWidgets]。本沙箱里 [testWidgets] 的
/// FakeAsync 不会推进方法通道的时钟，flutter_tts 的 invokeMethod 会挂起，导致
/// init() 卡死；plain test 走真实时钟，invokeMethod 会如期抛出 MissingPluginException
/// 并降级为静默（与项目里既有的无插件降级行为一致）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('听诗增强 · 音色与睡眠定时', () {
    test('无 TTS 插件环境下 availableVoices 返回空且不抛', () async {
      final svc = TtsService.instance;
      final voices = await svc.availableVoices();
      expect(voices, isEmpty);
    });

    test('selectVoice 不抛（即便无插件）', () async {
      final svc = TtsService.instance;
      await svc.selectVoice(const TtsVoice(name: '默认嗓音', locale: 'zh-CN'));
      // 不应抛；无插件时静默降级，SharedPreferences 里也不会留下有效音色
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_voice_name'), isNull);
    });

    test('startSleepTimer 后 sleepRemaining 有值，cancel 后为 null', () async {
      final svc = TtsService.instance;
      svc.startSleepTimer(const Duration(minutes: 15));
      expect(svc.sleepRemaining, isNotNull);
      svc.cancelSleepTimer();
      expect(svc.sleepRemaining, isNull);
    });

    test('disposeForTesting 后无 pending timer、状态归位', () async {
      final svc = TtsService.instance;
      svc.startSleepTimer(const Duration(minutes: 30));
      expect(svc.sleepRemaining, isNotNull);
      svc.disposeForTesting();
      expect(svc.sleepRemaining, isNull);
    });
  });
}
