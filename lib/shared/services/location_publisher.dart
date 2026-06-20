// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:cryptography/cryptography.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import 'mesh/mesh_bridge.dart';
import 'mesh/mesh_envelope.dart';

/// Reads the device GPS and publishes the user's own position to the party as
/// an encrypted blob. The plaintext lat/lng never leave the device unencrypted.
///
/// Phase 8c: every publish also broadcasts via the mesh bridge when a LoRa
/// radio is paired. The encrypted payload now embeds `user_id` so the mesh
/// receiver — which doesn't have a Supabase-issued sender_id on hand — can
/// map the position back to the correct party member.
class LocationPublisher {
  LocationPublisher(this._client, this._crypto, this._bridge);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final MeshBridge _bridge;

  /// Request location permission + ensure services are on. Returns whether we
  /// may read location at all (whileInUse or always).
  ///
  /// This is the foreground-only ask — sufficient for the screen-on map and
  /// fixes the publish loop reads. For background updates to keep flowing
  /// while the user has their phone in a pocket, see [ensureBackground]
  /// which adds the second-stage Always prompt + the in-app disclosure
  /// Google requires before that prompt fires.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Whether background location is already granted (Always on iOS / "Allow
  /// all the time" on Android). Reads-only; never prompts.
  Future<bool> hasBackgroundPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always;
  }

  /// Try to upgrade from whileInUse to always. The OS prompt only succeeds
  /// after a foreground (whileInUse) grant — so this method ensures that
  /// first, then asks for the upgrade.
  ///
  /// Returns:
  ///   - [BackgroundUpgradeResult.granted]   — perm is now Always; done
  ///   - [BackgroundUpgradeResult.needsSettings] — Android 11+ no longer
  ///     shows a runtime dialog for ACCESS_BACKGROUND_LOCATION; the user
  ///     has to grant it manually in app settings. Caller should call
  ///     [openAppSettings] next and listen for app resume to re-check.
  ///   - [BackgroundUpgradeResult.foregroundDenied] — even whileInUse
  ///     was refused. There's nothing more this code can do.
  ///
  /// IMPORTANT: callers must show the prominent disclosure screen
  /// (BackgroundDisclosureScreen) before invoking this. Google rejects
  /// Play Console submissions that ask for background location without
  /// an in-app disclosure preceding the OS prompt.
  Future<BackgroundUpgradeResult> requestBackgroundUpgrade() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return BackgroundUpgradeResult.foregroundDenied;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      return BackgroundUpgradeResult.foregroundDenied;
    }
    if (perm == LocationPermission.always) {
      return BackgroundUpgradeResult.granted;
    }
    // Try the runtime prompt. On Android 10 and earlier this can show a
    // 3-option dialog that includes "Allow all the time." On Android 11+
    // it's been deliberately neutered by Google: no in-app way to grant
    // background location — only system settings.
    perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.always) {
      return BackgroundUpgradeResult.granted;
    }
    return BackgroundUpgradeResult.needsSettings;
  }

  /// Open the app's system settings page so the user can manually grant
  /// "Allow all the time" for location. Required on Android 11+ where
  /// the runtime dialog for background location was removed.
  ///
  /// Returns true if settings opened. The caller can't await the user's
  /// action there — listen for app resume and re-check permission state.
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// A single current fix. The publish loop calls this on its configurable
  /// interval (battery-friendlier than a continuous stream).
  Future<Position?> current() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// Encrypt a position + fan it out to both Supabase (primary) and the mesh
  /// (redundant transport when paired). Failures on the mesh side never sink
  /// a Supabase publish — the on-internet path is the source of truth when
  /// available.
  Future<void> publish({
    required String partyId,
    required String userId,
    required SecretKey groupKey,
    required Position position,
  }) async {
    final now = DateTime.now().toUtc();
    // Compact JSON keys to keep position ciphertext inside Meshtastic's
    // ~237-byte payload limit. Without this, full ISO timestamps + UUIDs
    // + named keys push us past 250 bytes and mesh broadcasts drop on the
    // floor. Receivers tolerate both legacy long-form and compact keys.
    final payload = await _crypto.encryptJson(
      groupKey: groupKey,
      data: {
        'a': position.latitude,           // lat
        'o': position.longitude,          // lng (o for "lOngitude")
        's': position.speed,              // speed m/s
        'h': position.heading,            // heading deg
        'c': position.accuracy,           // aCcuracy m
        'e': position.altitude,           // elevation m
        't': now.millisecondsSinceEpoch,  // unix ms
        'u': userId,                       // user id
      },
    );
    // Both transports run in parallel, each in its own try-catch so a
    // Supabase failure (airplane mode) can't block the mesh broadcast and
    // vice versa. This is the bug we hit during the offline loop test:
    // sequential await meant Supabase threw first and the mesh broadcast
    // never fired, so positions stopped flowing the moment cell dropped.
    final supabaseFuture = () async {
      try {
        await _client.from('location_updates').upsert({
          'party_id': partyId,
          'user_id': userId,
          'encrypted_payload': payload.toWire(),
          'updated_at': now.toIso8601String(),
        }, onConflict: 'party_id,user_id');
      } catch (_) {/* offline — mesh is the fallback */}
    }();
    final meshFuture = () async {
      try {
        await _bridge.broadcast(
          partyId: partyId,
          type: MeshMsgType.position,
          ciphertext: payload.toBytes(),
        );
      } catch (_) {/* radio busy / not paired — silent */}
    }();
    await Future.wait([supabaseFuture, meshFuture]);
  }
}

/// Outcome of [LocationPublisher.requestBackgroundUpgrade]. Drives the UI's
/// decision on whether to open settings, show a snackbar, or do nothing.
enum BackgroundUpgradeResult {
  /// Background permission is now granted. UI flips to "ON".
  granted,

  /// Foreground (whileInUse) is granted, but the OS won't let us prompt
  /// for Always inline. Caller should open app settings.
  needsSettings,

  /// Even the foreground grant was refused. Nothing more to try.
  foregroundDenied,
}
