// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';
import 'dart:typed_data';

/// An opaque encrypted blob, exactly as it is stored on the server.
///
/// The Supabase backend only ever sees [nonce] + [cipherText] + [mac]. It never
/// has the key, and therefore never has plaintext coordinates or message
/// content. This is the single unit that crosses the trust boundary.
///
/// Wire format (the base64 string written to Supabase):
///
///     base64( nonce[24] || cipherText[n] || mac[16] )
///
/// XChaCha20 uses a 24-byte nonce; Poly1305 produces a 16-byte MAC.
class EncryptedPayload {
  EncryptedPayload({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  /// XChaCha20 nonce (24 bytes).
  final Uint8List nonce;

  /// Ciphertext (same length as the plaintext).
  final Uint8List cipherText;

  /// Poly1305 authentication tag (16 bytes).
  final Uint8List mac;

  static const int nonceLength = 24;
  static const int macLength = 16;

  /// Encode to the single base64 string that is stored server-side.
  String toWire() {
    final out = Uint8List(nonce.length + cipherText.length + mac.length);
    out
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + cipherText.length, cipherText)
      ..setRange(nonce.length + cipherText.length, out.length, mac);
    return base64.encode(out);
  }

  /// Decode a blob read back from the server.
  factory EncryptedPayload.fromWire(String wire) =>
      EncryptedPayload.fromBytes(base64.decode(wire));

  /// Raw concatenated bytes — used by the mesh bridge so we don't pay the
  /// base64-encode→decode roundtrip when going over LoRa instead of HTTP.
  Uint8List toBytes() {
    final out = Uint8List(nonce.length + cipherText.length + mac.length);
    out
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + cipherText.length, cipherText)
      ..setRange(nonce.length + cipherText.length, out.length, mac);
    return out;
  }

  factory EncryptedPayload.fromBytes(List<int> bytes) {
    if (bytes.length < nonceLength + macLength) {
      throw const FormatException('Encrypted payload is too short to be valid');
    }
    return EncryptedPayload(
      nonce: Uint8List.sublistView(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          0,
          nonceLength),
      cipherText: Uint8List.sublistView(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          nonceLength,
          bytes.length - macLength),
      mac: Uint8List.sublistView(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          bytes.length - macLength),
    );
  }
}
