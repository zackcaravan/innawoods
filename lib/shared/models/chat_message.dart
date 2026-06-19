// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:latlong2/latlong.dart';

/// What kind of party message this is. Default is plain text chat; mayday
/// is a special "crew alert" message triggered by the Man-down button, sent
/// over the same encrypted chat transport so it reuses the dedup + mesh +
/// Supabase fanout already in place.
enum ChatKind {
  text,
  mayday;

  static ChatKind fromId(String? id) {
    switch (id) {
      case 'mayday': return ChatKind.mayday;
      default:       return ChatKind.text;
    }
  }

  String get id => name;
}

/// A decrypted chat message. `text` and (for mayday) `mayday` come from the
/// encrypted payload; callsign is resolved from the party roster.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.callsign,
    required this.text,
    required this.sentAt,
    required this.mine,
    this.kind = ChatKind.text,
    this.mayday,
  });

  final String id;
  final String senderId;
  final String callsign;
  final String text;
  final DateTime sentAt;
  final bool mine;

  /// Discriminator — `text` for regular chat, `mayday` for the crew alert.
  final ChatKind kind;

  /// Populated when [kind] is mayday — carries the sender's position at
  /// the time the alert fired, so receivers can route to them without
  /// waiting for the next location publish.
  final MaydayPayload? mayday;
}

/// Extra fields baked into a mayday message's encrypted payload.
class MaydayPayload {
  const MaydayPayload({
    required this.location,
    this.note,
  });

  /// Sender's GPS fix at the moment they confirmed the man-down button.
  final LatLng location;

  /// Optional short free-text note (e.g. "stuck at trailhead", "out of gas").
  /// Mostly future-proofing — the v1 button doesn't prompt for it.
  final String? note;
}
