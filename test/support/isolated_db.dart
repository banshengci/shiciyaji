import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一个**只属于当前测试文件**的临时数据库。
///
/// ## 为什么不能直接用 `inMemoryDatabasePath`
///
/// `inMemoryDatabasePath` 就是字符串 `:memory:`。sqflite_common_ffi 在进程内
/// 按「路径」路由连接，于是**两个并发跑的测试文件拿到的是同一个内存库**：
/// 会看到对方的表，甚至在对方 `close()` / `resetForTesting()` 时被连坐清空。
///
/// 实测症状（2026-09-16）：`flutter test` 全量跑时
/// `phase2_integration_test` 的「6. 阅读历史」会随机从 3 条变成 1 条 ——
/// 因为另一个文件正好在那一刻重开了同名库；单独跑那个文件必定通过。
///
/// 换成一个临时文件路径就彻底隔离了：`sqflite_common_ffi` 对文件库按路径独立开连接。
class IsolatedTestDb {
  final Database db;
  final Directory dir;

  IsolatedTestDb._(this.db, this.dir);

  /// 关闭连接并删除临时目录
  Future<void> dispose() async {
    try {
      await db.close();
    } catch (_) {
      // 已被 resetForTesting 关掉时会走到这里
    }
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清理失败不该让测试失败
    }
  }
}

/// 打开一个独享的测试库（见 [IsolatedTestDb] 的说明）。
Future<IsolatedTestDb> openIsolatedTestDatabase(String tag) async {
  final dir = Directory.systemTemp.createTempSync('shici_test_$tag');
  final path = '${dir.path}${Platform.pathSeparator}$tag.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  return IsolatedTestDb._(db, dir);
}
