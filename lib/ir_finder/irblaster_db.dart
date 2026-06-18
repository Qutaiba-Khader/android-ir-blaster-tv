/* lib/ir_finder/irblaster_db.dart */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:irblaster_controller/ir_finder/ir_finder_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class IrBlasterDb {
  IrBlasterDb._();
  static final IrBlasterDb instance = IrBlasterDb._();

  /// The IR-code DB is NOT bundled in the APK (keeps it small + the build fast).
  /// It is downloaded on first use from this manifest's `url` and cached in the
  /// app's databases dir; queries then run locally.
  static const String dbManifestUrl =
      'https://rclone-public.websnake.org/storage/irdb/version.json';
  static const String _dbFileName = 'irblaster.sqlite';

  /// True while the DB is being fetched — UIs show a "downloading codes…" state.
  bool downloading = false;

  Database? _db;
  Future<void>? _initFuture;
  bool _perfTuned = false;

  // Protocol normalization cache: normalizedKey -> canonical DB value as stored in keys.protocol
  bool _protocolMapLoaded = false;
  final Map<String, String> _canonicalProtocolByKey = <String, String>{};

  Future<void> ensureInitialized() {
    _initFuture ??= _open();
    return _initFuture!.catchError((Object e) {
      // Let the next call retry (e.g. after the network comes back).
      _initFuture = null;
      throw e;
    });
  }

  /// The active DB's date stamp (db_meta.date), e.g. '2026-06-18'. Reflects the
  /// bundled DB or a background-applied update. Null if unavailable.
  Future<String?> dbDate() async {
    try {
      if (_db == null) {
        // Don't trigger a download just to read the date — only read if cached.
        final dir = await getDatabasesPath();
        final f = File(p.join(dir, _dbFileName));
        if (!(await f.exists() && await f.length() > 1000000)) return null;
      }
      await ensureInitialized();
      final rows = await _requireDb()
          .rawQuery("SELECT value FROM db_meta WHERE key='date' LIMIT 1;");
      if (rows.isNotEmpty) return rows.first['value'] as String?;
    } catch (_) {}
    return null;
  }

  Future<void> _open() async {
    if (_db != null) return;

    final String dbDir = await getDatabasesPath();
    final String dbPath = p.join(dbDir, _dbFileName);

    // Apply a background-downloaded update (staged by IrDbUpdater) before opening.
    final File pending = File(p.join(dbDir, 'irblaster.pending.sqlite'));
    if (await pending.exists() && await pending.length() > 1000000) {
      try {
        await pending.rename(dbPath);
      } catch (_) {
        try {
          await pending.copy(dbPath);
          await pending.delete();
        } catch (_) {}
      }
    }

    final File dbFile = File(dbPath);
    final bool ok = await dbFile.exists() && await dbFile.length() > 1000000;
    if (!ok) {
      // Not cached yet → download it (the hosted DB ships fully indexed).
      await _downloadDb(dbPath);
    }

    // Open writable so the perf-tuning PRAGMAs apply (indexes already exist).
    _db = await openDatabase(
      dbPath,
      readOnly: false,
      singleInstance: true,
    );

    await _ensurePerformanceTuning();
  }

  /// Download the cached-once DB from the hosted manifest. Throws on failure so
  /// callers (the finder / pickers) can show a retry state; never leaves a
  /// partial file in place.
  Future<void> _downloadDb(String targetPath) async {
    downloading = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final mReq = await client.getUrl(Uri.parse(dbManifestUrl));
      final mResp = await mReq.close().timeout(const Duration(seconds: 20));
      if (mResp.statusCode != 200) {
        throw StateError('manifest ${mResp.statusCode}');
      }
      final m = json.decode(await mResp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      final String url = (m['url'] ?? '').toString();
      final int? size =
          m['size'] is int ? m['size'] as int : int.tryParse('${m['size']}');
      if (url.isEmpty) throw StateError('no db url in manifest');

      final File tmp = File('$targetPath.part');
      await tmp.parent.create(recursive: true);
      if (await tmp.exists()) await tmp.delete();

      final dReq = await client.getUrl(Uri.parse(url));
      final dResp = await dReq.close().timeout(const Duration(minutes: 10));
      if (dResp.statusCode != 200) {
        throw StateError('download ${dResp.statusCode}');
      }
      final sink = tmp.openWrite();
      await dResp.pipe(sink); // closes the sink

      final int len = await tmp.length();
      if (len < 1000000 || (size != null && len != size)) {
        await tmp.delete();
        throw StateError('bad download ($len/${size ?? '?'})');
      }
      final File out = File(targetPath);
      if (await out.exists()) await out.delete();
      await tmp.rename(targetPath);
    } finally {
      client.close(force: true);
      downloading = false;
    }
  }

  Database _requireDb() {
    final Database? db = _db;
    if (db == null) {
      throw StateError('IrBlasterDb not initialized. Call ensureInitialized() first.');
    }
    return db;
  }

  Future<void> _ensurePerformanceTuning() async {
    if (_perfTuned) return;
    final db = _requireDb();

    Future<void> tryExec(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {
        // ignore
      }
    }

    await tryExec('PRAGMA temp_store=MEMORY;');
    await tryExec('PRAGMA cache_size=-20000;'); // ~20MB cache (negative => KB pages)
    await tryExec('PRAGMA mmap_size=268435456;'); // 256MB mmap (best-effort)
    await tryExec('PRAGMA synchronous=NORMAL;');
    await tryExec('PRAGMA foreign_keys=OFF;');

    // Core indexes
    await tryExec('CREATE INDEX IF NOT EXISTS idx_keys_protocol_id ON keys(protocol, id);');
    await tryExec('CREATE INDEX IF NOT EXISTS idx_keys_id ON keys(id);');
    await tryExec('CREATE INDEX IF NOT EXISTS idx_models_brand_id ON models(brand, id);');
    await tryExec('CREATE INDEX IF NOT EXISTS idx_models_brand_model ON models(brand, model);');
    await tryExec('CREATE INDEX IF NOT EXISTS idx_brands_name_nocase ON brands(name COLLATE NOCASE);');

    // Helpful optional indexes for case-insensitive / normalized protocol matching:
    await tryExec('CREATE INDEX IF NOT EXISTS idx_keys_protocol_nocase_id ON keys(protocol COLLATE NOCASE, id);');

    // Expression index (best-effort; supported on modern SQLite). If unsupported, it will be ignored.
    await tryExec(
      "CREATE INDEX IF NOT EXISTS idx_keys_protocol_norm_id ON keys("
      "lower(replace(replace(replace(protocol,'-',''),'_',''),' ','')), id"
      ");",
    );

    await tryExec('PRAGMA optimize;');

    _perfTuned = true;
  }

  // ---- Protocol normalization helpers ----

  static String _protocolKey(String s) {
    // Keep only [a-z0-9] after lowercasing; this makes:
    // "RCA-38" == "rca_38" == "RCA 38" -> "rca38"
    return s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String _sqlProtocolNormExpr(String column) {
    // Mirror a subset of _protocolKey() in SQL (fast enough + indexable via expression index).
    // We normalize by removing '-', '_' and spaces and lowercasing.
    return "lower(replace(replace(replace($column,'-',''),'_',''),' ',''))";
  }

  Future<void> _ensureProtocolMapLoaded() async {
    if (_protocolMapLoaded) return;
    final db = _requireDb();

    // Distinct over protocol is usually cheap with idx_keys_protocol_id.
    final rows = await db.rawQuery('SELECT DISTINCT protocol FROM keys WHERE protocol IS NOT NULL;');
    for (final r in rows) {
      final v = r['protocol'];
      if (v == null) continue;
      final String protoStr = v.toString();
      final String key = _protocolKey(protoStr);
      if (key.isEmpty) continue;
      _canonicalProtocolByKey.putIfAbsent(key, () => protoStr);
    }

    _protocolMapLoaded = true;
  }

  Future<_ProtocolFilter?> _resolveProtocolFilter(String? selectedProtocolId) async {
    final String? s = (selectedProtocolId == null || selectedProtocolId.trim().isEmpty)
        ? null
        : selectedProtocolId.trim();
    if (s == null) return null;

    final String key = _protocolKey(s);
    if (key.isEmpty) return null;

    await _ensureProtocolMapLoaded();

    // If DB has a canonical spelling for this normalized key, use it (fast path).
    final String? canonical = _canonicalProtocolByKey[key];

    return _ProtocolFilter(
      normalizedKey: key,
      canonicalDbValue: canonical,
    );
  }

  void _appendProtocolWhere({
    required List<String> where,
    required List<Object?> args,
    required String column,
    required _ProtocolFilter filter,
  }) {
    if (filter.canonicalDbValue != null) {
      // Exact DB value -> uses idx_keys_protocol_id
      where.add('$column = ?');
      args.add(filter.canonicalDbValue);
    } else {
      // Fallback normalized expression (works even if DB uses different separators/case)
      where.add('${_sqlProtocolNormExpr(column)} = ?');
      args.add(filter.normalizedKey);
    }
  }

  // ---- Public API ----

  Future<List<String>> listProtocolsFor({required String brand, required String model}) async {
    await ensureInitialized();
    final db = _requireDb();
    final String b = brand.trim();
    final String m = model.trim();
    if (b.isEmpty || m.isEmpty) return <String>[];

    final rows = await db.rawQuery('''
      SELECT DISTINCT k.protocol AS protocol
      FROM models m
      JOIN keys k ON k.id = m.id
      WHERE m.brand = ? AND m.model = ? AND k.protocol IS NOT NULL
      ORDER BY UPPER(k.protocol) ASC
    ''', [b, m]);
    return rows
        .map((r) => (r['protocol'] as String?)?.trim())
        .whereType<String>()
        .toList(growable: false);
  }

  /// Returns distinct protocols used by [brand] across all its models,
  /// ordered alphabetically. Used to auto-adjust the protocol when a
  /// brand is selected in the IR Finder without a protocol filter.
  Future<List<String>> listProtocolsForBrand(String brand) async {
    await ensureInitialized();
    final db = _requireDb();
    final String b = brand.trim();
    if (b.isEmpty) return <String>[];

    final rows = await db.rawQuery('''
      SELECT DISTINCT k.protocol AS protocol
      FROM models m
      JOIN keys k ON k.id = m.id
      WHERE m.brand = ? AND k.protocol IS NOT NULL
      ORDER BY UPPER(k.protocol) ASC
    ''', [b]);
    return rows
        .map((r) => (r['protocol'] as String?)?.trim())
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> listBrands({
    String? search,
    String? protocolId,
    int limit = 60,
    int offset = 0,
  }) async {
    await ensureInitialized();
    final db = _requireDb();

    final String? q = (search == null || search.trim().isEmpty) ? null : search.trim();
    final _ProtocolFilter? pf = await _resolveProtocolFilter(protocolId);

    // Always query through models+keys so the returned brand names are
    // exactly the same strings stored in models.brand. This is critical for
    // consistency: listProtocolsForBrand, listModelsDistinct, and the signal
    // test all query models.brand with an exact-match WHERE clause. If we
    // returned brand names from the separate `brands` display table they might
    // differ in capitalisation or spacing (e.g. "O General" vs "O-General"),
    // causing those follow-up queries to return zero results.
    final where = <String>[];
    final args = <Object?>[];

    if (pf != null) {
      _appendProtocolWhere(where: where, args: args, column: 'k.protocol', filter: pf);
    }

    if (q != null) {
      where.add('m.brand LIKE ? ESCAPE \'\\\'');
      args.add('%${_escapeLike(q)}%');
    }

    final String whereSql =
        where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    // Only join keys when a protocol filter needs k.protocol. Without it the
    // join over 413k keys makes the live brand search slow on TV (78ms→14ms).
    final String joinSql = pf != null ? 'JOIN keys k ON k.id = m.id' : '';

    final sql = '''
      SELECT DISTINCT m.brand AS name
      FROM models m
      $joinSql
      $whereSql
      ORDER BY name COLLATE NOCASE ASC
      LIMIT ? OFFSET ?
    ''';

    args.add(limit);
    args.add(offset);

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => (r['name'] as String)).toList(growable: false);
  }

  Future<List<String>> listModelsDistinct({
    required String brand,
    String? search,
    String? protocolId,
    int limit = 60,
    int offset = 0,
  }) async {
    await ensureInitialized();
    final db = _requireDb();

    final String b = brand.trim();
    if (b.isEmpty) return <String>[];

    final String? q = (search == null || search.trim().isEmpty) ? null : search.trim();
    final _ProtocolFilter? pf = await _resolveProtocolFilter(protocolId);

    // No protocol filter: keep it simple.
    if (pf == null) {
      final where = <String>['brand = ?'];
      final args = <Object?>[b];

      if (q != null) {
        where.add('model LIKE ? ESCAPE \'\\\'');
        args.add('%${_escapeLike(q)}%');
      }

      final rows = await db.query(
        'models',
        columns: const <String>['model'],
        distinct: true,
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'model COLLATE NOCASE ASC',
        limit: limit,
        offset: offset,
      );
      return rows.map((r) => (r['model'] as String)).toList(growable: false);
    }

    // Protocol-filtered models for a brand:
    final where = <String>['m.brand = ?'];
    final args = <Object?>[b];

    _appendProtocolWhere(where: where, args: args, column: 'k.protocol', filter: pf);

    if (q != null) {
      where.add('m.model LIKE ? ESCAPE \'\\\'');
      args.add('%${_escapeLike(q)}%');
    }

    final sql = '''
      SELECT DISTINCT m.model AS model
      FROM models m
      JOIN keys k ON k.id = m.id
      WHERE ${where.join(' AND ')}
      ORDER BY model COLLATE NOCASE ASC
      LIMIT ? OFFSET ?
    ''';

    args.add(limit);
    args.add(offset);

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => (r['model'] as String)).toList(growable: false);
  }

  Future<List<IrDbKeyCandidate>> fetchCandidateKeys({
    required String brand,
    String? model,
    String? selectedProtocolId,
    required bool quickWinsFirst,
    String? hexPrefixUpper,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    await ensureInitialized();
    final db = _requireDb();

    final String b = brand.trim();
    if (b.isEmpty) return <IrDbKeyCandidate>[];

    final String? m = (model == null || model.trim().isEmpty) ? null : model.trim();
    final String? prefix = (hexPrefixUpper == null || hexPrefixUpper.trim().isEmpty)
        ? null
        : hexPrefixUpper.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    final _ProtocolFilter? pf = await _resolveProtocolFilter(selectedProtocolId);

    final args = <Object?>[];
    final where = <String>[];

    where.add('m.brand = ?');
    args.add(b);

    if (m != null) {
      where.add('m.model = ?');
      args.add(m);
    }

    if (pf != null) {
      _appendProtocolWhere(where: where, args: args, column: 'k.protocol', filter: pf);
    }

    if (prefix != null) {
      where.add('UPPER(k.hexcode) LIKE ?');
      args.add('$prefix%');
    }

    final String? q = (search == null || search.trim().isEmpty) ? null : _escapeLike(search.trim());
    if (q != null) {
      where.add('(UPPER(k.label) LIKE UPPER(?) ESCAPE \'\\\' OR UPPER(k.hexcode) LIKE UPPER(?))');
      args.add('%$q%');
      args.add('%${q.toUpperCase()}%');
    }

    final String orderBy = quickWinsFirst
        ? '''
 CASE
 WHEN UPPER(k.label) LIKE '%POWER%' OR UPPER(k.label) IN ('PWR','POWER','ON','OFF') THEN 0
 WHEN UPPER(k.label) LIKE '%MUTE%' OR UPPER(k.label) = 'MUTE' THEN 1
 WHEN UPPER(k.label) LIKE 'VOL%' OR UPPER(k.label) LIKE '%VOLUME%' THEN 2
 WHEN UPPER(k.label) LIKE 'CH%' OR UPPER(k.label) LIKE '%CHANNEL%' THEN 3
 WHEN UPPER(k.label) IN ('OK','ENTER','MENU','HOME','BACK','UP','DOWN','LEFT','RIGHT') THEN 4
 ELSE 9
 END ASC,
 UPPER(k.label) ASC,
 UPPER(k.protocol) ASC,
 UPPER(k.hexcode) ASC,
 k.id ASC
 '''
        : '''
 UPPER(k.label) ASC,
 UPPER(k.protocol) ASC,
 UPPER(k.hexcode) ASC,
 k.id ASC
 ''';

    final sql = '''
 SELECT
   k.id AS remote_id,
   k.label AS label,
   k.hexcode AS hexcode,
   k.protocol AS protocol,
   m.brand AS brand,
   m.model AS model
 FROM models m
 JOIN keys k ON k.id = m.id
 WHERE ${where.join(' AND ')}
 ORDER BY $orderBy
 LIMIT ? OFFSET ?
''';

    args.add(limit);
    args.add(offset);

    final rows = await db.rawQuery(sql, args);

    return rows.map((r) {
      final int remoteId = (r['remote_id'] as int);
      final String label = (r['label'] as String);
      final String hex = (r['hexcode'] as String);
      final String protocol = (r['protocol'] as String);
      final String rb = (r['brand'] as String);
      final String rm = (r['model'] as String);

      return IrDbKeyCandidate(
        id: remoteId,
        protocol: protocol,
        hexcode: hex,
        remoteId: remoteId,
        label: label,
        brand: rb,
        model: rm,
      );
    }).toList(growable: false);
  }

  Future<int> countCandidateKeys({
    required String brand,
    String? model,
    String? selectedProtocolId,
    String? hexPrefixUpper,
    String? search,
  }) async {
    await ensureInitialized();
    final db = _requireDb();

    final String b = brand.trim();
    if (b.isEmpty) return 0;

    final String? m = (model == null || model.trim().isEmpty) ? null : model.trim();
    final String? prefix = (hexPrefixUpper == null || hexPrefixUpper.trim().isEmpty)
        ? null
        : hexPrefixUpper.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    final _ProtocolFilter? pf = await _resolveProtocolFilter(selectedProtocolId);

    final args = <Object?>[];
    final where = <String>[];

    where.add('m.brand = ?');
    args.add(b);

    if (m != null) {
      where.add('m.model = ?');
      args.add(m);
    }

    if (pf != null) {
      _appendProtocolWhere(where: where, args: args, column: 'k.protocol', filter: pf);
    }

    if (prefix != null) {
      where.add('UPPER(k.hexcode) LIKE ?');
      args.add('$prefix%');
    }

    final String? q = (search == null || search.trim().isEmpty) ? null : _escapeLike(search.trim());
    if (q != null) {
      where.add('(UPPER(k.label) LIKE UPPER(?) ESCAPE \'\\\' OR UPPER(k.hexcode) LIKE UPPER(?))');
      args.add('%$q%');
      args.add('%${q.toUpperCase()}%');
    }

    final sql = '''
 SELECT COUNT(1) AS cnt
 FROM models m
 JOIN keys k ON k.id = m.id
 WHERE ${where.join(' AND ')}
''';

    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) return 0;
    final dynamic v = rows.first['cnt'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  static String _escapeLike(String input) {
    return input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
  }
}

class _ProtocolFilter {
  final String normalizedKey;
  final String? canonicalDbValue;
  const _ProtocolFilter({
    required this.normalizedKey,
    required this.canonicalDbValue,
  });
}
