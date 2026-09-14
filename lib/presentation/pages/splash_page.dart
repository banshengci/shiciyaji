import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/achievement_service.dart';
import '../../data/database/database_helper.dart';
import '../widgets/shici_kit.dart';

/// 品牌首屏（启动页）：宣纸底 + 朱砂日轮 + 远山 + 方印 + 书法字标。
///
/// 设计意图（新中式 / 极简留白）：
/// - 先展示品牌，再在后台静默预初始化数据库与拼音索引，
///   避免直接进入 MainShell 时的黑/白屏闪烁。
/// - 加载完成后通过 [onFinished] 回调切到主壳，由 ShiciYajiApp 控制。
/// - 版面与设计稿 S1 封面 / S4 启动页主视觉同源，只是按竖屏重排。
class SplashPage extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashPage({super.key, required this.onFinished});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 预初始化数据库；即使失败也继续进入主壳，避免卡死在启动页。
    try {
      await DatabaseHelper.preInit();
    } catch (_) {
      // 忽略：交给主壳的错误处理
    }
    if (!mounted) return;
    // 建立成就解锁基线：把当前已满足的成就直接标记为已解锁（不弹横幅），
    // 后续行为触发 sync() 时才对「新解锁」弹横幅。
    await AchievementService.instance.init();
    // 数据就绪后预热拼音索引（分片让出 UI 线程），用户输入拼音时零等待。
    DatabaseHelper.warmPinyinIndex();
    // 让品牌首屏停留片刻，避免一闪而过。
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final w = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: c.paper,
      body: FadeTransition(
        opacity: _fade,
        child: Stack(
          children: <Widget>[
            // 朱砂日轮：右上角大面积低透明度，呼应封面
            Positioned(
              top: -80,
              right: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.cinnabar.withOpacity(0.06),
                ),
              ),
            ),
            // 远山留白：贴底，做成水墨地平线
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Opacity(
                opacity: 0.45,
                child: InkMountain(size: Size(w, 128), inkColor: c.ink),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 方印
                  SealMark(size: 76, color: c.cinnabar, glyphColor: c.paper),
                  const SizedBox(height: 30),
                  // 书法字标
                  Text(
                    '诗词雅集',
                    style: ShiciText.calligraphy.copyWith(
                      fontSize: 42,
                      color: c.ink,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 朱砂短线点睛
                  Container(width: 46, height: 2, color: c.cinnabar),
                  const SizedBox(height: 16),
                  Text(
                    '与古人对话 · 与风雅同行',
                    style: ShiciText.caption.copyWith(
                      color: c.inkSoft,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: c.cinnabar.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
