/* lib/ir_finder/ir_db_updater.dart */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import 'irblaster_db.dart';

/// Background updater for the bundled IR-code database.
///
/// On app start we fetch a tiny manifest (version.json). If its `date` is newer
/// than the active DB's `db_meta.date`, we download the new DB to a STAGING file
/// and validate its size. We never touch the live, open database — [IrBlasterDb]
/// swaps the staged file in on the NEXT open (next launch). Fully best-effort:
/// any network/IO error is swallowed and the app keeps using the bundled DB.
class IrDbUpdater {
  IrDbUpdater._();

  static const String manifestUrl =
      'https://rclone-public.websnake.org/storage/irdb/version.json';
  static const String _pendingName = 'irblaster.pending.sqlite';

  static bool _ran = false;
  static String? lastCheckResult; // for debugging / a Settings readout

  /// Check the manifest and stage a newer DB if available. Safe to call
  /// fire-and-forget at startup; never throws.
  static Future<void> checkAndStage() async {
    if (_ran) return;
    _ran = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      // Only check for UPDATES to an already-cached DB. The first download
      // happens on demand via IrBlasterDb when the finder/import is opened.
      final current = await IrBlasterDb.instance.dbDate();
      if (current == null) {
        lastCheckResult = 'no local db yet (downloads on demand)';
        return;
      }

      final mReq = await client.getUrl(Uri.parse(manifestUrl));
      final mResp = await mReq.close().timeout(const Duration(seconds: 15));
      if (mResp.statusCode != 200) {
        lastCheckResult = 'manifest ${mResp.statusCode}';
        return;
      }
      final body = await mResp.transform(utf8.decoder).join();
      final m = json.decode(body) as Map<String, dynamic>;
      final remoteDate = (m['date'] ?? '').toString();
      final url = (m['url'] ?? '').toString();
      final size = m['size'] is int
          ? m['size'] as int
          : int.tryParse('${m['size']}');

      // Date stamps are ISO yyyy-mm-dd → lexical compare == chronological.
      if (remoteDate.isEmpty || remoteDate.compareTo(current) <= 0 || url.isEmpty) {
        lastCheckResult = 'up to date ($current)';
        return;
      }

      final dir = await getDatabasesPath();
      final pending = File(p.join(dir, _pendingName));
      final tmp = File(p.join(dir, '$_pendingName.part'));
      if (await tmp.exists()) await tmp.delete();

      final dReq = await client.getUrl(Uri.parse(url));
      final dResp = await dReq.close().timeout(const Duration(minutes: 8));
      if (dResp.statusCode != 200) {
        lastCheckResult = 'download ${dResp.statusCode}';
        return;
      }
      final sink = tmp.openWrite();
      await dResp.pipe(sink); // pipe closes the sink

      final len = await tmp.length();
      if (size != null && len != size) {
        await tmp.delete();
        lastCheckResult = 'size mismatch ($len/$size)';
        return;
      }
      if (len < 1000000) {
        await tmp.delete();
        lastCheckResult = 'too small ($len)';
        return;
      }
      // Atomically promote the verified download to the staging slot.
      if (await pending.exists()) await pending.delete();
      await tmp.rename(pending.path);
      lastCheckResult = 'staged $remoteDate (applies next launch)';
    } catch (e) {
      lastCheckResult = 'error: $e';
    } finally {
      client.close(force: true);
    }
  }
}
