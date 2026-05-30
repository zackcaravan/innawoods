import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encrypted_payload.dart';

/// The cryptographic heart of innawoods.
///
/// Design (zero-knowledge server):
///
///  * Every user has a long-lived **X25519 identity keypair**. The public key
///    is published to the server (`users.public_key`); the private key never
///    leaves the device's secure storage.
///  * Every party has a random 256-bit **group secret** that is generated on
///    the client and **never sent to the server**. It travels only inside the
///    invite (the part after `#`, see [PartyInvite]).
///  * The symmetric **group key** is derived from that secret with
///    HKDF-SHA256, salted with the party id. All location pings, pins, routes
///    and messages are sealed with XChaCha20-Poly1305 under this key before
///    they touch Supabase.
///  * For future private invites, [wrapSecretForMember] / [unwrapSecret]
///    deliver the group secret to a specific member's public key using an
///    ephemeral-X25519 sealed box — the libsodium-style hybrid.
///
/// All primitives come from the open-source `cryptography` package.
class CryptoService {
  CryptoService({Cipher? aead, X25519? keyExchange, Random? random})
      : _aead = aead ?? Xchacha20.poly1305Aead(),
        _kx = keyExchange ?? X25519(),
        _random = random ?? Random.secure();

  final Cipher _aead;
  final X25519 _kx;
  final Random _random;

  /// Domain-separation label, baked into the HKDF salt so keys derived here
  /// can never collide with keys derived for another purpose.
  static const String _groupKeyContext = 'innawoods-group-key-v1';
  static const String _wrapKeyContext = 'innawoods-wrap-v1';
  static const int groupSecretLength = 32;

  // ---------------------------------------------------------------------------
  // Identity keys
  // ---------------------------------------------------------------------------

  /// Generate a fresh X25519 identity keypair for a new user.
  Future<SimpleKeyPair> generateIdentityKeyPair() => _kx.newKeyPair();

  /// Raw 32-byte public key (published to `users.public_key`).
  Future<Uint8List> publicKeyBytes(SimpleKeyPair keyPair) async {
    final pub = await keyPair.extractPublicKey();
    return Uint8List.fromList(pub.bytes);
  }

  /// Raw 32-byte private key (stored only in device secure storage).
  Future<Uint8List> privateKeyBytes(SimpleKeyPair keyPair) async =>
      Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

  /// Rebuild a keypair from the bytes persisted in secure storage.
  SimpleKeyPair restoreIdentityKeyPair({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) {
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  // ---------------------------------------------------------------------------
  // Group secret + group key
  // ---------------------------------------------------------------------------

  /// A new random 256-bit party secret. Stays client-side forever.
  Uint8List generateGroupSecret() => _randomBytes(groupSecretLength);

  /// Derive the symmetric group key shared by everyone holding [groupSecret].
  ///
  /// The HKDF salt binds the key to both the purpose and this specific party,
  /// so the same secret used in two parties would still yield different keys.
  Future<SecretKey> deriveGroupKey({
    required Uint8List groupSecret,
    required String partyId,
  }) {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(groupSecret),
      nonce: utf8.encode('$_groupKeyContext|$partyId'),
    );
  }

  // ---------------------------------------------------------------------------
  // Payload sealing (the trust boundary)
  // ---------------------------------------------------------------------------

  /// Encrypt a JSON-serialisable payload under the group key.
  Future<EncryptedPayload> encryptJson({
    required Map<String, dynamic> data,
    required SecretKey groupKey,
  }) async {
    final clear = utf8.encode(jsonEncode(data));
    final box = await _aead.encrypt(clear, secretKey: groupKey);
    return EncryptedPayload(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  /// Decrypt a payload. Throws [SecretBoxAuthenticationError] if the blob has
  /// been tampered with or the wrong key is used.
  Future<Map<String, dynamic>> decryptJson({
    required EncryptedPayload payload,
    required SecretKey groupKey,
  }) async {
    final box = SecretBox(
      payload.cipherText,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );
    final clear = await _aead.decrypt(box, secretKey: groupKey);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Sealed box: deliver the group secret to one member's public key
  // (ephemeral X25519 -> HKDF -> XChaCha20-Poly1305). Used by private invites.
  // ---------------------------------------------------------------------------

  /// Wrap [groupSecret] so only the holder of the private key matching
  /// [recipientPublicKey] can recover it. Returns the ephemeral public key and
  /// the sealed blob, both safe to store server-side.
  Future<WrappedSecret> wrapSecretForMember({
    required Uint8List groupSecret,
    required Uint8List recipientPublicKey,
  }) async {
    final ephemeral = await _kx.newKeyPair();
    final ephemeralPublic =
        Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final wrapKey = await _deriveWrapKey(
      keyPair: ephemeral,
      remotePublicKey: recipientPublicKey,
      ephemeralPublic: ephemeralPublic,
    );
    final box = await _aead.encrypt(groupSecret, secretKey: wrapKey);
    return WrappedSecret(
      ephemeralPublicKey: ephemeralPublic,
      blob: EncryptedPayload(
        nonce: Uint8List.fromList(box.nonce),
        cipherText: Uint8List.fromList(box.cipherText),
        mac: Uint8List.fromList(box.mac.bytes),
      ),
    );
  }

  /// Recover a group secret wrapped for [identity] via [wrapSecretForMember].
  Future<Uint8List> unwrapSecret({
    required WrappedSecret wrapped,
    required SimpleKeyPair identity,
  }) async {
    final wrapKey = await _deriveWrapKey(
      keyPair: identity,
      remotePublicKey: wrapped.ephemeralPublicKey,
      ephemeralPublic: wrapped.ephemeralPublicKey,
    );
    final box = SecretBox(
      wrapped.blob.cipherText,
      nonce: wrapped.blob.nonce,
      mac: Mac(wrapped.blob.mac),
    );
    return Uint8List.fromList(await _aead.decrypt(box, secretKey: wrapKey));
  }

  Future<SecretKey> _deriveWrapKey({
    required SimpleKeyPair keyPair,
    required Uint8List remotePublicKey,
    required Uint8List ephemeralPublic,
  }) async {
    final shared = await _kx.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey:
          SimplePublicKey(remotePublicKey, type: KeyPairType.x25519),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('$_wrapKeyContext|${base64.encode(ephemeralPublic)}'),
    );
  }

  Uint8List _randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}

/// A group secret sealed for a single recipient, plus the ephemeral public key
/// needed to open it. Both fields are safe to persist on the server.
class WrappedSecret {
  WrappedSecret({required this.ephemeralPublicKey, required this.blob});

  final Uint8List ephemeralPublicKey;
  final EncryptedPayload blob;
}
