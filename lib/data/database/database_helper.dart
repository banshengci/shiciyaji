import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../../core/s2t_converter.dart';
import '../../utils/pinyin_helper.dart';

/// SQLite 数据库帮助类
/// 负责：建表、初始数据加载、DAO 查询
class DatabaseHelper {
  static const _dbName = 'poetry.db';
  static const _dbVersion = 8;

  static Database? _db;
  static bool _initialized = false;
  static final bool _isMobile = Platform.isAndroid || Platform.isIOS;

  /// 初始化 SQLite（桌面端用 FFI，移动端用原生 sqflite）
  static void initFfi() {
    if (_initialized) return;
    if (!_isMobile) {
      ffi.sqfliteFfiInit();
      ffi.databaseFactory = ffi.databaseFactoryFfi;
    }
    _initialized = true;
  }

  /// 应用启动预热
  ///
  /// 在 `runApp` 之前调用，把「初始化驱动 → 打开/迁移数据库 → 装载预设计划」
  /// 这些耗时 IO 提前做完，避免首页首屏卡顿。
  ///
  /// 任何一步失败都不能阻塞启动：失败时仅记录日志，后续各 DAO 会惰性重试。
  static Future<void> preInit() async {
    final sw = Stopwatch()..start();
    try {
      initFfi();
      await database();
      await ensurePresetPlans();
      // 自动备份（默认开启，可在设置页关闭）；失败绝不影响启动
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('auto_backup') ?? true) {
          final f = await createAutoBackup();
          debugPrint('💾 自动备份已写入: ${f.path}');
        }
      } catch (e, st) {
        debugPrint('⚠️ 自动备份失败(不影响启动): $e\n$st');
      }
      debugPrint('🚀 数据库预热完成 (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      debugPrint('❌ 数据库预热失败: $e\n$st');
    }
  }

  /// 获取数据库实例
  static Future<Database> database() async {
    initFfi();
    if (_db != null) return _db!;
    final docsPath = await getApplicationSupportDirectory();
    final dbPath = p.join(docsPath.path, _dbName);
    final dbFile = File(dbPath);

    // 首次启动：从 assets 复制预置数据
    final existed = await dbFile.exists();
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    if (!existed) {
      try {
        await _loadInitialData(_db!);
        final pc = (await _db!.rawQuery('SELECT COUNT(*) FROM poems'))
            .first
            .values
            .first as int?;
        debugPrint('✅ 预置数据加载完成: poems=$pc');
      } catch (e, st) {
        debugPrint('❌ 加载预置数据失败: $e\n$st');
      }
    }

    // 迁移：确保新表存在（兼容旧数据库）
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS reading_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL,
        read_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_reading_history ON reading_history(poem_id)');

    // 迁移：收藏夹表（支持空收藏夹）
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    // 迁移已存在的收藏夹名到 collections 表
    await _db!.execute('''
      INSERT OR IGNORE INTO collections (name)
      SELECT DISTINCT collection_name FROM favorites
      WHERE collection_name IS NOT NULL
    ''');

    // 迁移：离线包安装表
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS installed_packs (
        pack_name TEXT PRIMARY KEY,
        description TEXT,
        source TEXT,
        count INTEGER NOT NULL DEFAULT 0,
        installed_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    return _db!;
  }

  // ============ 测试支持 ============

  /// 仅供测试：注入内存数据库并建表，避免读写真实文件系统
  @visibleForTesting
  static Future<void> setDatabaseForTesting(Database db) async {
    initFfi();
    await _db?.close();
    _db = db;
    invalidatePinyinIndex();
    await _onCreate(db, _dbVersion);
  }

  /// 仅供测试：重置单例状态，释放数据库连接
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _db?.close();
    _db = null;
    invalidatePinyinIndex();
  }

  // ============ 建表 ============

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE dynasties (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        start_year INTEGER,
        sort_order INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE authors (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        dynasty_id INTEGER,
        bio TEXT,
        birth_year TEXT,
        death_year TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT,
        sort_order INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE poems (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        author_id INTEGER,
        dynasty_id INTEGER,
        type TEXT,
        notes TEXT,
        translation TEXT,
        appreciation TEXT,
        background TEXT,
        source TEXT,
        sort_order INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE poem_categories (
        poem_id INTEGER,
        category_id INTEGER,
        PRIMARY KEY (poem_id, category_id)
      )
    ''');

    batch.execute('''
      CREATE TABLE favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL,
        collection_name TEXT DEFAULT '默认收藏',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    batch.execute('''
      CREATE TABLE collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    batch.execute('''
      CREATE TABLE study_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        poem_ids TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    batch.execute('''
      CREATE TABLE study_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL,
        study_date DATE DEFAULT CURRENT_DATE,
        status TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE study_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS reading_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL,
        read_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_reading_history ON reading_history(poem_id)');

    batch.execute('CREATE INDEX idx_poems_author ON poems(author_id)');
    batch.execute('CREATE INDEX idx_poems_dynasty ON poems(dynasty_id)');
    batch.execute('CREATE INDEX idx_favorites_poem ON favorites(poem_id)');
    // 同一首诗同一天、同一学习状态只允许一条记录：
    // 不同状态（如「学习中」与「复习」）视为不同记录，允许同日共存；
    // markPoemStudied 用 ConflictAlgorithm.replace，重复点击同一状态会就地更新而非产生脏行。
    batch.execute(
        'CREATE UNIQUE INDEX idx_study_records_unique ON study_records(poem_id, study_date, status)');

    // 离线包安装表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS installed_packs (
        pack_name TEXT PRIMARY KEY,
        description TEXT,
        source TEXT,
        count INTEGER NOT NULL DEFAULT 0,
        installed_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await batch.commit();
  }

  /// 数据库版本升级时的回调：合并新增预置数据到已有数据库
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion,
      {Future<String> Function(String path)? assetReader}) async {
    debugPrint('📦 数据库升级: v$oldVersion -> v$newVersion');
    // v1→v2: poems.json 从35首扩充到70首，合并新诗词
    if (oldVersion < 2) {
      await _loadInitialData(db, assetReader: assetReader);
      final pc = (await db.rawQuery('SELECT COUNT(*) FROM poems'))
          .first
          .values
          .first as int?;
      debugPrint('✅ 升级后合并完成: poems=$pc');
    }
    // v2→v3: 新增 installed_packs 表（离线包安装状态）
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS installed_packs (
          pack_name TEXT PRIMARY KEY,
          description TEXT,
          source TEXT,
          count INTEGER NOT NULL DEFAULT 0,
          installed_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      debugPrint('✅ installed_packs 表已创建');
    }
    // v3→v4: study_records 增加 (poem_id, study_date) 唯一约束
    if (oldVersion < 4) {
      // 历史脏数据：同一首诗同一天可能被重复打卡，先保留 id 最小的那条
      await db.execute('''
        DELETE FROM study_records
        WHERE id NOT IN (
          SELECT MIN(id) FROM study_records GROUP BY poem_id, study_date
        )
      ''');
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_study_records_unique ON study_records(poem_id, study_date)');
      debugPrint('✅ study_records 唯一索引已创建');
    }
    // v5→v6: 将所有诗词内容/标题/作者简介中的繁体字转为简体
    if (oldVersion < 6) {
      await _convertTraditionalToSimplified(db);
    }
    // v6→v7: 内容源升级（离线包改为名篇精选；预置内容补全）。
    // 数据区（诗词/作者/朝代/分类）全部来自 assets，可安全重建再生；
    // 用户数据（收藏/打卡/笔记/历史/计划）表保留，仅清理指向已移除诗词的悬空行。
    if (oldVersion < 7) {
      await _upgradeV7RebuildContent(db, assetReader: assetReader);
    }
    // v7→v8: 离线包扩充（74/51/19 → 约 600/500/150）。
    // 已安装的包按 id 区间清空后用新版 assets/data/packs/*.json 重装；
    // 用户收藏/笔记若指向被替换的旧 id，会在删包时一并清理（与卸载逻辑一致）。
    if (oldVersion < 8) {
      await _upgradeV8RefreshPacks(db, assetReader: assetReader);
    }
  }

  /// 仅供测试：模拟从 [oldVersion] 直接升级到当前版本。
  /// 测试环境的 rootBundle 不可用（flutter test 不打包 assets），
  /// 通过 [assetReader] 注入 File 读取器以真实 assets 为数据源。
  static Future<void> upgradeFromForTesting(
    Database db, int oldVersion, {
    Future<String> Function(String path)? assetReader,
  }) {
    return _onUpgrade(db, oldVersion, _dbVersion,
        assetReader: assetReader);
  }

  /// v7 迁移：重建诗词数据区 + 自动重装已装的离线包（新版名篇精选）。
  ///
  /// 历史版本问题：
  /// 1. 预置 poems.json 首启播种后永不刷新 → 老用户内容字段陈旧（无译文/赏析/背景）。
  /// 2. assets/data/packs/*.json 旧版是 chinese-poetry 全集原样截取（繁体、无内容、
  ///    宋词甚至无标题），且 importPack 用 conflictAlgorithm.ignore，已装包永不更新。
  ///
  /// v7 做法：清空可再生的数据区 → 重灌新版 poems.json → 清理悬空用户数据 →
  /// 对升级前已装的离线包用新版 packs/*.json 重装。
  static Future<void> _upgradeV7RebuildContent(Database db,
      {Future<String> Function(String path)? assetReader}) async {
    debugPrint('🔄 v7 数据区重建（内容刷新 + 离线包升级）...');
    assetReader ??= _defaultAssetReader();
    // 升级前已装的离线包（新包诗词与其 id 区间不同，需自动重装）
    final installedRows =
        await db.query('installed_packs', columns: ['pack_name']);
    final installed = {
      for (final r in installedRows) r['pack_name'] as String,
    };

    // 1) 清空纯数据表（顺序：先清关联表）
    await db.delete('poem_categories');
    await db.delete('poems');
    await db.delete('authors');
    await db.delete('dynasties');
    await db.delete('categories');
    await db.delete('installed_packs');

    // 2) 重灌新版预置数据（70 首名篇，含完整译文/赏析/背景/作者简介）
    await _loadInitialData(db, assetReader: assetReader);

    // 3) 清理悬空用户数据：收藏/打卡/笔记/历史中指向已移除诗词（旧离线包）的行
    const orphanWhere = 'poem_id NOT IN (SELECT id FROM poems)';
    final orphanTables = <String>[
      'favorites',
      'study_records',
      'study_notes',
      'reading_history',
    ];
    for (final t in orphanTables) {
      await db.delete(t, where: orphanWhere);
    }

    // 4) 自动重装升级前已装的离线包（新版名篇精选）
    if (installed.isNotEmpty) {
      debugPrint('📦 v7 重装已装离线包: $installed');
      for (final packName in installed) {
        try {
          final jsonString =
              await assetReader('assets/data/packs/$packName.json');
          await _importPackWithDb(db, jsonString);
        } catch (e) {
          debugPrint('⚠️ v7 重装离线包 $packName 失败: $e');
        }
      }
    }

    invalidatePinyinIndex();
    final pc = (await db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;
    debugPrint('✅ v7 完成：诗词共 $pc 首');
  }

  /// v8 迁移：已安装的离线包升级为扩充版（约 600/500/150 首）。
  ///
  /// 只处理 installed_packs 中已存在的包：按 id 区间删旧诗再 import 新包。
  /// 未安装的包不动，用户仍可在离线包商店手动安装。
  static Future<void> _upgradeV8RefreshPacks(Database db,
      {Future<String> Function(String path)? assetReader}) async {
    debugPrint('🔄 v8 离线包扩充刷新...');
    assetReader ??= _defaultAssetReader();
    final installedRows =
        await db.query('installed_packs', columns: ['pack_name']);
    if (installedRows.isEmpty) {
      debugPrint('✅ v8 完成：无已装离线包，跳过');
      return;
    }

    const ranges = <String, (int, int)>{
      'xiaoxue': (10000, 12000),
      'tangshi': (20000, 22000),
      'songci': (30000, 32000),
    };

    for (final row in installedRows) {
      final packName = row['pack_name'] as String;
      final range = ranges[packName];
      if (range == null) {
        debugPrint('⚠️ v8 未知离线包 $packName，跳过');
        continue;
      }
      final (idStart, idEnd) = range;
      try {
        await db.transaction((txn) async {
          await txn.delete('poem_categories',
              where: 'poem_id >= ? AND poem_id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('favorites',
              where: 'poem_id >= ? AND poem_id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('study_records',
              where: 'poem_id >= ? AND poem_id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('study_notes',
              where: 'poem_id >= ? AND poem_id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('reading_history',
              where: 'poem_id >= ? AND poem_id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('poems',
              where: 'id >= ? AND id < ?',
              whereArgs: [idStart, idEnd]);
          await txn.delete('installed_packs',
              where: 'pack_name = ?', whereArgs: [packName]);
        });
        final jsonString =
            await assetReader('assets/data/packs/$packName.json');
        final inserted = await _importPackWithDb(db, jsonString);
        debugPrint('✅ v8 重装 $packName：新插入 $inserted 首');
      } catch (e) {
        debugPrint('⚠️ v8 重装离线包 $packName 失败: $e');
      }
    }

    invalidatePinyinIndex();
    final pc = (await db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;
    debugPrint('✅ v8 完成：诗词共 $pc 首');
  }

  /// 将数据库中所有繁体字转为简体字
  ///
  /// poems.json 来源于 chinese-poetry 开源数据集，原始数据混用繁简，
  /// 导致很多诗词显示繁体（如「雲」「鳴」「鐘」等）。
  /// 此迁移一次性将 poems/authors 表中的 title/content/bio 字段全部转简体。
  /// 使用 assets/data/t2s_mapping.json（3751 对映射，由 opencc 生成）做精确转换。
  static Future<void> _convertTraditionalToSimplified(Database db) async {
    debugPrint('🔄 开始繁简转换迁移...');
    // 加载完整繁→简映射表
    Map<String, String> t2sMap;
    try {
      final jsonStr = await rootBundle.loadString('assets/data/t2s_mapping.json');
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
      t2sMap = raw.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      debugPrint('⚠️ 加载 t2s_mapping.json 失败，使用 S2TConverter 兜底: $e');
      t2sMap = S2TConverter.t2s;
    }

    String convert(String text) {
      final sb = StringBuffer();
      for (final rune in text.runes) {
        final ch = String.fromCharCode(rune);
        sb.write(t2sMap[ch] ?? ch);
      }
      return sb.toString();
    }

    // 1. 转换 poems 表
    int poemCount = 0;
    final poems = await db.query('poems', columns: ['id', 'title', 'content']);
    for (final row in poems) {
      final id = row['id'] as int;
      final title = row['title'] as String? ?? '';
      final content = row['content'] as String? ?? '';
      final newTitle = convert(title);
      final newContent = convert(content);
      if (newTitle != title || newContent != content) {
        await db.update(
          'poems',
          {'title': newTitle, 'content': newContent},
          where: 'id = ?',
          whereArgs: [id],
        );
        poemCount++;
      }
    }

    // 2. 转换 authors 表的 bio
    int authorCount = 0;
    final authors = await db.query('authors', columns: ['id', 'name', 'bio']);
    for (final row in authors) {
      final id = row['id'] as int;
      final bio = row['bio'] as String? ?? '';
      final newBio = convert(bio);
      if (newBio != bio) {
        await db.update('authors', {'bio': newBio},
            where: 'id = ?', whereArgs: [id]);
        authorCount++;
      }
    }

    debugPrint('✅ 繁简转换完成: poems=$poemCount, authors=$authorCount');
  }


  // ============ 初始数据加载 ============

  /// 加载 asset 文本的默认实现（生产用 rootBundle；测试可注入 File 读取器，
  /// 因为 flutter test 环境不打包 assets、rootBundle 不可用）。
  static Future<String> Function(String path) _defaultAssetReader() =>
      (path) => rootBundle.loadString(path);

  static Future<void> _loadInitialData(Database db,
      {Future<String> Function(String path)? assetReader}) async {
    assetReader ??= _defaultAssetReader();
    final jsonString = await assetReader('assets/data/poems.json');
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final batch = db.batch();

    // 朝代
    for (final d in (data['dynasties'] as List)) {
      batch.insert('dynasties', d as Map<String, dynamic>,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // 作者
    for (final a in (data['authors'] as List)) {
      batch.insert('authors', a as Map<String, dynamic>,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // 分类
    for (final c in (data['categories'] as List)) {
      batch.insert('categories', c as Map<String, dynamic>,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // 诗词
    for (final p in (data['poems'] as List)) {
      final pm = p as Map<String, dynamic>;
      final categoryIds = pm.remove('category_ids') as List?;
      batch.insert('poems', pm, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (categoryIds != null) {
        for (final cid in categoryIds) {
          batch.insert(
              'poem_categories',
              {
                'poem_id': pm['id'],
                'category_id': cid,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }

    await batch.commit();
    // 诗词集合已变化，拼音索引需重建
    invalidatePinyinIndex();
  }

  // ============ DAO: 诗词查询 ============

  /// 获取所有诗词（带作者名+朝代名）
  static Future<List<Poem>> getAllPoems({
    int? dynastyId,
    int? authorId,
    int? categoryId,
    String? type,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await database();
    final where = <String>[];
    final args = <dynamic>[];

    if (dynastyId != null) {
      where.add('p.dynasty_id = ?');
      args.add(dynastyId);
    }
    if (authorId != null) {
      where.add('p.author_id = ?');
      args.add(authorId);
    }
    if (type != null) {
      where.add('p.type = ?');
      args.add(type);
    }

    String fromClause =
        'poems p LEFT JOIN authors a ON p.author_id = a.id LEFT JOIN dynasties d ON p.dynasty_id = d.id';
    if (categoryId != null) {
      fromClause += ' JOIN poem_categories pc ON p.id = pc.poem_id';
      where.add('pc.category_id = ?');
      args.add(categoryId);
    }

    final whereClause = where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM $fromClause
      $whereClause
      ORDER BY p.sort_order, p.id
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    return results.map(Poem.fromMap).toList();
  }

  /// 卡片标签用：poem_id → 分类名列表（按 sort_order，已做繁简归一）
  ///
  /// 一次查询把全部关联取回，避免列表里逐首查一遍分类造成的 N+1。
  static Future<Map<int, List<String>>> getPoemCategoryMap() async {
    final db = await database();
    final rows = await db.rawQuery('''
      SELECT pc.poem_id AS poem_id, c.name AS name
      FROM poem_categories pc
      JOIN categories c ON pc.category_id = c.id
      ORDER BY c.sort_order, c.id
    ''');
    final out = <int, List<String>>{};
    for (final r in rows) {
      final id = r['poem_id'] as int?;
      final name = S2TConverter.apply(r['name'] as String? ?? '');
      if (id == null || name.isEmpty) continue;
      out.putIfAbsent(id, () => <String>[]).add(name);
    }
    return out;
  }

  /// 卡片收藏态用：一次性取回全部已收藏的诗词 id
  static Future<Set<int>> getFavoritePoemIds() async {
    final db = await database();
    final rows = await db.query('favorites', columns: <String>['poem_id']);
    return rows
        .map((r) => r['poem_id'])
        .whereType<int>()
        .toSet();
  }

  /// 获取单首诗词详情
  static Future<Poem?> getPoemById(int id) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE p.id = ?
    ''', [id]);
    if (results.isEmpty) return null;
    return Poem.fromMap(results.first);
  }

  /// 按 id 批量获取诗词（保持传入顺序；不存在 / 已删除的 id 自动跳过）
  ///
  /// 用于学习计划详情、背诵自测等需要按 id 列表取诗的场景，
  /// 避免逐条 `getPoemById` 造成的 N 次查询。
  static Future<List<Poem>> getPoemsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await database();
    final byId = <int, Poem>{};
    // SQLite 变量上限 999，按批拆分避免超大计划出错
    for (var i = 0; i < ids.length; i += 500) {
      final end = (i + 500) > ids.length ? ids.length : i + 500;
      final chunk = ids.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT p.*, a.name AS author_name, d.name AS dynasty_name
        FROM poems p
        LEFT JOIN authors a ON p.author_id = a.id
        LEFT JOIN dynasties d ON p.dynasty_id = d.id
        WHERE p.id IN ($placeholders)
      ''', chunk);
      for (final r in rows) {
        final poem = Poem.fromMap(r);
        byId[poem.id] = poem;
      }
    }
    // 按传入顺序还原
    return ids
        .map((id) => byId[id])
        .whereType<Poem>()
        .toList();
  }

  /// 记录一次「背诵自测」结果
  ///
  /// remembered=true 记为「自测通过」，false 记为「自测未过」。
  /// 同一天同一首同一结果只保留一条（依赖 study_records 唯一索引去重）。
  static Future<void> recordRecall(int poemId, {required bool remembered}) async {
    final db = await database();
    await db.insert(
      'study_records',
      {'poem_id': poemId, 'status': remembered ? '自测通过' : '自测未过'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 拼音索引缓存（懒加载，首次拼音搜索时构建一次并缓存）
  ///
  /// 记录每首诗的「全拼串」与「首字母串」，例如《静夜思》正文首句
  /// 床前明月光 → full: chuangqianmingyueguang，initials: cqmyg。
  /// 诗词增删（导入离线包、加载预置数据）后需调用 [invalidatePinyinIndex]。
  static List<({int id, String full, String initials})>? _pinyinIndex;

  /// 正在构建中的任务（防止并发重复构建）
  static Future<void>? _pinyinBuilding;

  /// 数据代次：诗词表每次增删都自增，用于丢弃「构建期间数据已变」的脏索引
  static int _pinyinGeneration = 0;

  static void invalidatePinyinIndex() {
    _pinyinIndex = null;
    _pinyinBuilding = null;
    _pinyinGeneration++;
  }

  /// 预热拼音索引（不阻塞调用方，供启动后台调用）
  ///
  /// 2000 首规模构建约 1 秒 CPU，启动时预热可让用户输入拼音时零等待。
  static void warmPinyinIndex() {
    _ensurePinyinIndex().ignore();
  }

  /// 获取可用的拼音索引（必要时构建）
  ///
  /// 若构建期间诗词表被改动，结果会被丢弃并重试，最多 3 次后返回当前已知结果，
  /// 保证调用方永远拿到非空列表、不会因缓存竞态而崩溃。
  static Future<List<({int id, String full, String initials})>>
      _ensurePinyinIndex() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final cached = _pinyinIndex;
      if (cached != null) return cached;
      // 已有构建在进行 -> 复用，避免并发重复计算
      await (_pinyinBuilding ??= _buildPinyinIndex());
    }
    return _pinyinIndex ?? const [];
  }

  static Future<void> _buildPinyinIndex() async {
    final generation = _pinyinGeneration;
    try {
      final db = await database();
      final rows = await db.query('poems', columns: ['id', 'title', 'content']);
      final index = <({int id, String full, String initials})>[];
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final text = '${r['title'] ?? ''}${r['content'] ?? ''}';
        final pairs = PinyinHelper.splitWithPinyin(text);
        final full = StringBuffer();
        final initials = StringBuffer();
        for (final e in pairs) {
          if (e.py.isEmpty) continue;
          full.write(e.py);
          initials.write(e.py[0]);
        }
        index.add((
          id: r['id'] as int,
          full: full.toString().toLowerCase(),
          initials: initials.toString().toLowerCase(),
        ));
        // 每 200 首让出事件循环，避免长时间阻塞 UI 线程
        if (i % 200 == 199) await Future<void>.delayed(Duration.zero);
      }
      // 构建期间诗词表发生过增删 -> 本次结果已过期，丢弃
      if (generation == _pinyinGeneration) _pinyinIndex = index;
    } finally {
      if (generation == _pinyinGeneration) _pinyinBuilding = null;
    }
  }

  /// 搜索诗词（标题/内容/作者名）
  ///
  /// 匹配策略（按优先级返回）：
  /// 1) 完整关键词匹配 title/content/author
  /// 2) 关键词按字拆解，content 中按顺序出现每个字（容错记错字；仅 4 字及以上启用）
  /// 3) 朝代/体裁过滤可叠加在 1+2 之上
  ///
  /// 另：纯英文字母关键词走**拼音索引**，支持全拼（chuangqian）与首字母（cq）。
  static Future<List<Poem>> searchPoems(String keyword,
      {int? dynastyId, String? type}) async {
    final db = await database();
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return <Poem>[];

    // 0) 纯拼音：全拼或首字母缩写（不改动原有中文 SQL 路径，也不影响其性能）
    if (RegExp(r'^[a-zA-Z]+$').hasMatch(trimmed)) {
      final index = await _ensurePinyinIndex();
      final kw = trimmed.toLowerCase();
      final matched = <int>[];
      for (final e in index) {
        if (e.full.contains(kw) || e.initials.contains(kw)) {
          matched.add(e.id);
        }
      }
      if (matched.isEmpty) return <Poem>[];
      var poems = await getPoemsByIds(matched);
      if (dynastyId != null) {
        poems = poems.where((p) => p.dynastyId == dynastyId).toList();
      }
      if (type != null) {
        poems = poems.where((p) => p.type == type).toList();
      }
      return poems;
    }

    // 1) 完整词匹配
    final kw = '%$trimmed%';
    final likeWhere = <String>[
      '(p.title LIKE ? OR p.content LIKE ? OR a.name LIKE ?)'
    ];
    final likeArgs = <dynamic>[kw, kw, kw];

    // 2) 拆字匹配：把关键词里的字用 LIKE 串起来
    //    采用「连续字面量 LIKE」模式：例如 "国破山河在" -> LIKE '%国%破%山%河%在%'
    //    速度极快（单次扫描、能走索引），能命中原文片段/漏字场景
    //    不支持错字（如「窗前」->「床前」不命中）—— 这是性能与容错的权衡
    final charWhere = <String>[];
    final charArgs = <dynamic>[];
    final distinctChars = <String>{};
    for (final rune in trimmed.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(ch)) {
        distinctChars.add(ch);
      }
    }
    if (distinctChars.length >= 4) {
      // 单次 LIKE 模式：所有字按顺序出现即可命中
      final allCharsPattern = '%${distinctChars.join('%')}%';
      charWhere.add('p.content LIKE ?');
      charArgs.add(allCharsPattern);
    }

    // 合并两段 WHERE（UNION ALL 去重：先排完整匹配的，再排拆字匹配）
    final filterWhere = <String>[];
    final filterArgs = <dynamic>[];
    if (dynastyId != null) {
      filterWhere.add('p.dynasty_id = ?');
      filterArgs.add(dynastyId);
    }
    if (type != null) {
      filterWhere.add('p.type = ?');
      filterArgs.add(type);
    }
    final filterSql =
        filterWhere.isEmpty ? '' : ' AND ${filterWhere.join(' AND ')}';

    const baseSelect = '''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
    ''';

    // 完整匹配（保留 ORDER BY）
    final exactResults = await db.rawQuery('''
      $baseSelect
      WHERE ${likeWhere.join(' AND ')} $filterSql
      ORDER BY p.sort_order, p.id
      LIMIT 200
    ''', [...likeArgs, ...filterArgs]);

    // 拆字匹配
    final fuzzyResults = charWhere.isEmpty
        ? const <Map<String, Object?>>[]
        : await db.rawQuery('''
      $baseSelect
      WHERE ${charWhere.join(' AND ')} $filterSql
      ORDER BY p.sort_order, p.id
      LIMIT 200
    ''', [...charArgs, ...filterArgs]);

    // 合并：完整匹配优先，去重
    final seen = <int>{};
    final merged = <Poem>[];
    for (final r in [...exactResults, ...fuzzyResults]) {
      final id = r['id'] as int;
      if (seen.add(id)) {
        merged.add(Poem.fromMap(r));
      }
    }
    return merged;
  }

  /// 随机一首
  static Future<Poem?> getRandomPoem() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      ORDER BY RANDOM()
      LIMIT 1
    ''');
    if (results.isEmpty) return null;
    return Poem.fromMap(results.first);
  }

  /// 每日推荐（基于日期确定性算法）
  static Future<Poem?> getDailyPoem() async {
    final db = await database();
    final count = await db.rawQuery('SELECT COUNT(*) AS c FROM poems');
    final total = count.first['c'] as int;
    if (total == 0) return null;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    // 按序偏移取值，而不是拿 id 直接取模：
    // 导入离线包后 id 段是 1-70 / 10000+ / 20000+ / 30000+，并不连续，
    // 用 id = (dayOfYear % total) + 1 命中不了就会退化成每次随机。
    final offset = dayOfYear % total;
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      ORDER BY p.id
      LIMIT 1 OFFSET ?
    ''', [offset]);
    if (results.isEmpty) {
      return getRandomPoem();
    }
    return Poem.fromMap(results.first);
  }

  // ============ DAO: 朝代/作者/分类 ============

  static Future<List<Dynasty>> getAllDynasties() async {
    final db = await database();
    final results = await db.query('dynasties', orderBy: 'sort_order');
    return results.map(Dynasty.fromMap).toList();
  }

  static Future<List<Author>> getAllAuthors() async {
    final db = await database();
    final results = await db.query('authors', orderBy: 'id');
    return results.map(Author.fromMap).toList();
  }

  // ============ 飞花令：按字找诗 ============

  /// 找到 title 或 content 中包含 [char] 的全部诗词（随机乱序，供飞花令使用）
  static Future<List<Poem>> getPoemsContainingChar(String char,
      {int? dynastyId}) async {
    final db = await database();
    final where = <String>['(p.title LIKE ? OR p.content LIKE ?)'];
    final args = <dynamic>['%$char%', '%$char%'];
    if (dynastyId != null) {
      where.add('p.dynasty_id = ?');
      args.add(dynastyId);
    }
    final rows = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE ${where.join(' AND ')}
      ORDER BY RANDOM()
    ''', args);
    return rows.map(Poem.fromMap).toList();
  }

  /// 随机获取不含 [char] 的诗词（飞花令干扰项用）
  ///
  /// 从全量诗词中排除 title/content 包含 [char] 的，随机取 [count] 首。
  static Future<List<Poem>> getRandomPoemsExcludingChar(String char,
      {int count = 40}) async {
    final db = await database();
    final rows = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE p.title NOT LIKE ? AND p.content NOT LIKE ?
      ORDER BY RANDOM()
      LIMIT ?
    ''', ['%$char%', '%$char%', count]);
    return rows.map(Poem.fromMap).toList();
  }

  /// 随机选一个「至少出现在 [minCount] 首诗中」的汉字
  ///
  /// 飞花令选字用：排除标点/数字/英文字母，只取内容中的汉字，
  /// 统计每个字出现的诗数，再按频次加权随机抽一个。
  /// 不看标题，避免仅因篇名出现而极少真正入句的字。
  static Future<String?> getRandomPlayChar({int minCount = 3}) async {
    final poems = await getAllPoems(limit: 2000);
    if (poems.isEmpty) return null;
    // 统计每个汉字出现在几首不同的诗中
    final charToPoemCount = <String, int>{};
    for (final p in poems) {
      final seen = <String>{};
      for (final rune in p.content.runes) {
        if (rune < 0x4E00 || rune > 0x9FFF) continue;
        final ch = String.fromCharCode(rune);
        if (seen.add(ch)) {
          charToPoemCount[ch] = (charToPoemCount[ch] ?? 0) + 1;
        }
      }
    }
    // 过滤：至少出现在 minCount 首诗中，且不是太常见的字（如「的」「了」）
    // 上限放宽到 80%，避免扩充包后可选令字过少
    final candidates = charToPoemCount.entries
        .where((e) => e.value >= minCount && e.value <= poems.length * 0.8)
        .toList();
    if (candidates.isEmpty) {
      // 退回更宽松的下限
      final loose = charToPoemCount.entries
          .where((e) => e.value >= 2 && e.value <= poems.length * 0.8)
          .toList();
      if (loose.isEmpty) return null;
      final w = loose.fold<int>(0, (s, e) => s + e.value);
      var r = DateTime.now().millisecondsSinceEpoch % w;
      for (final e in loose) {
        r -= e.value;
        if (r < 0) return e.key;
      }
      return loose.last.key;
    }
    // 按频次加权随机
    final totalWeight = candidates.fold<int>(0, (s, e) => s + e.value);
    var r = DateTime.now().millisecondsSinceEpoch % totalWeight;
    for (final e in candidates) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return candidates.last.key;
  }

  static Future<Author?> getAuthorById(int id) async {
    final db = await database();
    final results = await db.query('authors', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return Author.fromMap(results.first);
  }

  /// 诗人列表（含作品数），按作品数倒序 —— 李白/杜甫这类大家自然排在前面
  ///
  /// 只返回**确有作品**的诗人（INNER JOIN），避免离线包卸载后残留空作者。
  /// [dynastyId] 可选，按朝代过滤。
  static Future<List<({Author author, int poemCount})>> getAuthorsWithPoemCount(
      {int? dynastyId}) async {
    final db = await database();
    final where = dynastyId != null ? 'WHERE a.dynasty_id = ?' : '';
    final args = dynastyId != null ? [dynastyId] : <dynamic>[];
    final rows = await db.rawQuery('''
      SELECT a.*, COUNT(p.id) AS poem_count
      FROM authors a
      JOIN poems p ON p.author_id = a.id
      $where
      GROUP BY a.id
      ORDER BY poem_count DESC, a.id
    ''', args);
    return rows
        .map((r) => (
              author: Author.fromMap(r),
              poemCount: (r['poem_count'] as int?) ?? 0,
            ))
        .toList();
  }

  /// 某位诗人的全部作品（按 sort_order/id，稳定顺序）
  static Future<List<Poem>> getPoemsByAuthor(int authorId) async {
    final db = await database();
    final rows = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name
      FROM poems p
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE p.author_id = ?
      ORDER BY p.sort_order, p.id
    ''', [authorId]);
    return rows.map(Poem.fromMap).toList();
  }

  static Future<List<Category>> getCategoriesByType(String type) async {
    final db = await database();
    final results = await db.query('categories',
        where: 'type = ?', whereArgs: [type], orderBy: 'sort_order');
    return results.map(Category.fromMap).toList();
  }

  static Future<List<Category>> getAllCategories() async {
    final db = await database();
    final results = await db.query('categories', orderBy: 'type, sort_order');
    return results.map(Category.fromMap).toList();
  }

  /// 库内实际出现过的体裁取值（`poems.type` 去重）。
  ///
  /// 筛选选项据此生成，而不是在页面里写死一份列表 —— 写死的那份会随着
  /// 诗集包更新慢慢变成假选项（点了筛不出任何东西），也会漏掉新体裁。
  /// 次序由调用方决定，这里只管「有哪些」。
  static Future<List<String>> getPoemTypes() async {
    final db = await database();
    final rows = await db.rawQuery(
      "SELECT DISTINCT type FROM poems "
      "WHERE type IS NOT NULL AND TRIM(type) <> '' ORDER BY type",
    );
    return rows
        .map((r) => (r['type'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // ============ DAO: 收藏 ============

  static Future<bool> isFavorite(int poemId) async {
    final db = await database();
    final results =
        await db.query('favorites', where: 'poem_id = ?', whereArgs: [poemId]);
    return results.isNotEmpty;
  }

  static Future<void> addFavorite(int poemId,
      {String collection = '默认收藏'}) async {
    final db = await database();
    // 确保收藏夹存在
    await db.insert('collections', {'name': collection},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
        'favorites',
        {
          'poem_id': poemId,
          'collection_name': collection,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> removeFavorite(int poemId) async {
    final db = await database();
    await db.delete('favorites', where: 'poem_id = ?', whereArgs: [poemId]);
  }

  static Future<List<Poem>> getFavoritePoems() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name, f.created_at
      FROM favorites f
      JOIN poems p ON f.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      ORDER BY f.created_at DESC
    ''');
    return results.map(Poem.fromMap).toList();
  }

  // ---- 收藏夹管理 ----

  /// 获取所有收藏夹（含诗词数量，支持空夹）
  static Future<List<Map<String, dynamic>>> getCollections() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT c.name AS name, COUNT(f.poem_id) AS cnt
      FROM collections c
      LEFT JOIN favorites f ON c.name = f.collection_name
      GROUP BY c.name
      ORDER BY c.created_at
    ''');
    return results;
  }

  /// 创建空收藏夹
  static Future<void> createCollection(String name) async {
    final db = await database();
    await db.insert('collections', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 重命名收藏夹（同步 favorites）
  static Future<void> renameCollection(String oldName, String newName) async {
    final db = await database();
    await db.update('collections', {'name': newName},
        where: 'name = ?', whereArgs: [oldName]);
    await db.update('favorites', {'collection_name': newName},
        where: 'collection_name = ?', whereArgs: [oldName]);
  }

  /// 删除收藏夹（含其下所有收藏）
  static Future<void> deleteCollection(String name) async {
    final db = await database();
    await db
        .delete('favorites', where: 'collection_name = ?', whereArgs: [name]);
    await db.delete('collections', where: 'name = ?', whereArgs: [name]);
  }

  /// 按收藏夹获取诗词
  static Future<List<Poem>> getFavoritePoemsByCollection(
      String collectionName) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name, f.created_at
      FROM favorites f
      JOIN poems p ON f.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE f.collection_name = ?
      ORDER BY f.created_at DESC
    ''', [collectionName]);
    return results.map(Poem.fromMap).toList();
  }

  /// 从指定收藏夹移除一首
  static Future<void> removeFavoriteFromCollection(
      int poemId, String collectionName) async {
    final db = await database();
    await db.delete('favorites',
        where: 'poem_id = ? AND collection_name = ?',
        whereArgs: [poemId, collectionName]);
  }

  // ============ DAO: 学习计划 ============

  static Future<List<StudyPlan>> getStudyPlans() async {
    final db = await database();
    final results = await db.query('study_plans', orderBy: 'created_at DESC');
    return results.map(StudyPlan.fromMap).toList();
  }

  static Future<int> createStudyPlan(
      String name, String? description, List<int> poemIds) async {
    final db = await database();
    return await db.insert('study_plans', {
      'name': name,
      'description': description,
      'poem_ids': jsonEncode(poemIds),
    });
  }

  static Future<void> deleteStudyPlan(int id) async {
    final db = await database();
    await db.delete('study_plans', where: 'id = ?', whereArgs: [id]);
  }

  /// 往学习计划追加诗词（自动去重，保持原有顺序）
  ///
  /// 返回实际新增的首数；计划不存在时返回 0。
  static Future<int> addPoemsToPlan(int planId, List<int> poemIds) async {
    if (poemIds.isEmpty) return 0;
    final db = await database();
    final rows =
        await db.query('study_plans', where: 'id = ?', whereArgs: [planId]);
    if (rows.isEmpty) return 0;
    final existing = StudyPlan.fromMap(rows.first).poemIds.toSet();
    final merged = <int>[...StudyPlan.fromMap(rows.first).poemIds];
    for (final id in poemIds) {
      if (existing.add(id)) merged.add(id);
    }
    final added = merged.length - StudyPlan.fromMap(rows.first).poemIds.length;
    if (added == 0) return 0;
    await db.update('study_plans', {'poem_ids': jsonEncode(merged)},
        where: 'id = ?', whereArgs: [planId]);
    return added;
  }

  /// 给定诗词 id 集合里「已学」的数量（用于学习计划进度）
  static Future<int> getStudiedCountIn(List<int> poemIds) async {
    if (poemIds.isEmpty) return 0;
    final db = await database();
    var total = 0;
    // SQLite 变量上限 999，按批拆分避免超大计划出错
    for (var i = 0; i < poemIds.length; i += 500) {
      final chunk = poemIds.sublist(
          i, (i + 500) > poemIds.length ? poemIds.length : i + 500);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT COUNT(DISTINCT poem_id) AS c FROM study_records '
          'WHERE poem_id IN ($placeholders)',
          chunk);
      total += r.first['c'] as int;
    }
    return total;
  }

  /// 收藏夹数量
  static Future<int> getCollectionCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM collections');
    return r.first['c'] as int;
  }

  // ============ DAO: 学习记录 ============

  static Future<void> markPoemStudied(int poemId,
      {String status = '学习中'}) async {
    final db = await database();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.insert(
        'study_records',
        {
          'poem_id': poemId,
          'study_date': today,
          'status': status,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<StudyRecord>> getStudyRecords() async {
    final db = await database();
    final results = await db.query('study_records', orderBy: 'study_date DESC');
    return results.map(StudyRecord.fromMap).toList();
  }

  static Future<int> getStudiedCount() async {
    final db = await database();
    final results = await db
        .rawQuery('SELECT COUNT(DISTINCT poem_id) AS c FROM study_records');
    return results.first['c'] as int;
  }

  // ---- 艾宾浩斯遗忘曲线复习 ----
  // 间隔序列：第n次学习后，n天后复习（n=1→1天，2→2天，3→4天，4→7天，5→15天，6+→30天）
  static const List<int> _ebbinghausIntervals = [1, 2, 4, 7, 15, 30];

  /// 今日待复习的诗词（含复习次数、上次复习日、下次复习日）
  static Future<List<Map<String, dynamic>>> getTodayReviewItems() async {
    final db = await database();
    final results = await db.rawQuery('''
      WITH stats AS (
        SELECT poem_id, MAX(study_date) AS last_date, COUNT(DISTINCT study_date) AS review_count
        FROM study_records GROUP BY poem_id
      ),
      review AS (
        SELECT s.poem_id, s.last_date, s.review_count,
          CASE s.review_count
            WHEN 1 THEN date(s.last_date, '+1 day')
            WHEN 2 THEN date(s.last_date, '+2 days')
            WHEN 3 THEN date(s.last_date, '+4 days')
            WHEN 4 THEN date(s.last_date, '+7 days')
            WHEN 5 THEN date(s.last_date, '+15 days')
            ELSE date(s.last_date, '+30 days')
          END AS next_review
        FROM stats s
      )
      SELECT p.id, p.title, p.content, p.author_id, p.dynasty_id, p.sort_order, p.type,
             a.name AS author_name, d.name AS dynasty_name,
             r.last_date, r.review_count, r.next_review
      FROM review r
      JOIN poems p ON r.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE r.last_date < date('now')
        AND r.next_review <= date('now')
        AND r.review_count < ?
      ORDER BY r.next_review, r.review_count DESC
    ''', [_ebbinghausIntervals.length]);
    return results;
  }

  /// 今日待复习数量（用于角标）
  static Future<int> getTodayReviewCount() async {
    final db = await database();
    final results = await db.rawQuery('''
      WITH stats AS (
        SELECT poem_id, MAX(study_date) AS last_date, COUNT(DISTINCT study_date) AS review_count
        FROM study_records GROUP BY poem_id
      )
      SELECT COUNT(*) AS c FROM stats
      WHERE last_date < date('now')
        AND CASE review_count
              WHEN 1 THEN date(last_date, '+1 day')
              WHEN 2 THEN date(last_date, '+2 days')
              WHEN 3 THEN date(last_date, '+4 days')
              WHEN 4 THEN date(last_date, '+7 days')
              WHEN 5 THEN date(last_date, '+15 days')
              ELSE date(last_date, '+30 days')
            END <= date('now')
        AND review_count < ?
    ''', [_ebbinghausIntervals.length]);
    return results.first['c'] as int;
  }

  /// 已掌握数量（完成全部艾宾浩斯周期 review_count >= 6）
  static Future<int> getMasteredCount() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM (
        SELECT poem_id, COUNT(DISTINCT study_date) AS rc
        FROM study_records GROUP BY poem_id
        HAVING rc >= ?
      )
    ''', [_ebbinghausIntervals.length]);
    return results.first['c'] as int;
  }

  /// 根据复习次数返回下次复习间隔（天）
  static int nextInterval(int reviewCount) {
    if (reviewCount <= 0) return 0;
    if (reviewCount > _ebbinghausIntervals.length) {
      return _ebbinghausIntervals.last;
    }
    return _ebbinghausIntervals[reviewCount - 1];
  }

  static Future<int> getStreakDays() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT DISTINCT study_date FROM study_records ORDER BY study_date DESC
    ''');
    if (results.isEmpty) return 0;
    int streak = 0;
    var expected = DateTime.now();
    for (final row in results) {
      final dateStr = row['study_date'] as String;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      if (date.year == expected.year &&
          date.month == expected.month &&
          date.day == expected.day) {
        streak++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (streak == 0) {
        // 今天没学，但昨天学了
        final yesterday = expected.subtract(const Duration(days: 1));
        if (date.year == yesterday.year &&
            date.month == yesterday.month &&
            date.day == yesterday.day) {
          streak++;
          expected = yesterday.subtract(const Duration(days: 1));
        } else {
          break;
        }
      } else {
        break;
      }
    }
    return streak;
  }

  // ============ 预设学习计划 ============

  static Future<void> ensurePresetPlans() async {
    final db = await database();

    /// 按朝代名取诗词 id（写死 dynasty_id 在数据扩充/离线包导入后极易失效）
    Future<List<int>> idsByDynasty(String dynastyName, int limit) async {
      final rows = await db.rawQuery('''
        SELECT p.id FROM poems p
        JOIN dynasties d ON p.dynasty_id = d.id
        WHERE d.name = ?
        ORDER BY p.sort_order, p.id
        LIMIT ?
      ''', [dynastyName, limit]);
      return rows.map((e) => e['id'] as int).toList();
    }

    /// 按分类名取诗词 id
    Future<List<int>> idsByCategory(String categoryName) async {
      final rows = await db.rawQuery('''
        SELECT p.id FROM poems p
        JOIN poem_categories pc ON p.id = pc.poem_id
        JOIN categories c ON pc.category_id = c.id
        WHERE c.name = ?
        ORDER BY p.sort_order, p.id
      ''', [categoryName]);
      return rows.map((e) => e['id'] as int).toList();
    }

    Future<void> ensure(
        String name, String description, List<int> ids) async {
      if (ids.isEmpty) {
        debugPrint('⚠️ 预设计划「$name」未匹配到诗词，已跳过');
        return;
      }
      final existing =
          await db.query('study_plans', where: 'name = ?', whereArgs: [name]);
      if (existing.isNotEmpty) return;
      await db.insert('study_plans', {
        'name': name,
        'description': description,
        'poem_ids': jsonEncode(ids),
      });
      debugPrint('➕ 预设计划「$name」已创建 (${ids.length} 首)');
    }

    await ensure('唐诗三百首', '精选唐诗名篇，循序渐进学习',
        await idsByDynasty('唐', 20));
    await ensure('宋词精选', '豪放与婉约，宋词名篇',
        await idsByDynasty('宋', 15));
    await ensure('小学必背', '小学生必背古诗词',
        await idsByCategory('必背'));
  }

  // ============ DAO: 阅读历史 ============

  static Future<void> addReadingHistory(int poemId) async {
    final db = await database();
    final now = DateTime.now().toIso8601String();
    // 先删除旧记录（去重），再插入
    await db
        .delete('reading_history', where: 'poem_id = ?', whereArgs: [poemId]);
    await db.insert('reading_history', {
      'poem_id': poemId,
      'read_at': now,
    });
    // 只保留最近20条
    final count =
        await db.rawQuery('SELECT COUNT(*) AS c FROM reading_history');
    final total = count.first['c'] as int;
    if (total > 20) {
      await db.rawDelete('''
        DELETE FROM reading_history WHERE id NOT IN (
          SELECT id FROM reading_history ORDER BY read_at DESC LIMIT 20
        )
      ''');
    }
  }

  static Future<List<Poem>> getReadingHistory() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT p.*, a.name AS author_name, d.name AS dynasty_name, rh.read_at
      FROM reading_history rh
      JOIN poems p ON rh.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      ORDER BY rh.read_at DESC
    ''');
    return results.map(Poem.fromMap).toList();
  }

  // ============ DAO: 上一篇/下一篇 ============

  static Future<int?> getPrevPoemId(int currentId) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT id FROM poems WHERE sort_order <= (SELECT sort_order FROM poems WHERE id = ?)
        AND id != ? ORDER BY sort_order DESC, id DESC LIMIT 1
    ''', [currentId, currentId]);
    if (results.isEmpty) return null;
    return results.first['id'] as int;
  }

  static Future<int?> getNextPoemId(int currentId) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT id FROM poems WHERE sort_order >= (SELECT sort_order FROM poems WHERE id = ?)
        AND id != ? ORDER BY sort_order ASC, id ASC LIMIT 1
    ''', [currentId, currentId]);
    if (results.isEmpty) return null;
    return results.first['id'] as int;
  }

  static Future<List<int>> getAllPoemIds() async {
    final db = await database();
    final results =
        await db.query('poems', columns: ['id'], orderBy: 'sort_order, id');
    return results.map((e) => e['id'] as int).toList();
  }

  // ============ DAO: 热力图数据 ============

  static Future<Map<String, int>> getStudyDatesCount() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT study_date, COUNT(*) AS cnt FROM study_records
      GROUP BY study_date ORDER BY study_date DESC LIMIT 365
    ''');
    final map = <String, int>{};
    for (final row in results) {
      final date = row['study_date'] as String;
      final cnt = row['cnt'] as int;
      map[date] = cnt;
    }
    return map;
  }

  // ============ DAO: 学习统计 ============

  /// 已学诗词的朝代分布
  static Future<Map<String, int>> getStudiedDynastyDistribution() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT IFNULL(d.name, '未知') AS dynasty, COUNT(DISTINCT s.poem_id) AS cnt
      FROM study_records s
      JOIN poems p ON s.poem_id = p.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      GROUP BY dynasty ORDER BY cnt DESC
    ''');
    final map = <String, int>{};
    for (final row in results) {
      map[row['dynasty'] as String] = row['cnt'] as int;
    }
    return map;
  }

  /// 已学诗词的作者分布（取前 N）
  static Future<Map<String, int>> getStudiedAuthorDistribution(
      {int limit = 10}) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT IFNULL(a.name, '佚名') AS author, COUNT(DISTINCT s.poem_id) AS cnt
      FROM study_records s
      JOIN poems p ON s.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      GROUP BY author ORDER BY cnt DESC LIMIT ?
    ''', [limit]);
    final map = <String, int>{};
    for (final row in results) {
      map[row['author'] as String] = row['cnt'] as int;
    }
    return map;
  }

  /// 收藏诗词的朝代分布
  static Future<Map<String, int>> getFavoriteDynastyDistribution() async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT IFNULL(d.name, '未知') AS dynasty, COUNT(*) AS cnt
      FROM favorites f
      JOIN poems p ON f.poem_id = p.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      GROUP BY dynasty ORDER BY cnt DESC
    ''');
    final map = <String, int>{};
    for (final row in results) {
      map[row['dynasty'] as String] = row['cnt'] as int;
    }
    return map;
  }

  /// 收藏总数
  static Future<int> getFavoriteCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM favorites');
    return r.first['c'] as int;
  }

  /// 诗词总数
  static Future<int> getTotalPoemsCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM poems');
    return r.first['c'] as int;
  }

  /// 作者总数
  static Future<int> getTotalAuthorsCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM authors');
    return r.first['c'] as int;
  }

  /// 阅读历史条数
  static Future<int> getReadingHistoryCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM reading_history');
    try {
      return r.first['c'] as int;
    } catch (_) {
      return 0;
    }
  }

  // ============ DAO: 学习笔记 ============

  /// 某首诗的笔记列表
  static Future<List<StudyNote>> getNotesByPoem(int poemId) async {
    final db = await database();
    final results = await db.rawQuery('''
      SELECT n.*, p.title, a.name AS author_name, d.name AS dynasty_name
      FROM study_notes n
      JOIN poems p ON n.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      WHERE n.poem_id = ?
      ORDER BY n.created_at DESC, n.id DESC
    ''', [poemId]);
    return results.map(StudyNote.fromMap).toList();
  }

  /// 所有笔记（按诗词聚合信息）
  static Future<List<StudyNote>> getAllNotes({String keyword = ''}) async {
    final db = await database();
    final kw = '%$keyword%';
    final where = keyword.trim().isEmpty
        ? ''
        : 'WHERE n.content LIKE ? OR p.title LIKE ? OR a.name LIKE ?';
    final args = keyword.trim().isEmpty ? <dynamic>[] : <dynamic>[kw, kw, kw];
    final results = await db.rawQuery('''
      SELECT n.*, p.title, a.name AS author_name, d.name AS dynasty_name
      FROM study_notes n
      JOIN poems p ON n.poem_id = p.id
      LEFT JOIN authors a ON p.author_id = a.id
      LEFT JOIN dynasties d ON p.dynasty_id = d.id
      $where
      ORDER BY n.created_at DESC, n.id DESC
      LIMIT 500
    ''', args);
    return results.map(StudyNote.fromMap).toList();
  }

  /// 添加笔记
  static Future<int> addNote(int poemId, String content) async {
    if (content.trim().isEmpty) return 0;
    final db = await database();
    return await db
        .insert('study_notes', {'poem_id': poemId, 'content': content.trim()});
  }

  /// 更新笔记
  static Future<void> updateNote(int noteId, String content) async {
    final db = await database();
    await db.update(
      'study_notes',
      {
        'content': content.trim(),
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  /// 删除笔记
  static Future<void> deleteNote(int noteId) async {
    final db = await database();
    await db.delete('study_notes', where: 'id = ?', whereArgs: [noteId]);
  }

  /// 笔记总数
  static Future<int> getNotesCount() async {
    final db = await database();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM study_notes');
    return r.first['c'] as int;
  }

  /// 有笔记的诗词数
  static Future<int> getNotedPoemsCount() async {
    final db = await database();
    final r = await db
        .rawQuery('SELECT COUNT(DISTINCT poem_id) AS c FROM study_notes');
    return r.first['c'] as int;
  }

  // ============ DAO: 离线包 ============

  /// 获取所有已安装的离线包
  static Future<List<Map<String, dynamic>>> getInstalledPacks() async {
    final db = await database();
    return await db.query('installed_packs', orderBy: 'installed_at DESC');
  }

  /// 是否已安装某离线包
  static Future<bool> isPackInstalled(String packName) async {
    final db = await database();
    final r = await db.query('installed_packs',
        where: 'pack_name = ?', whereArgs: [packName]);
    return r.isNotEmpty;
  }

  /// 卸载离线包（仅删除该包导入的诗词，保留 poems.json 预置的 1-70）
  static Future<int> uninstallPack(String packName) async {
    final db = await database();
    int deletedPoems = 0;
    await db.transaction((txn) async {
      // 根据 id 范围判定哪些诗属于此包（每包预留 2000 个 id）
      int? idStart, idEnd;
      switch (packName) {
        case 'tangshi':
          idStart = 20000;
          idEnd = 22000;
          break;
        case 'songci':
          idStart = 30000;
          idEnd = 32000;
          break;
        case 'xiaoxue':
          idStart = 10000;
          idEnd = 12000;
          break;
      }
      if (idStart == null) return;
      // 删除 poem_categories 中与这些诗关联
      await txn.delete('poem_categories',
          where: 'poem_id >= ? AND poem_id < ?', whereArgs: [idStart, idEnd]);
      // 删除收藏/学习记录/笔记/阅读历史/学习中记录（防止外键悬挂）
      await txn.delete('favorites',
          where: 'poem_id >= ? AND poem_id < ?', whereArgs: [idStart, idEnd]);
      await txn.delete('study_records',
          where: 'poem_id >= ? AND poem_id < ?', whereArgs: [idStart, idEnd]);
      await txn.delete('study_notes',
          where: 'poem_id >= ? AND poem_id < ?', whereArgs: [idStart, idEnd]);
      await txn.delete('reading_history',
          where: 'poem_id >= ? AND poem_id < ?', whereArgs: [idStart, idEnd]);
      // 删除诗词本身
      deletedPoems = await txn.delete('poems',
          where: 'id >= ? AND id < ?', whereArgs: [idStart, idEnd]);
      // 删除安装记录
      await txn.delete('installed_packs',
          where: 'pack_name = ?', whereArgs: [packName]);
    });
    // 诗词已删除，拼音索引失效
    invalidatePinyinIndex();
    debugPrint('🗑️ 卸载离线包 $packName，删除 $deletedPoems 首');
    return deletedPoems;
  }

  /// 导入离线包 JSON 数据到数据库
  /// [jsonString] 离线包 JSON 字符串（根含 pack_name/count/poems）
  /// 返回实际新插入的诗词数

  static Future<int> importPack(String jsonString) async {
    final db = await database();
    return _importPackWithDb(db, jsonString);
  }

  /// 以指定连接执行离线包导入（事务体）。
  /// 供 v7 内容刷新迁移在 onUpgrade 回调内复用——那里 _db 尚未赋值，
  /// 不可再调 database()（否则会递归打开第二个连接导致死锁）。
  static Future<int> _importPackWithDb(
      Database db, String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final packName = data['pack_name'] as String;
    final description = data['description'] as String? ?? '';
    final source = data['source'] as String? ?? '';
    final poems = (data['poems'] as List).cast<Map<String, dynamic>>();
    // 包内可选作者元数据（真实简介/生卒），导入时优先于占位模板
    final packAuthors = <String, Map<String, dynamic>>{};
    final packAuthorList = data['authors'];
    if (packAuthorList is List) {
      for (final raw in packAuthorList) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final name = (m['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          packAuthors[name] = m;
        }
      }
    }

    // 作者缓存：本包内遇到的新作者分配 id
    final authorCache = <String, int>{}; // name -> author_id
    // 预加载已有作者（按名字去重）
    final existing = await db.query('authors', columns: ['id', 'name']);
    for (final row in existing) {
      authorCache[row['name'] as String] = row['id'] as int;
    }
    // 朝代 id → 名称（离线包作者简介用，避免写死错位的 id 映射）
    final dynRows = await db.query('dynasties', columns: ['id', 'name']);
    final dynastyName = <int, String>{
      for (final r in dynRows) r['id'] as int: r['name'] as String,
    };
    int nextAuthorId = 1000;
    final maxAuthorRow = await db.rawQuery('SELECT MAX(id) AS m FROM authors');
    final maxId = maxAuthorRow.first['m'] as int?;
    if (maxId != null && maxId >= nextAuthorId) {
      nextAuthorId = maxId + 1;
    }

    // 推断该包对应的 id 区间（用于统计新插入行数；每包预留 2000 个 id）
    int idStart, idEnd;
    switch (packName) {
      case 'tangshi':
        idStart = 20000;
        idEnd = 22000;
        break;
      case 'songci':
        idStart = 30000;
        idEnd = 32000;
        break;
      case 'xiaoxue':
        idStart = 10000;
        idEnd = 12000;
        break;
      default:
        idStart = 0;
        idEnd = 0;
    }

    // 记录导入前的数量，用于计算 diff
    final before = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM poems WHERE id >= ? AND id < ?',
        [idStart, idEnd]);
    final beforeCount = before.first['c'] as int? ?? 0;

    await db.transaction((txn) async {
      try {
        // 先插入所有作者（优先使用包内真实简介）
        for (final p in poems) {
          final authorName = (p['author'] as String?)?.trim() ?? '佚名';
          if (!authorCache.containsKey(authorName)) {
            final authorId = nextAuthorId++;
            authorCache[authorName] = authorId;
            final meta = packAuthors[authorName];
            final bioRaw = (meta?['bio'] as String?)?.trim() ?? '';
            final birth = meta?['birth_year'];
            final death = meta?['death_year'];
            final dynId =
                (meta?['dynasty_id'] as int?) ?? (p['dynasty_id'] as int?);
            final bio = bioRaw.isNotEmpty
                ? bioRaw
                : '$authorName，${dynastyName[dynId] ?? '古代'}代'
                    '${(p['type'] as String?)?.contains('词') == true ? '词人' : '诗人'}。'
                    '其作品题材广泛、艺术精湛，在中国古代文学史上具有重要地位。';
            await txn.insert(
              'authors',
              {
                'id': authorId,
                'name': authorName,
                'dynasty_id': dynId,
                'bio': bio,
                if (birth != null) 'birth_year': birth,
                if (death != null) 'death_year': death,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        // 再插入诗
        for (final p in poems) {
        // 离线包原始数据含繁体字，入库前统一转简体（显示时再按繁简偏好转换）。
        // 必须用 S2TConverter（完整 3751 对映射），ChineseConverter 仅 232 对会漏字。
        if (p['content'] is String) {
          p['content'] = S2TConverter.toSimplified(p['content'] as String);
        }
        if (p['title'] is String) {
          p['title'] = S2TConverter.toSimplified(p['title'] as String);
        }
        if (p['rhythmic'] is String) {
          p['rhythmic'] = S2TConverter.toSimplified(p['rhythmic'] as String);
        }
        if (p['translation'] is String) {
          p['translation'] =
              S2TConverter.toSimplified(p['translation'] as String);
        }
          final authorName = (p['author'] as String?)?.trim() ?? '佚名';
          final authorId = authorCache[authorName]!;
          // 兼容宋词等缺 title 字段的离线包：title → rhythmic → 内容首行前 20 字 → "无题"
          String titleValue = (p['title'] as String?)?.trim() ?? '';
          if (titleValue.isEmpty) {
            final rhythmic = (p['rhythmic'] as String?)?.trim() ?? '';
            if (rhythmic.isNotEmpty) {
              titleValue = rhythmic;
            } else {
              final content = (p['content'] as String?) ?? '';
              final firstLine = content.split('\n').first.trim();
              titleValue = firstLine.length > 20
                  ? firstLine.substring(0, 20)
                  : (firstLine.isEmpty ? '无题' : firstLine);
            }
          }
          // 自动生成占位赏析/背景/译文：让 UI 卡片能显示完整版式
          final translation = (p['translation'] as String?)?.trim();
          final appreciation = (p['appreciation'] as String?)?.trim();
          final background = (p['background'] as String?)?.trim();
          final notesText = (p['notes'] as String?)?.trim();
          // 无真实内容时不生成模板占位，UI 会自动隐藏对应段落
          final fallbackTranslation =
              translation?.isNotEmpty == true ? translation : '';
          final fallbackBackground =
              background?.isNotEmpty == true ? background : '';
          final fallbackAppreciation =
              appreciation?.isNotEmpty == true ? appreciation : '';
          final fallbackNotes = notesText ?? '（暂无注释）';
          final pm = <String, dynamic>{
            'id': p['id'],
            'title': titleValue,
            'content': p['content'],
            'author_id': authorId,
            'dynasty_id': p['dynasty_id'],
            'type': p['type'],
            'source': p['source'],
            'sort_order': p['sort_order'],
            'translation': fallbackTranslation,
            'appreciation': fallbackAppreciation,
            'background': fallbackBackground,
            'notes': fallbackNotes,
          };
          await txn.insert('poems', pm,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          // 关联分类
          final cats = (p['category_ids'] as List?)?.cast<int>() ?? const [];
          for (final cid in cats) {
            await txn.insert(
              'poem_categories',
              {'poem_id': p['id'], 'category_id': cid},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        // 写入 installed_packs
        await txn.insert(
          'installed_packs',
          {
            'pack_name': packName,
            'description': description,
            'source': source,
            'count': poems.length,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint('✅ importPack transaction 完成');
      } catch (e, st) {
        debugPrint('❌ importPack 错误: $e\n$st');
        rethrow;
      }
    });

    final after = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM poems WHERE id >= ? AND id < ?',
        [idStart, idEnd]);
    final afterCount = after.first['c'] as int? ?? 0;
    final inserted = afterCount - beforeCount;

    debugPrint('📥 导入离线包 $packName: 共 ${poems.length} 首，新插入 $inserted 首');
    // 诗词集合已变化，拼音索引需重建
    invalidatePinyinIndex();
    return inserted;
  }

  // ============ 用户数据备份 / 恢复 ============
  // 只备份「用户生成数据」，预置诗词/作者/朝代/分类来自 assets，重装后可经离线包恢复，
  // 不纳入备份以免体积膨胀与 id 冲突。导入采用「合并 + 自然唯一键去重」，不会删除备份中不存在的现有数据。

  static const int _backupFormatVersion = 1;

  /// 导出全部用户数据为可序列化 Map（不含自增 id，避免恢复时 id 冲突）
  static Future<Map<String, dynamic>> exportAllData() async {
    final db = await database();
    Future<List<Map<String, dynamic>>> cols(
        String table, List<String> columns) async {
      final rows = await db.query(table, columns: columns);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    return {
      'backupFormat': _backupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'studyPlans': await cols(
          'study_plans', ['name', 'description', 'poem_ids', 'created_at']),
      'collections': await cols('collections', ['name', 'created_at']),
      'favorites':
          await cols('favorites', ['poem_id', 'collection_name', 'created_at']),
      'studyRecords':
          await cols('study_records', ['poem_id', 'study_date', 'status']),
      'notes': await cols(
          'study_notes', ['poem_id', 'content', 'created_at', 'updated_at']),
      'readingHistory': await cols('reading_history', ['poem_id', 'read_at']),
      'installedPacks': await cols('installed_packs',
          ['pack_name', 'description', 'source', 'count', 'installed_at']),
    };
  }

  /// 合并恢复用户数据，返回各表恢复行数摘要
  static Future<Map<String, int>> importAllData(
      Map<String, dynamic> data) async {
    final db = await database();
    final summary = <String, int>{};

    await db.transaction((txn) async {
      // 收藏夹（name 唯一，先查后插去重；统计实际新增行数）
      final collections =
          (data['collections'] as List? ?? []).cast<Map<String, dynamic>>();
      int collAdded = 0;
      for (final c in collections) {
        final name = c['name'] as String;
        final exists = await txn
            .query('collections', where: 'name = ?', whereArgs: [name]);
        if (exists.isEmpty) {
          await txn.insert('collections',
              {'name': name, 'created_at': c['created_at']});
          collAdded++;
        }
      }
      summary['collections'] = collAdded;

      // 学习计划（name 唯一，先查后插去重）
      final plans =
          (data['studyPlans'] as List? ?? []).cast<Map<String, dynamic>>();
      int planAdded = 0;
      for (final p in plans) {
        final name = p['name'] as String;
        final exists = await txn
            .query('study_plans', where: 'name = ?', whereArgs: [name]);
        if (exists.isEmpty) {
          await txn.insert('study_plans', {
            'name': name,
            'description': p['description'],
            'poem_ids': p['poem_ids'],
            'created_at': p['created_at'],
          });
          planAdded++;
        }
      }
      summary['studyPlans'] = planAdded;

      // 收藏（poem_id + collection_name 去重）
      final favorites =
          (data['favorites'] as List? ?? []).cast<Map<String, dynamic>>();
      int favAdded = 0;
      for (final f in favorites) {
        final pid = f['poem_id'];
        final cn = f['collection_name'] ?? '默认收藏';
        final exists = await txn.query('favorites',
            where: 'poem_id = ? AND collection_name = ?',
            whereArgs: [pid, cn]);
        if (exists.isEmpty) {
          await txn.insert('favorites', {
            'poem_id': pid,
            'collection_name': cn,
            'created_at': f['created_at']
          });
          favAdded++;
        }
      }
      summary['favorites'] = favAdded;

      // 学习打卡（poem_id + study_date + status 唯一索引，先查后插去重）
      final records =
          (data['studyRecords'] as List? ?? []).cast<Map<String, dynamic>>();
      int recAdded = 0;
      for (final r in records) {
        final exists = await txn.query('study_records',
            where: 'poem_id = ? AND study_date = ? AND status = ?',
            whereArgs: [r['poem_id'], r['study_date'], r['status']]);
        if (exists.isEmpty) {
          await txn.insert('study_records', {
            'poem_id': r['poem_id'],
            'study_date': r['study_date'],
            'status': r['status'],
          });
          recAdded++;
        }
      }
      summary['studyRecords'] = recAdded;

      // 笔记（poem_id + content 去重）
      final notes =
          (data['notes'] as List? ?? []).cast<Map<String, dynamic>>();
      int noteAdded = 0;
      for (final n in notes) {
        final pid = n['poem_id'];
        final content = n['content'];
        final exists = await txn.query('study_notes',
            where: 'poem_id = ? AND content = ?', whereArgs: [pid, content]);
        if (exists.isEmpty) {
          await txn.insert('study_notes', {
            'poem_id': pid,
            'content': content,
            'created_at': n['created_at'],
            'updated_at': n['updated_at'],
          });
          noteAdded++;
        }
      }
      summary['notes'] = noteAdded;

      // 阅读历史（poem_id 去重）
      final history = (data['readingHistory'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      int histAdded = 0;
      for (final h in history) {
        final pid = h['poem_id'];
        final exists = await txn
            .query('reading_history', where: 'poem_id = ?', whereArgs: [pid]);
        if (exists.isEmpty) {
          await txn.insert(
              'reading_history', {'poem_id': pid, 'read_at': h['read_at']});
          histAdded++;
        }
      }
      summary['readingHistory'] = histAdded;

      // 已装离线包（pack_name 主键，存在则跳过；统计实际新增）
      final packs = (data['installedPacks'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      int packAdded = 0;
      for (final pk in packs) {
        final exists = await txn.query('installed_packs',
            where: 'pack_name = ?', whereArgs: [pk['pack_name']]);
        if (exists.isEmpty) {
          await txn.insert('installed_packs', {
            'pack_name': pk['pack_name'],
            'description': pk['description'],
            'source': pk['source'],
            'count': pk['count'],
            'installed_at': pk['installed_at'],
          });
          packAdded++;
        }
      }
      summary['installedPacks'] = packAdded;
    });

    return summary;
  }

  /// 备份文件目录（应用支持目录下的 backups/，写入无需额外存储权限）
  static Future<Directory> getBackupDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 自动备份：导出全部用户数据并写入 backups/auto_backup_<时间戳>.json，
  /// 仅保留最近 [keep] 份，避免无限增长。返回写入的文件。
  static Future<File> createAutoBackup({int keep = 5}) async {
    final data = await exportAllData();
    final json = jsonEncode(data);
    final dir = await getBackupDirectory();
    final file = File(p.join(dir.path, 'auto_backup_${_autoBackupTs()}.json'));
    await file.writeAsString(json);
    // 修剪：文件名含时间，字典序即时间序，删除最旧的超量文件
    final existing = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('auto_backup_') &&
            p.basename(f.path).endsWith('.json'))
        .map((f) => f.path)
        .toList()
      ..sort();
    while (existing.length > keep) {
      final oldest = existing.removeAt(0);
      try {
        await File(oldest).delete();
      } catch (_) {
        // 删除失败不影响主流程
      }
    }
    return file;
  }

  /// 当前已存的自动备份数量
  static Future<int> getAutoBackupCount() async {
    try {
      final dir = await getBackupDirectory();
      return dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              p.basename(f.path).startsWith('auto_backup_') &&
              p.basename(f.path).endsWith('.json'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  static String _autoBackupTs() {
    final d = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p2(d.month)}${p2(d.day)}_'
        '${p2(d.hour)}${p2(d.minute)}${p2(d.second)}';
  }
}
