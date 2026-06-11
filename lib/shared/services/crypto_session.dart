// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:cryptography/cryptography.dart';

import '../../core/crypto/crypto_service.dart';
import 'party_secret_store.dart';

/// Resolves and caches the derived group key for each party the user belongs to.
///
/// Phase 3+ encrypt/decrypt paths (locations, pins, routes, messages) all go
/// through here so the HKDF derivation happens once per party per session.
class CryptoSession {
  CryptoSession(this._crypto, this._secrets);

  final CryptoService _crypto;
  final PartySecretStore _secrets;
  final Map<String, SecretKey> _cache = {};

  /// The group key for [partyId], or null if this device holds no secret for it
  /// (e.g. the user never joined, or the secret was wiped).
  Future<SecretKey?> groupKey(String partyId) async {
    final cached = _cache[partyId];
    if (cached != null) return cached;
    final secret = await _secrets.load(partyId);
    if (secret == null) return null;
    final key = await _crypto.deriveGroupKey(groupSecret: secret, partyId: partyId);
    _cache[partyId] = key;
    return key;
  }

  void forget(String partyId) => _cache.remove(partyId);
}
