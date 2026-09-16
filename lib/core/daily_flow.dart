import '../data/models/models.dart';

/// 一日一赏的编排 —— 纯函数，**不含随机**。
///
/// 编排规则：今日一首 → 同作者其他作品 → 同朝代其他作品。
/// 这样连着翻下去有「顺着一个人读」或「顺着一个时代读」的味道，
/// 比随机抽取更像一期一期的内容，也让「下一首」有意义。
///
/// 为什么坚持不要随机：同一天打开两次必须看到同样的次序 ——
/// 用户可能翻到第三首准备分享，切出去再回来却发现全换了一批；
/// 而导出的是屏幕上的这张卡，随机会让同一期的分享图不可复现。
List<Poem> buildDailyFlow({
  required Poem daily,
  required List<Poem> all,
  int authorLimit = 5,
  int dynastyLimit = 5,
}) {
  final flow = <Poem>[daily];
  final seen = <int>{daily.id};

  void take(Iterable<Poem> candidates, int limit) {
    var added = 0;
    for (final poem in candidates) {
      if (added >= limit) break;
      if (!seen.add(poem.id)) continue;
      flow.add(poem);
      added++;
    }
  }

  /// 按 id 升序：数据源顺序可能变（离线包导入次序不同），
  /// 但「同一份数据得到同一个次序」必须成立。
  int byId(Poem a, Poem b) => a.id.compareTo(b.id);

  final authorId = daily.authorId;
  if (authorId != null) {
    take(all.where((p) => p.authorId == authorId).toList()..sort(byId), authorLimit);
  }
  final dynastyId = daily.dynastyId;
  if (dynastyId != null) {
    take(all.where((p) => p.dynastyId == dynastyId).toList()..sort(byId),
        dynastyLimit);
  }

  return flow;
}
