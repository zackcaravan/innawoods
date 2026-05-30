import 'package:cryptography/cryptography.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';

/// Reads the device GPS and publishes the user's own position to the party as
/// an encrypted blob. The plaintext lat/lng never leave the device unencrypted.
class LocationPublisher {
  LocationPublisher(this._client, this._crypto);

  final SupabaseClient _client;
  final CryptoService _crypto;

  /// Request location permission + ensure services are on. Returns whether we
  /// may read location.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

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

  /// Encrypt a position and upsert it as this user's row for the party.
  Future<void> publish({
    required String partyId,
    required String userId,
    required SecretKey groupKey,
    required Position position,
  }) async {
    final now = DateTime.now().toUtc();
    final payload = await _crypto.encryptJson(
      groupKey: groupKey,
      data: {
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed,
        'heading': position.heading,
        'ts': now.toIso8601String(),
      },
    );
    await _client.from('location_updates').upsert({
      'party_id': partyId,
      'user_id': userId,
      'encrypted_payload': payload.toWire(),
      'updated_at': now.toIso8601String(),
    }, onConflict: 'party_id,user_id');
  }
}
