// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_service.dart';

/// Persists the user's X25519 identity keypair in the OS keystore/keychain.
///
/// The private key never leaves the device and is never written to Supabase,
/// shared preferences, or any log. Losing it (e.g. uninstalling the app) is
/// by design unrecoverable — true ownership of one's own keys.
class IdentityKeyStore {
  IdentityKeyStore({FlutterSecureStorage? storage, CryptoService? crypto})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _crypto = crypto ?? CryptoService();

  final FlutterSecureStorage _storage;
  final CryptoService _crypto;

  static const _privateKeyKey = 'innawoods.identity.private';
  static const _publicKeyKey = 'innawoods.identity.public';

  /// Load the existing identity, or generate, persist, and return a new one.
  Future<SimpleKeyPair> loadOrCreate() async {
    final priv = await _storage.read(key: _privateKeyKey);
    final pub = await _storage.read(key: _publicKeyKey);
    if (priv != null && pub != null) {
      return _crypto.restoreIdentityKeyPair(
        privateKey: Uint8List.fromList(base64.decode(priv)),
        publicKey: Uint8List.fromList(base64.decode(pub)),
      );
    }

    final keyPair = await _crypto.generateIdentityKeyPair();
    final privBytes = await _crypto.privateKeyBytes(keyPair);
    final pubBytes = await _crypto.publicKeyBytes(keyPair);
    await _storage.write(key: _privateKeyKey, value: base64.encode(privBytes));
    await _storage.write(key: _publicKeyKey, value: base64.encode(pubBytes));
    return _crypto.restoreIdentityKeyPair(
      privateKey: privBytes,
      publicKey: pubBytes,
    );
  }

  /// Wipe identity keys (e.g. on "purge my data"). Irreversible.
  Future<void> wipe() async {
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _publicKeyKey);
  }
}
