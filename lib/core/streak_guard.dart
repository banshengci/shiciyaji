/// 打卡韧性（连胜冻结 / 补签卡）的纯逻辑层。
///
/// 设计目标（功能 F3）：
/// - 连续打卡一旦中断就清零，长期坚持被一次意外毁掉 —— 借鉴多邻国 Streak
///   Freeze / 墨墨「补签卡」，但**绝不做假打卡**；
/// - 「冻结日」「补签日」都视为**已打卡**，参与连续天数计算；
/// - 二者都不向 study_records 写入任何学习记录 —— 不伪造学习数据；
/// - 覆盖必须是用户显式操作、有额度、有记录。
///
/// 本文件**无任何 Flutter UI 依赖、不读系统时钟**：`today` 一律由调用方传入，
/// 以便单测可确定性地推进时间。存储与额度由 [DatabaseHelper] / `streak_store`
/// 负责。
library;

/// 连胜守护的持久化状态快照（不可变）。
///
/// 冻结日与补签日分别保存，便于界面区分展示；参与连续天数计算时取二者并集
/// [covered]。补签卡存量与已发放里程碑用于发放判定与去重。
class StreakGuardState {
  /// 冻结日集合（用户主动冻结的空档日）。
  final Set<DateTime> frozen;

  /// 补签日集合（用补签卡补的空档日）。
  final Set<DateTime> repaired;

  /// 补签卡存量。
  final int repairCards;

  /// 已发放过补签卡的「达成点」（如 `'streak_7'`），防止同一里程碑重复发放。
  final Set<String> grantedMilestones;

  const StreakGuardState({
    this.frozen = const <DateTime>{},
    this.repaired = const <DateTime>{},
    this.repairCards = StreakGuard.initialRepairCards,
    this.grantedMilestones = const <String>{},
  });

  /// 冻结 ∪ 补签 的并集，参与连续天数计算的「已覆盖」日集合。
  Set<DateTime> get covered => <DateTime>{...frozen, ...repaired};

  StreakGuardState copyWith({
    Set<DateTime>? frozen,
    Set<DateTime>? repaired,
    int? repairCards,
    Set<String>? grantedMilestones,
  }) =>
      StreakGuardState(
        frozen: frozen ?? this.frozen,
        repaired: repaired ?? this.repaired,
        repairCards: repairCards ?? this.repairCards,
        grantedMilestones: grantedMilestones ?? this.grantedMilestones,
      );
}

/// 纯逻辑：连胜计算与额度判定。
class StreakGuard {
  const StreakGuard._();

  /// 补签卡：初始发放数（新用户开局即有，不依赖任何达成）。
  static const int initialRepairCards = 3;

  /// 补签卡：存量上限。
  static const int maxRepairCards = 5;

  /// 每月冻结次数上限（自然月，跨月自动重置）。
  static const int freezesPerMonth = 2;

  /// 补签卡发放节奏：每连续这么多天补发 1 张。
  static const int repairCardEveryStreak = 7;

  /// 把任意 [DateTime] 归一到「当天 00:00」，忽略时分秒，只按天比较。
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 当前连续天数。
  ///
  /// [studied] 与 [covered] 里都是「已打卡」的日期（[covered] 为冻结日 ∪ 补签日）。
  /// 规则与改造前一致：从今天往回数连续天数；若今天没打卡（也没覆盖），
  /// 则从昨天开始数 —— 允许「今天还没学、但昨天学了」仍算连胜。
  static int currentStreak({
    required Set<DateTime> studied,
    required Set<DateTime> covered,
    required DateTime today,
  }) {
    final active = <DateTime>{
      for (final d in studied) dayOnly(d),
      for (final d in covered) dayOnly(d),
    };
    final t = dayOnly(today);
    // 今天算「已打卡」则从今天起数；否则退到昨天（允许今天尚未学习）。
    var cursor = active.contains(t) ? t : t.subtract(const Duration(days: 1));
    if (!active.contains(cursor)) return 0;
    var streak = 0;
    while (active.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 该日是否可被覆盖（冻结或补签）。
  ///
  /// 仅当同时满足：
  /// 1. 早于今天 —— 不能覆盖今天或未来；
  /// 2. 当天确实没有打卡记录 —— 不在 [studied] 中；
  /// 3. 当天未被覆盖过 —— 不在 [covered] 中。
  static bool canCover({
    required DateTime day,
    required Set<DateTime> studied,
    required Set<DateTime> covered,
    required DateTime today,
  }) {
    final d = dayOnly(day);
    final t = dayOnly(today);
    if (!d.isBefore(t)) return false; // 今天或未来不可覆盖
    if (studied.contains(d)) return false; // 当天已有真实打卡
    if (covered.contains(d)) return false; // 已被冻结 / 补签过
    return true;
  }

  /// 本月剩余冻结次数。
  ///
  /// [freezesUsed] 为已用冻结日集合；只统计与 [today] 同自然月的部分，
  /// 所以历史月份的记录在跨月后不再占用额度（跨月自动重置）。
  static int freezesLeftThisMonth({
    required DateTime today,
    required Set<DateTime> freezesUsed,
  }) {
    final t = dayOnly(today);
    var used = 0;
    for (final d in freezesUsed) {
      final dd = dayOnly(d);
      if (dd.year == t.year && dd.month == t.month) used++;
    }
    return (freezesPerMonth - used).clamp(0, freezesPerMonth);
  }

  /// 补签卡发放判定。
  ///
  /// 规则：
  /// - 初始 [initialRepairCards] 张（由 [StreakGuardState.repairCards] 默认值给出，
  ///   本函数只在存量基础上**累加**达成奖励）；
  /// - 每达成连续 [repairCardEveryStreak] 天（7 / 14 / 21 / 28 …）补发 1 张；
  /// - 上限 [maxRepairCards] 张；
  /// - 同一「达成点」只发一次 —— 由 [grantedMilestones] 去重。
  ///
  /// 返回发放后的卡数与**本次新达成**的里程碑集合（已去重、未超上限的部分）。
  static ({int repairCards, Set<String> newlyGranted}) grantRepairCards({
    required int streakDays,
    required Set<String> grantedMilestones,
    required int repairCards,
  }) {
    var cards = repairCards;
    final newly = <String>{};
    if (streakDays >= repairCardEveryStreak) {
      final maxMilestone = (streakDays / repairCardEveryStreak).floor();
      for (var m = 1; m <= maxMilestone; m++) {
        final key = 'streak_${m * repairCardEveryStreak}';
        if (grantedMilestones.contains(key)) continue; // 该里程碑已发过
        if (cards >= maxRepairCards) break; // 封顶，不再发放
        cards++;
        newly.add(key);
      }
    }
    return (repairCards: cards, newlyGranted: newly);
  }
}
