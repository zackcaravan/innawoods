// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

/// A decrypted chat message. Only `text` comes from the encrypted payload;
/// callsign is resolved from the party roster.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.callsign,
    required this.text,
    required this.sentAt,
    required this.mine,
  });

  final String id;
  final String senderId;
  final String callsign;
  final String text;
  final DateTime sentAt;
  final bool mine;
}
