import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A shareable party invite.
///
/// The invite has two parts with very different trust properties:
///
///  * [code] — a short, human-typable lookup code. The server stores it
///    (`parties.invite_code`) so joiners can find the party. It is **not** a
///    secret; knowing it reveals nothing about the party's contents.
///  * [secret] — 256 bits of key material that the server **never** sees. It is
///    carried in the URL fragment (after `#`), which by convention is not sent
///    to servers. Combined with the party id it derives the group key.
///
/// Share link format:
///
///     innawoods://join/<code>#<secret-base64url>
///
/// Recipients look the party up by [code], learn the party id, then derive the
/// group key from [secret] + party id locally.
class PartyInvite {
  PartyInvite({required this.code, required this.secret});

  final String code;
  final Uint8List secret;

  /// Alphabet for the public lookup code — Crockford base32 minus easily
  /// confused characters (no I, L, O, U). Safe to read aloud or type.
  static const String _codeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int codeLength = 8;

  /// Generate a fresh invite: a random public code + a caller-supplied secret.
  factory PartyInvite.create({required Uint8List secret, Random? random}) {
    final rng = random ?? Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < codeLength; i++) {
      buf.write(_codeAlphabet[rng.nextInt(_codeAlphabet.length)]);
    }
    return PartyInvite(code: buf.toString(), secret: secret);
  }

  /// The full link to hand to someone over SMS/Signal/etc.
  String toShareLink() =>
      'innawoods://join/$code#${base64Url.encode(secret).replaceAll('=', '')}';

  /// Parse a share link back into its parts.
  factory PartyInvite.parse(String link) {
    final uri = Uri.parse(link.trim());
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final fragment = uri.fragment;
    if (code.isEmpty || fragment.isEmpty) {
      throw const FormatException('Not a valid innawoods invite link');
    }
    return PartyInvite(code: code, secret: _decodeSecret(fragment));
  }

  static Uint8List _decodeSecret(String fragment) {
    // Restore base64url padding stripped by toShareLink().
    final padded = fragment.padRight((fragment.length + 3) & ~3, '=');
    return Uint8List.fromList(base64Url.decode(padded));
  }
}
