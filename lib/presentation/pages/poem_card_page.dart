import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/poem_share_cards.dart';
import '../widgets/shici_kit.dart';

/// 诗词卡片：把一首诗渲染成可保存 / 可分享的图，预览与导出走同一棵组件树。
///
/// 两款画面（04 名句摘录 / 01 经典题签）由 [PoemShareCard] 分发，
/// 选中项存 [PoemShareStyleStore]，与详情页、首页每日一诗共享同一份偏好。
class PoemCardPage extends StatefulWidget {
  final Poem poem;

  const PoemCardPage({super.key, required this.poem});

  @override
  State<PoemCardPage> createState() => _PoemCardPageState();
}

class _PoemCardPageState extends State<PoemCardPage> {
  final GlobalKey _cardKey = GlobalKey();

  PoemShareStyle _style = PoemShareStyleStore.fallback;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _restoreStyle();
  }

  Future<void> _restoreStyle() async {
    final saved = await PoemShareStyleStore.load();
    if (mounted) setState(() => _style = saved);
  }

  Future<void> _pickStyle(PoemShareStyle style) async {
    if (style == _style) return;
    setState(() => _style = style);
    await PoemShareStyleStore.save(style);
  }

  Future<void> _share(BuildContext anchorContext) async {
    if (_sharing) return;
    // 分享锚点必须在任何 await 之前取好：await 之后 widget 可能已卸载，
    // 那时再读 RenderBox 就会踩到「BuildContext 跨异步间隙」的坑。
    // 锚点本身是给 iPad / macOS 用的 —— 不给它，分享面板会从屏幕左上角弹出。
    final box = anchorContext.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(p.join(
        dir.path,
        'poem_card_${widget.poem.id}_${_style.name}.png',
      ));
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: widget.poem.title,
        text: '${widget.poem.title} · ${widget.poem.authorName ?? ''}'
            ' —— 来自「诗词雅集」',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('生成卡片失败：$e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final shareAnchor = GlobalKey();

    return Scaffold(
      appBar: AppBar(
        title: const Text('诗词卡片', style: TextStyle(fontFamily: ShiciFont.serif)),
        actions: <Widget>[
          Builder(
            builder: (btnCtx) => IconButton(
              onPressed: () => _share(btnCtx),
              icon: const PoemIcon(PoemIcons.share),
              tooltip: '分享卡片',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 卡片按可用宽度收敛，窄屏不去横向滚动、宽屏也不无限拉伸
            final cardWidth =
                math.min(360.0, constraints.maxWidth - ShiciSize.pagePadding * 2);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                ShiciSize.pagePadding,
                16,
                ShiciSize.pagePadding,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 展板：卡片垫在淡赭底上，深色卡与浅色卡都能看清边界
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: c.sand,
                      borderRadius: BorderRadius.circular(ShiciSize.rLg),
                    ),
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: PoemShareCard(
                        poem: widget.poem,
                        style: _style,
                        width: cardWidth,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildStyleSwitcher(c),
                  const SizedBox(height: 18),
                  _buildShareButton(shareAnchor),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 样式切换：两款画面各有取舍，就地切换比藏进弹窗更容易发现
  Widget _buildStyleSwitcher(ShiciColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '卡片样式',
          style: ShiciText.heading.copyWith(fontSize: 14, color: c.ink),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final style in PoemShareStyle.values)
              ShiciPill(
                label: style.label,
                selected: style == _style,
                onTap: () => _pickStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _style.hint,
          style: ShiciText.caption.copyWith(fontSize: 12, color: c.inkSoft),
        ),
      ],
    );
  }

  Widget _buildShareButton(GlobalKey anchor) {
    final c = ShiciColors.of(context);
    return Builder(
      key: anchor,
      builder: (btnCtx) => SizedBox(
        height: 46,
        child: Material(
          color: c.cinnabar,
          borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
          child: InkWell(
            onTap: _sharing ? null : () => _share(btnCtx),
            borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PoemIcon(PoemIcons.share, size: 16, color: c.onAccent),
                  const SizedBox(width: 8),
                  Text(
                    _sharing ? '正在生成…' : '分享为图片',
                    style: ShiciText.heading.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
