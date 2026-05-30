import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which regions are downloaded on this device and which one is active.
/// Files live at `${appSupport}/maps/<id>.pmtiles`.
class RegionStore {
  static const _kActive = 'innawoods.region.active';
  static const _kDownloaded = 'innawoods.region.downloaded'; // CSV of ids

  Directory? _mapsDir;

  Future<Directory> _dir() async {
    if (_mapsDir != null) return _mapsDir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'maps'));
    if (!d.existsSync()) d.createSync(recursive: true);
    // Migrate the legacy `wa.pmtiles` at the support root from before the
    // region-download manager existed. Also auto-activate it so the user
    // doesn't land on the "no map" screen after an update.
    final legacy = File(p.join(base.path, 'wa.pmtiles'));
    final migrated = File(p.join(d.path, 'us-wa.pmtiles'));
    if (legacy.existsSync() && !migrated.existsSync()) {
      legacy.renameSync(migrated.path);
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kActive) == null) {
        await prefs.setString(_kActive, 'us-wa');
      }
    }
    _mapsDir = d;
    return d;
  }

  /// Absolute on-disk path for the given region (file may not exist).
  Future<String> pathFor(String regionId) async =>
      p.join((await _dir()).path, '$regionId.pmtiles');

  /// True if the .pmtiles file for this region is present.
  Future<bool> isDownloaded(String regionId) async =>
      File(await pathFor(regionId)).existsSync();

  /// All region ids the user has downloaded (filesystem-truthful).
  Future<List<String>> downloaded() async {
    final dir = await _dir();
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pmtiles'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList()
      ..sort();
  }

  Future<String?> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kActive);
    if (stored != null && await isDownloaded(stored)) return stored;
    // Nothing stored (or the stored region is gone) — but the user may have
    // downloaded something. Fall back to any downloaded region so the map
    // "just works" instead of stranding them on the empty-state screen.
    final present = await downloaded();
    if (present.isEmpty) return null;
    final pick = present.first;
    await prefs.setString(_kActive, pick);
    return pick;
  }

  Future<void> setActive(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActive, regionId);
  }

  /// Remove a region from disk. If it was active, clears the active selection.
  Future<void> delete(String regionId) async {
    final f = File(await pathFor(regionId));
    if (f.existsSync()) f.deleteSync();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kActive) == regionId) {
      await prefs.remove(_kActive);
    }
    // The CSV cache is best-effort; ignored if the active key is the source of
    // truth and downloaded() reads from the filesystem.
    await prefs.remove(_kDownloaded);
  }
}
