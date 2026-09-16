import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把屏幕上的某个 [RepaintBoundary] 导出成 PNG 并调起系统分享。
///
/// 从 `poem_card_page` 里抽出来的：月报长图要与诗词卡片走**同一条**导出路径，
/// 否则两处的分辨率、文件名规则、失败提示会慢慢各走各的。
///
/// 三条实现上的注意事项（都是踩过的）：
/// 1. `toImage` 必须在 `await` 之前拿到 boundary —— await 之后 widget 可能已卸载；
/// 2. `pixelRatio: 3.0` 是为了让分享图在手机上不发虚，与卡片保持一致；
/// 3. 分享锚点（`sharePositionOrigin`）不能省 —— iPad / macOS 上不给它，
///    分享面板会从屏幕左上角冒出来。
class CardExporter {
  CardExporter._();

  /// 导出并分享。[key] 指向要导出的 [RepaintBoundary]。
  ///
  /// 返回 null 表示成功，否则返回给用户看的错误文案。
  static Future<String?> exportAndShare({
    required GlobalKey key,
    required String fileName,
    required String text,
    String? subject,
    Rect? shareOrigin,
    double pixelRatio = 3.0,
  }) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return '画面还没准备好，稍后再试';

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return '生成图片失败';

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: subject,
        text: text,
        sharePositionOrigin: shareOrigin,
      );
      return null;
    } catch (e) {
      return '生成图片失败：$e';
    }
  }
}
