import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Filesystem store for finalized tracks. Each track lives as a JSON file
/// under `<appSupport>/tracks/<id>.json`. Tracks are private to the device.
class TrackStore {
  Directory? _dir;

  Future<Directory> _ensure() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'tracks'));
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
    return d;
  }

  Future<void> save(Track t) async {
    final dir = await _ensure();
    final f = File(p.join(dir.path, '${t.id}.json'));
    await f.writeAsString(jsonEncode(t.toJson()));
  }

  Future<List<Track>> list() async {
    final dir = await _ensure();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    final out = <Track>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(Track.fromJson(j));
      } catch (_) {/* corrupt file — skip */}
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = await _ensure();
    final f = File(p.join(dir.path, '$id.json'));
    if (f.existsSync()) f.deleteSync();
  }
}
