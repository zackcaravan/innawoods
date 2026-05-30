import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/identity_key_store.dart';
import '../../core/theme/app_theme.dart';
import '../models/app_user.dart';

/// Bootstraps a user with zero friction: anonymous Supabase session + an
/// on-device X25519 identity + a profile row. No email, no password.
class AuthService {
  AuthService(this._client, this._keys, this._crypto);

  final SupabaseClient _client;
  final IdentityKeyStore _keys;
  final CryptoService _crypto;

  /// Ensure a session, identity keypair, and profile row all exist. Idempotent.
  Future<AppUser> bootstrap() async {
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }
    final uid = _client.auth.currentUser!.id;

    final keyPair = await _keys.loadOrCreate();
    final publicKey = base64.encode(await _crypto.publicKeyBytes(keyPair));

    final existing =
        await _client.from('users').select().eq('id', uid).maybeSingle();
    if (existing != null) return AppUser.fromJson(existing);

    final inserted = await _client
        .from('users')
        .insert({
          'id': uid,
          'avatar_color': _randomEarthColor(),
          'public_key': publicKey,
        })
        .select()
        .single();
    return AppUser.fromJson(inserted);
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
