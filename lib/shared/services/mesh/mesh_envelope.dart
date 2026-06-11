// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;

/// Wire format for innawoods payloads going across the Meshtastic mesh.
///
/// Mesh peers may not be in the same innawoods party (e.g. a stranger's
/// repeater node in earshot), so each packet carries an 8-byte party-id
/// hash that lets receivers cheaply filter for "is this for me?" without
/// even attempting to decrypt the ciphertext.
///
/// We do NOT decrypt-and-re-encrypt at the bridge — the innawoods E2E
/// ciphertext travels intact over the mesh, and Meshtastic's radio-layer
/// encryption (channel PSK) wraps it again. Zero-knowledge property is
/// preserved across both transports.
///
/// Layout (big-endian):
///   0..3    magic 'INWD' (0x49 0x4E 0x57 0x44)
///   4       version (currently 1)
///   5       msg type (0=chat, 1=position, 2=ack — reserved)
///   6..13   party id hash (first 8 bytes of SHA-256(party_id))
///   14..29  message UUID (16 bytes; UUID v4 binary form)
///   30..37  unix ms timestamp (u64)
///   38..    ciphertext (variable — innawoods E2E blob)
///
/// Meshtastic's payload cap is ~228 bytes on the wire, leaving us ~190
/// bytes for the ciphertext after this envelope. A typical chat message
/// ciphertext is well under that; positions are ~50 bytes. Anything
/// larger drops on the floor with a log line (chunking lands in 8c if it
/// turns out we need it).
class MeshEnvelope {
  MeshEnvelope({
    required this.type,
    required this.partyIdHash,
    required this.msgUuidBytes,
    required this.timestampMs,
    required this.ciphertext,
  });

  static const int magic0 = 0x49; // I
  static const int magic1 = 0x4E; // N
  static const int magic2 = 0x57; // W
  static const int magic3 = 0x44; // D
  static const int version = 1;
  // Meshtastic's Data.payload caps at ~237 bytes on the wire. We need
  // 38 bytes for our envelope header, leaving 199 for ciphertext. We use
  // 200 as the published limit to keep the math human-readable and so a
  // single byte of jitter doesn't reject a valid send.
  static const int maxCiphertextBytes = 200;

  final MeshMsgType type;
  final Uint8List partyIdHash; // 8 bytes
  final Uint8List msgUuidBytes; // 16 bytes
  final int timestampMs;
  final Uint8List ciphertext;

  /// Compute an 8-byte hash of [partyId] suitable for the envelope. We
  /// use SHA-256 truncated rather than a raw substring because party ids
  /// are usually 8-char invite codes — colliding hashes would let two
  /// parties accidentally cross-receive packets.
  static Uint8List hashParty(String partyId) {
    final digest = sha256.convert(partyId.codeUnits).bytes;
    return Uint8List.fromList(digest.sublist(0, 8));
  }

  Uint8List encode() {
    if (ciphertext.length > maxCiphertextBytes) {
      throw ArgumentError(
          'ciphertext too large for mesh envelope: ${ciphertext.length} > $maxCiphertextBytes');
    }
    final out = BytesBuilder();
    out.addByte(magic0);
    out.addByte(magic1);
    out.addByte(magic2);
    out.addByte(magic3);
    out.addByte(version);
    out.addByte(type.wireId);
    out.add(partyIdHash);
    out.add(msgUuidBytes);
    final ts = ByteData(8)..setUint64(0, timestampMs);
    out.add(ts.buffer.asUint8List());
    out.add(ciphertext);
    return out.toBytes();
  }

  static MeshEnvelope? tryDecode(Uint8List bytes) {
    if (bytes.length < 38) return null;
    if (bytes[0] != magic0 ||
        bytes[1] != magic1 ||
        bytes[2] != magic2 ||
        bytes[3] != magic3) return null;
    if (bytes[4] != version) return null;
    final type = MeshMsgType.fromWire(bytes[5]);
    if (type == null) return null;
    final hash = Uint8List.sublistView(bytes, 6, 14);
    final uuid = Uint8List.sublistView(bytes, 14, 30);
    final ts = ByteData.sublistView(bytes, 30, 38).getUint64(0);
    final ciphertext = Uint8List.sublistView(bytes, 38);
    return MeshEnvelope(
      type: type,
      partyIdHash: Uint8List.fromList(hash),
      msgUuidBytes: Uint8List.fromList(uuid),
      timestampMs: ts,
      ciphertext: Uint8List.fromList(ciphertext),
    );
  }
}

enum MeshMsgType {
  chat(0),
  position(1),
  ack(2);

  const MeshMsgType(this.wireId);
  final int wireId;

  static MeshMsgType? fromWire(int v) {
    for (final m in values) {
      if (m.wireId == v) return m;
    }
    return null;
  }
}
