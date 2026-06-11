// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

/// A member of a party as stored in `public.party_members`.
class PartyMember {
  const PartyMember({
    required this.id,
    required this.partyId,
    required this.userId,
    required this.callsign,
    required this.color,
    required this.joinedAt,
  });

  final String id;
  final String partyId;
  final String userId;
  final String callsign;
  final String color;
  final DateTime joinedAt;

  factory PartyMember.fromJson(Map<String, dynamic> json) => PartyMember(
        id: json['id'] as String,
        partyId: json['party_id'] as String,
        userId: json['user_id'] as String,
        callsign: json['callsign'] as String,
        color: json['color'] as String? ?? '#C19A6B',
        joinedAt: DateTime.parse(json['joined_at'] as String),
      );
}
