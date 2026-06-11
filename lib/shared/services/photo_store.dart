// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-device store for pin photos. Photos are PRIVATE to this device — they
/// don't sync to crew, since we'd need Supabase Storage + per-party encrypted
/// upload for that. The pin's encrypted payload carries the photo's local id
/// (`photoId`); if a different device opens the same pin, the lookup just
/// returns null and the UI hides the thumbnail.
///
/// Photos live at `<appSupport>/pin_photos/<id>.jpg`.
class PhotoStore {
  Directory? _dir;

  Future<Directory> _ensure() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'pin_photos'));
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
    return d;
  }

  /// Returns the on-disk path for the photo with this id (file may not exist).
  Future<String> pathFor(String id) async =>
      p.join((await _ensure()).path, '$id.jpg');

  Future<bool> exists(String id) async =>
      File(await pathFor(id)).existsSync();

  /// Save raw JPEG bytes under [id]. Overwrites if already present.
  Future<void> save(String id, Uint8List bytes) async {
    final path = await pathFor(id);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  /// Copies an existing file (e.g. the path returned by image_picker) into the
  /// store under [id]. Cheaper than re-encoding through bytes.
  Future<void> saveFromPath(String id, String srcPath) async {
    final dst = await pathFor(id);
    await File(srcPath).copy(dst);
  }

  Future<void> delete(String id) async {
    final f = File(await pathFor(id));
    if (f.existsSync()) await f.delete();
  }
}
