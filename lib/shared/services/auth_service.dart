import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/identity_key_store.dart';
import '../../core/theme/app_theme.dart';
import '../models/app_user.dart';

/// Bootstraps a user with zero friction: anonymous Supabase session + an
/// on-device X25519 identity + a profile row. No email, no password.
///
/// Resilient offline once the first online launch has cached the AppUser:
/// subsequent launches without internet (e.g. mid-hike) read from the
/// local cache instead of failing with "Could not start a secure session".
class AuthService {
  AuthService(this._client, this._keys, this._crypto);

  final SupabaseClient _client;
  final IdentityKeyStore _keys;
  final CryptoService _crypto;

  static const _kCachedUser = 'innawoods.auth.cached_user_json';

  /// Ensure a session, identity keypair, and profile row all exist. Idempotent.
  /// Falls back to the locally cached AppUser when network is unreachable so
  /// the user can launch the app and use mesh/offline features without cell.
  Future<AppUser> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    AppUser? cached = _loadCached(prefs);
    // We can't sign in anonymously without a network — but if a prior
    // session is still cached locally we have a uid + we have the cached
    // profile, so we can proceed entirely offline.
    if (_client.auth.currentSession == null) {
      try {
        await _client.auth.signInAnonymously();
      } catch (e) {
        if (cached != null) return cached;
        rethrow;
      }
    }
    final uid = _client.auth.currentUser!.id;

    final keyPair = await _keys.loadOrCreate();
    final publicKey = base64.encode(await _crypto.publicKeyBytes(keyPair));

    try {
      final existing =
          await _client.from('users').select().eq('id', uid).maybeSingle();
      if (existing != null) {
        final user = AppUser.fromJson(existing);
        await _saveCached(prefs, user);
        return user;
      }
      final inserted = await _client
          .from('users')
          .insert({
            'id': uid,
            'avatar_color': _randomEarthColor(),
            'public_key': publicKey,
          })
          .select()
          .single();
      final user = AppUser.fromJson(inserted);
      await _saveCached(prefs, user);
      return user;
    } catch (e) {
      // Network gone. Prefer the cache; otherwise synthesize a minimal
      // AppUser from what we know locally — the uid is in the cached
      // session, the public key was just loaded/created above. The user
      // can still browse already-downloaded regions, use the mesh, and
      // join parties via QR + paste once internet returns.
      if (cached != null && cached.id == uid) return cached;
      final synthetic = AppUser(
        id: uid,
        avatarColor: _randomEarthColor(),
        publicKey: publicKey,
      );
      // Don't persist the synthetic record — let the next online launch
      // fetch the canonical row from Supabase and overwrite this stub.
      return synthetic;
    }
  }

  AppUser? _loadCached(SharedPreferences prefs) {
    final raw = prefs.getString(_kCachedUser);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCached(SharedPreferences prefs, AppUser user) async {
    await prefs.setString(
      _kCachedUser,
      jsonEncode({
        'id': user.id,
        'display_name': user.displayName,
        'avatar_color': user.avatarColor,
        'public_key': user.publicKey,
      }),
    );
  }

  Future<AppUser> setDisplayName(String name) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('users')
        .update({'display_name': name.trim()})
        .eq('id', uid)
        .select()
        .single();
    return AppUser.fromJson(row);
  }

  String _randomEarthColor() =>
      AppTheme.memberPalette[Random().nextInt(AppTheme.memberPalette.length)];
}
