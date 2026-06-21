// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists which mayday messages this device has already shown the
/// receiver-side alert dialog for, so we don't re-pop the same mayday on
/// every map-screen rebuild.
///
/// Backed by SharedPreferences as a JSON map of `<maydayId>: <dismissedAtMs>`.
/// Entries older than [_keepDuration] are pruned on load so the prefs don't
/// grow forever — practical horizon is "if a mayday was dismissed a week
/// ago, don't bother remembering it." Beyond that, the [autoExpire] check
/// in [shouldShow] catches the stale-mayday case independently.
class MaydayDismissalStore {
  MaydayDismissalStore();

  static const _kPrefsKey = 'innawoods.mayday.dismissed.v1';
  static const _keepDuration = Duration(days: 7);

  /// A mayday is considered too old to alert on if its `sentAt` is older
  /// than this. Two hours is a reasonable upper bound on "the situation
  /// might still be active"; anything older the user has either already
  /// handled in-person or the sender resolved off-app.
  static const autoExpire = Duration(hours: 2);

  Map<String, int>? _cache;

  Future<Map<String, int>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) {
      _cache = {};
      return _cache!;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cutoff = DateTime.now()
          .subtract(_keepDuration)
          .millisecondsSinceEpoch;
      _cache = {
        for (final entry in decoded.entries)
          if (entry.value is int && (entry.value as int) >= cutoff)
            entry.key: entry.value as int,
      };
      // If we pruned anything, write the cleaned map back so the next load
      // is faster and the prefs don't keep growing.
      if (_cache!.length != decoded.length) {
        unawaited(_save());
      }
      return _cache!;
    } catch (_) {
      _cache = {};
      return _cache!;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(_cache ?? const {}));
  }

  /// True iff the receiver has already dismissed the alert for [maydayId].
  Future<bool> isDismissed(String maydayId) async {
    final map = await _load();
    return map.containsKey(maydayId);
  }

  /// Record that the receiver has dismissed (or otherwise handled) the
  /// alert for [maydayId]. Calling twice for the same id is a no-op.
  Future<void> dismiss(String maydayId) async {
    final map = await _load();
    if (map.containsKey(maydayId)) return;
    map[maydayId] = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  /// Decision-shaped helper used by the map screen — combines the
  /// already-dismissed gate AND the auto-expire age gate. Returns true
  /// when the alert dialog should still be shown.
  Future<bool> shouldShow({
    required String maydayId,
    required DateTime sentAt,
  }) async {
    if (DateTime.now().difference(sentAt) > autoExpire) return false;
    return !(await isDismissed(maydayId));
  }
}

