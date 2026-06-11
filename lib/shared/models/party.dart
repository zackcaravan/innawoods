// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

/// A party (crew session) as stored in `public.parties`.
class Party {
  const Party({
    required this.id,
    required this.inviteCode,
    required this.createdBy,
    required this.ephemeral,
    required this.maxMembers,
    required this.createdAt,
    this.name,
    this.expiresAt,
    this.endedAt,
  });

  final String id;
  final String inviteCode;
  final String? name;
  final String createdBy;
  final bool ephemeral;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? endedAt;

  bool get isActive =>
      endedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));

  String get displayLabel => name?.trim().isNotEmpty == true ? name! : inviteCode;

  factory Party.fromJson(Map<String, dynamic> json) => Party(
        id: json['id'] as String,
        inviteCode: json['invite_code'] as String,
        name: json['name'] as String?,
        createdBy: json['created_by'] as String,
        ephemeral: json['ephemeral'] as bool? ?? true,
        maxMembers: (json['max_members'] as num?)?.toInt() ?? 12,
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String),
      );
}
