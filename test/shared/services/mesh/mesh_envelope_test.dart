// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:innawoods/shared/services/mesh/mesh_envelope.dart';

void main() {
  group('MeshEnvelope', () {
    final uuidBytes = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final ciphertext = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);

    test('encode → decode roundtrip preserves every field', () {
      final hash = MeshEnvelope.hashParty('SOMEPARTY');
      final env = MeshEnvelope(
        type: MeshMsgType.chat,
        partyIdHash: hash,
        msgUuidBytes: uuidBytes,
        timestampMs: 0x0102030405060708,
        ciphertext: ciphertext,
      );
      final wire = env.encode();
      final decoded = MeshEnvelope.tryDecode(wire);
      expect(decoded, isNotNull);
      expect(decoded!.type, MeshMsgType.chat);
      expect(decoded.partyIdHash, hash);
      expect(decoded.msgUuidBytes, uuidBytes);
      expect(decoded.timestampMs, 0x0102030405060708);
      expect(decoded.ciphertext, ciphertext);
    });

    test('wire format begins with magic bytes + version + type', () {
      final env = MeshEnvelope(
        type: MeshMsgType.position,
        partyIdHash: Uint8List(8),
        msgUuidBytes: uuidBytes,
        timestampMs: 0,
        ciphertext: ciphertext,
      );
      final wire = env.encode();
      expect(wire[0], 0x49); // 'I'
      expect(wire[1], 0x4E); // 'N'
      expect(wire[2], 0x57); // 'W'
      expect(wire[3], 0x44); // 'D'
      expect(wire[4], MeshEnvelope.version);
      expect(wire[5], MeshMsgType.position.wireId);
    });

    test('partyIdHash is deterministic for the same party id', () {
      final a = MeshEnvelope.hashParty('crew-001');
      final b = MeshEnvelope.hashParty('crew-001');
      final c = MeshEnvelope.hashParty('crew-002');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.length, 8);
    });

    test('decode rejects malformed input', () {
      expect(MeshEnvelope.tryDecode(Uint8List.fromList([])), isNull);
      expect(MeshEnvelope.tryDecode(Uint8List.fromList(List.filled(10, 0))),
          isNull); // too short
      expect(
          MeshEnvelope.tryDecode(Uint8List.fromList(
              List<int>.filled(60, 0)..[0] = 0x00)),
          isNull); // wrong magic
    });

    test('decode rejects unknown msg-type byte', () {
      final env = MeshEnvelope(
        type: MeshMsgType.chat,
        partyIdHash: Uint8List(8),
        msgUuidBytes: uuidBytes,
        timestampMs: 0,
        ciphertext: ciphertext,
      );
      final wire = env.encode();
      wire[5] = 99; // tamper with msg-type
      expect(MeshEnvelope.tryDecode(wire), isNull);
    });

    test('encode rejects oversize ciphertext', () {
      expect(
        () => MeshEnvelope(
          type: MeshMsgType.chat,
          partyIdHash: Uint8List(8),
          msgUuidBytes: uuidBytes,
          timestampMs: 0,
          ciphertext: Uint8List(MeshEnvelope.maxCiphertextBytes + 1),
        ).encode(),
        throwsArgumentError,
      );
    });

    test('encoded payload size = 38 + ciphertext.length', () {
      final env = MeshEnvelope(
        type: MeshMsgType.chat,
        partyIdHash: Uint8List(8),
        msgUuidBytes: uuidBytes,
        timestampMs: 0,
        ciphertext: Uint8List(64),
      );
      expect(env.encode().length, 38 + 64);
    });
  });
}
