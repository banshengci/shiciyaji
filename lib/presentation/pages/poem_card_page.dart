import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/poem_icon.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';

/// 诗词卡片：把一首诗渲染成宣纸质感的竖排图文，用于保存 / 分享
class PoemCardWidget extends StatelessWidget {
  final Poem poem;

  const PoemCardWidget({super.key, required this.poem});

  @override
  Widget build(BuildContext context) {
    const paperBg = AppTheme.xuanZhiBai;
    final author = poem.authorName ?? '佚名';
    final dynasty = poem.dynastyName ?? '';

    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      decoration: BoxDecoration(
        color: paperBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.songLv.withOpacity(0.35), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 顶部装饰：细线 + 朱砂方印
          Row(
            children: [
              Expanded(
                child: Container(
                    height: 1, color: AppTheme.songLv.withOpacity(0.4)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 10,
                height: 10,
                color: AppTheme.zhuShaHong,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                    height: 1, color: AppTheme.songLv.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            poem.title,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: AppTheme.moHei,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            dynasty.isEmpty ? author : '$dynasty · $author',
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 14,
              color: AppTheme.qingHui,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            poem.content,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 19,
              height: 2.0,
              color: AppTheme.moHei,
            ),
          ),
          const SizedBox(height: 24),
          // 落款：印章 + 应用名
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '诗词雅集',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 11,
                      color: AppTheme.qingHui,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.zhuShaHong, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '雅集',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 11,
                        color: AppTheme.zhuShaHong,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 卡片预览 / 分享页
class PoemCardPage extends StatelessWidget {
  final Poem poem;

  PoemCardPage({super.key, required this.poem});

  final GlobalKey _cardKey = GlobalKey();

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'poem_card_${poem.id}.png'));
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: poem.title,
        text: '${poem.title} · ${poem.authorName ?? ''} —— 来自「诗词雅集」',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('生成卡片失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('诗词卡片', style: TextStyle(fontFamily: 'serif')),
        actions: [
          IconButton(
            onPressed: () => _share(context),
            icon: const PoemIcon(PoemIcons.share),
            tooltip: '分享卡片',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: PoemCardWidget(poem: poem),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '点击右上角可分享为图片',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
