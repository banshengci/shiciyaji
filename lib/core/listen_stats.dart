import 'package:shared_preferences/shared_preferences.dart';

/// 听诗统计 —— 连播累计听过的篇次，供月报展示。
///
/// 轻量计数，不入库：听读是旁路体验，不该污染「学习打卡」语义。
class ListenStats {
  ListenStats._();

  static const _kCount = 'listen_poem_count';
  static const _kSessions = 'listen_session_count';
  static const _kMonthCount = 'listen_month_count'; // yyyyMM
  static const _kMonthSessions = 'listen_month_sessions';

  /// 累计听完的篇次（一篇读完记 1）
  static Future<int> totalPoems() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kCount) ?? 0;
  }

  static Future<int> totalSessions() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kSessions) ?? 0;
  }

  static String _monthKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}';

  /// 当月篇次
  static Future<int> monthPoems([DateTime? now]) async {
    final p = await SharedPreferences.getInstance();
    final k = _monthKey(now ?? DateTime.now());
    return p.getInt('${_kMonthCount}_$k') ?? 0;
  }

  static Future<int> monthSessions([DateTime? now]) async {
    final p = await SharedPreferences.getInstance();
    final k = _monthKey(now ?? DateTime.now());
    return p.getInt('${_kMonthSessions}_$k') ?? 0;
  }

  /// 连播开了一局
  static Future<void> recordSessionStart() async {
    final p = await SharedPreferences.getInstance();
    final k = _monthKey(DateTime.now());
    await p.setInt(_kSessions, (p.getInt(_kSessions) ?? 0) + 1);
    await p.setInt(
        '${_kMonthSessions}_$k', (p.getInt('${_kMonthSessions}_$k') ?? 0) + 1);
  }

  /// 一篇读完
  static Future<void> recordPoemHeard() async {
    final p = await SharedPreferences.getInstance();
    final k = _monthKey(DateTime.now());
    await p.setInt(_kCount, (p.getInt(_kCount) ?? 0) + 1);
    await p.setInt(
        '${_kMonthCount}_$k', (p.getInt('${_kMonthCount}_$k') ?? 0) + 1);
  }

  /// 供测试
  static Future<void> resetForTesting() async {
    final p = await SharedPreferences.getInstance();
    final keys = p.getKeys().where((k) => k.startsWith('listen_'));
    for (final k in keys.toList()) {
      await p.remove(k);
    }
  }
}

/// 飞花令段位 —— 按历史最佳分与局数给出称号。
class FlyingFlowerRank {
  FlyingFlowerRank._();

  static const _kBest = 'ff_best_score';
  static const _kGames = 'ff_game_count';
  static const _kTotalScore = 'ff_total_score';

  static Future<void> recordGame(int score) async {
    final p = await SharedPreferences.getInstance();
    final best = p.getInt(_kBest) ?? 0;
    if (score > best) await p.setInt(_kBest, score);
    await p.setInt(_kGames, (p.getInt(_kGames) ?? 0) + 1);
    await p.setInt(_kTotalScore, (p.getInt(_kTotalScore) ?? 0) + score);
  }

  static Future<int> bestScore() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBest) ?? 0;
  }

  static Future<int> gameCount() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kGames) ?? 0;
  }

  /// 段位：童生 → 秀才 → 举人 → 进士 → 翰林 → 状元
  static String rankOfScore(int best) {
    if (best >= 300) return '状元';
    if (best >= 200) return '翰林';
    if (best >= 120) return '进士';
    if (best >= 70) return '举人';
    if (best >= 30) return '秀才';
    return '童生';
  }

  static Future<String> currentRank() async =>
      rankOfScore(await bestScore());
}
