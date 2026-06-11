// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores each party's group secret in the OS keystore, keyed by party id.
///
/// The secret is the only thing that can derive a party's encryption key, and
/// it never goes to the server — so it lives here, on-device, and is wiped when
/// you leave or the party ends.
class PartySecretStore {
  PartySecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  String _key(String partyId) => 'innawoods.party.secret.$partyId';

  Future<void> save(String partyId, Uint8List secret) =>
      _storage.write(key: _key(partyId), value: base64.encode(secret));

  Future<Uint8List?> load(String partyId) async {
    final v = await _storage.read(key: _key(partyId));
    return v == null ? null : Uint8List.fromList(base64.decode(v));
  }

  Future<void> delete(String partyId) => _storage.delete(key: _key(partyId));
}
