// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

/// A user profile as stored in `public.users`. No email, no phone — anonymous
/// auth means the only identity is the auth uid + a published X25519 public key.
class AppUser {
  const AppUser({
    required this.id,
    required this.avatarColor,
    required this.publicKey,
    this.displayName,
  });

  final String id;
  final String? displayName;
  final String avatarColor;
  final String publicKey;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        avatarColor: json['avatar_color'] as String? ?? '#8A9A5B',
        publicKey: json['public_key'] as String,
      );
}
