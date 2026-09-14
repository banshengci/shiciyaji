import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/database_helper.dart';
import '../data/models/achievement.dart';

/// 成就解锁中心。
///
/// 职责：
/// 1. 持久化已解锁成就集合（SharedPreferences），避免重复弹横幅；
/// 2. 应用启动（数据库就绪后）[init] 建立基线——当前已满足的成就直接标记，
///    不弹横幅，防止「一进 App 弹一堆历史成就」；
/// 3. 关键行为（复习打卡 / 收藏 / 笔记…）后调 [sync]，重新评估并把
///    **新解锁** 的成就经 [onUnlock] 广播，由根 Widget（MainShell）弹全局横幅。
///
/// 判定逻辑完全复用 `Achievement.isUnlocked(AchievementStats)`，本类不重复定义阈值。
class AchievementService {
  AchievementService._();

  static final AchievementService instance = AchievementService._();

  static const String _prefKey = 'shici_unlocked_achievements';

  final Set<String> _unlocked = {};
  // sync:true —— 解锁即刻同步派发，保证「行为→横幅」时序确定（也便于测试断言）
  final StreamController<Achievement> _stream =
      StreamController<Achievement>.broadcast(sync: true);
  bool _initialized = false;

  /// 新解锁成就事件流（仅 [sync] 且 announce=true 时发射）。
  Stream<Achievement> get onUnlock => _stream.stream;

  /// 应用启动调用：加载已解锁集合 + 建立基线（已满足的成就直接标记，不弹）。
  ///
  /// 必须在数据库初始化之后调用（[sync]/[init] 内部会查询统计）。
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.trim().isNotEmpty) {
      _unlocked.addAll(raw.split(','));
    }
    _initialized = true;
    await _evaluate(announce: false);
  }

  /// 行为后调用：重新评估成就，将新解锁的成就广播给订阅者。
  Future<void> sync() => _evaluate(announce: true);

  Future<void> _evaluate({required bool announce}) async {
    if (!_initialized) {
      // 尚未初始化（理论上不会走到，Splash 已 init）；按基线处理不弹。
      await init();
      return;
    }
    final results = await Future.wait<int>([
      DatabaseHelper.getStudiedCount(),
      DatabaseHelper.getNotesCount(),
      DatabaseHelper.getNotedPoemsCount(),
      DatabaseHelper.getStreakDays(),
      DatabaseHelper.getFavoriteCount(),
      DatabaseHelper.getTotalPoemsCount(),
    ]);
    final stats = AchievementStats(
      studiedCount: results[0],
      notesCount: results[1],
      notedPoemsCount: results[2],
      streakDays: results[3],
      favoriteCount: results[4],
      totalPoems: results[5],
    );

    final newly = <Achievement>[];
    for (final a in Achievements.all) {
      if (a.isUnlocked(stats) && !_unlocked.contains(a.id)) {
        _unlocked.add(a.id);
        newly.add(a);
      }
    }
    if (newly.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _unlocked.join(','));

    if (announce) {
      for (final a in newly) {
        _stream.add(a);
      }
    }
  }

  /// 当前已解锁成就 id 集合（只读副本）。
  Set<String> get unlockedIds => Set<String>.from(_unlocked);

  /// 仅供测试：重置单例状态（清空已解锁集合与初始化标记）。
  void resetForTesting() {
    _unlocked.clear();
    _initialized = false;
  }
}
