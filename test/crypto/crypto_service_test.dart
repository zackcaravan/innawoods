// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innawoods/core/crypto/crypto_service.dart';
import 'package:innawoods/core/crypto/encrypted_payload.dart';
import 'package:innawoods/core/crypto/party_invite.dart';

void main() {
  final crypto = CryptoService();
  const partyId = 'b3f1c2a4-0000-4000-8000-000000000001';

  // A realistic location ping — the kind of data the server must NEVER read.
  Map<String, dynamic> sampleLocation() => {
        'lat': 47.6062,
        'lng': -122.3321,
        'speed': 12.4,
        'heading': 270,
        'ts': '2026-05-24T19:30:00Z',
      };

  group('identity keys', () {
    test('generates a 32-byte X25519 keypair', () async {
      final kp = await crypto.generateIdentityKeyPair();
      expect((await crypto.publicKeyBytes(kp)).length, 32);
      expect((await crypto.privateKeyBytes(kp)).length, 32);
    });

    test('restores an equivalent keypair from stored bytes', () async {
      final kp = await crypto.generateIdentityKeyPair();
      final priv = await crypto.privateKeyBytes(kp);
      final pub = await crypto.publicKeyBytes(kp);
      final restored = crypto.restoreIdentityKeyPair(privateKey: priv, publicKey: pub);
      expect(await crypto.privateKeyBytes(restored), priv);
      expect(await crypto.publicKeyBytes(restored), pub);
    });
  });

  group('group key derivation', () {
    test('is deterministic for the same secret + party', () async {
      final secret = crypto.generateGroupSecret();
      final a = await (await crypto.deriveGroupKey(groupSecret: secret, partyId: partyId)).extractBytes();
      final b = await (await crypto.deriveGroupKey(groupSecret: secret, partyId: partyId)).extractBytes();
      expect(a, b);
      expect(a.length, 32);
    });

    test('differs across parties even with the same secret', () async {
      final secret = crypto.generateGroupSecret();
      final a = await (await crypto.deriveGroupKey(groupSecret: secret, partyId: partyId)).extractBytes();
      final b = await (await crypto.deriveGroupKey(groupSecret: secret, partyId: 'other-party')).extractBytes();
      expect(a, isNot(b));
    });

    test('differs across secrets', () async {
      final a = await (await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId)).extractBytes();
      final b = await (await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId)).extractBytes();
      expect(a, isNot(b));
    });
  });

  group('payload sealing', () {
    test('round-trips an encrypted payload', () async {
      final key = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final payload = await crypto.encryptJson(data: sampleLocation(), groupKey: key);
      final decrypted = await crypto.decryptJson(payload: payload, groupKey: key);
      expect(decrypted, sampleLocation());
    });

    test('survives the wire format (toWire/fromWire)', () async {
      final key = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final wire = (await crypto.encryptJson(data: sampleLocation(), groupKey: key)).toWire();
      final decrypted = await crypto.decryptJson(payload: EncryptedPayload.fromWire(wire), groupKey: key);
      expect(decrypted, sampleLocation());
    });

    test('ZERO-PLAINTEXT: no coordinates or text leak into the blob', () async {
      final key = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final data = {'lat': 47.6062, 'lng': -122.3321, 'note': 'rendezvous at the ridge'};
      final wire = (await crypto.encryptJson(data: data, groupKey: key)).toWire();
      final blob = base64.decode(wire);

      bool contains(Uint8List haystack, List<int> needle) {
        for (var i = 0; i + needle.length <= haystack.length; i++) {
          var match = true;
          for (var j = 0; j < needle.length; j++) {
            if (haystack[i + j] != needle[j]) { match = false; break; }
          }
          if (match) return true;
        }
        return false;
      }

      // Skip the 24-byte nonce prefix; check the ciphertext region.
      final ct = Uint8List.sublistView(blob, EncryptedPayload.nonceLength);
      expect(contains(ct, utf8.encode('47.6062')), isFalse, reason: 'lat leaked');
      expect(contains(ct, utf8.encode('122.3321')), isFalse, reason: 'lng leaked');
      expect(contains(ct, utf8.encode('rendezvous')), isFalse, reason: 'text leaked');
      expect(contains(ct, utf8.encode('"lat"')), isFalse, reason: 'json keys leaked');
    });

    test('rejects a tampered ciphertext', () async {
      final key = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final payload = await crypto.encryptJson(data: sampleLocation(), groupKey: key);
      payload.cipherText[0] ^= 0xFF; // flip a byte
      expect(
        () => crypto.decryptJson(payload: payload, groupKey: key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('cannot be decrypted with the wrong key', () async {
      final key1 = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final key2 = await crypto.deriveGroupKey(groupSecret: crypto.generateGroupSecret(), partyId: partyId);
      final payload = await crypto.encryptJson(data: sampleLocation(), groupKey: key1);
      expect(
        () => crypto.decryptJson(payload: payload, groupKey: key2),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('sealed box (private invite delivery)', () {
    test('only the intended member can unwrap the group secret', () async {
      final secret = crypto.generateGroupSecret();
      final member = await crypto.generateIdentityKeyPair();
      final outsider = await crypto.generateIdentityKeyPair();
      final memberPub = await crypto.publicKeyBytes(member);

      final wrapped = await crypto.wrapSecretForMember(groupSecret: secret, recipientPublicKey: memberPub);

      expect(await crypto.unwrapSecret(wrapped: wrapped, identity: member), secret);
      await expectLater(
        crypto.unwrapSecret(wrapped: wrapped, identity: outsider),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('invite links', () {
    test('round-trips code + secret through a share link', () {
      final invite = PartyInvite.create(secret: crypto.generateGroupSecret());
      final parsed = PartyInvite.parse(invite.toShareLink());
      expect(parsed.code, invite.code);
      expect(parsed.secret, invite.secret);
    });

    test('generates an 8-char human-typable code', () {
      final invite = PartyInvite.create(secret: crypto.generateGroupSecret());
      expect(invite.code.length, PartyInvite.codeLength);
      expect(invite.code, matches(RegExp(r'^[2-9A-HJ-NP-Z]+$')));
    });
  });
}
