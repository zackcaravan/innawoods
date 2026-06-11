// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/party_invite.dart';
import '../models/party.dart';
import '../models/party_member.dart';
import 'crypto_session.dart';
import 'party_secret_store.dart';

/// Result of creating a party: the persisted row plus the invite to share.
class CreatedParty {
  CreatedParty({required this.party, required this.invite});
  final Party party;
  final PartyInvite invite;

  /// The link to hand to the crew. The secret in it never reached the server.
  String get shareLink => invite.toShareLink();
}

/// Create / join / leave / end parties and list the ones you belong to.
///
/// The group secret is generated (create) or parsed from the invite (join)
/// entirely client-side and stored in the keystore; the server only ever sees
/// the public invite code.
class PartyService {
  PartyService(this._client, this._crypto, this._secrets, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final PartySecretStore _secrets;
  final CryptoSession _session;

  Future<CreatedParty> createParty({
    required String callsign,
    required String color,
    String? name,
    bool ephemeral = true,
    Duration? ttl,
  }) async {
    final secret = _crypto.generateGroupSecret();
    final invite = PartyInvite.create(secret: secret);
    final expiresAt =
        ttl == null ? null : DateTime.now().toUtc().add(ttl).toIso8601String();

    final row = await _client.rpc('create_party', params: {
      'p_invite_code': invite.code,
      'p_callsign': callsign,
      'p_color': color,
      'p_name': name,
      'p_ephemeral': ephemeral,
      'p_expires_at': expiresAt,
    });
    final party = Party.fromJson(Map<String, dynamic>.from(row as Map));
    await _secrets.save(party.id, secret);
    await _rememberCachedParty(party);
    return CreatedParty(party: party, invite: invite);
  }

  /// Join from a full `innawoods://join/<code>#<secret>` link.
  Future<Party> joinFromLink({
    required String link,
    required String callsign,
    required String color,
  }) async {
    final invite = PartyInvite.parse(link);
    final row = await _client.rpc('join_party', params: {
      'p_invite_code': invite.code,
      'p_callsign': callsign,
      'p_color': color,
    });
    final party = Party.fromJson(Map<String, dynamic>.from(row as Map));
    await _secrets.save(party.id, invite.secret);
    await _rememberCachedParty(party);
    return party;
  }

  /// Persist enough of [p] in the local cache that a no-internet relaunch
  /// can still surface this party on the home screen. Idempotent — same
  /// party id is overwritten rather than duplicated.
  Future<void> _rememberCachedParty(Party p) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCachedParties);
    final list = <Map<String, dynamic>>[];
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = Map<String, dynamic>.from(e as Map);
          if (m['id'] != p.id) list.add(m);
        }
      } catch (_) {/* malformed cache — start fresh */}
    }
    list.insert(0, {
      'id': p.id,
      'name': p.name,
      'invite_code': p.inviteCode,
      'created_by': p.createdBy,
      'created_at': p.createdAt.toIso8601String(),
      'ephemeral': p.ephemeral,
    });
    await prefs.setString(_kCachedParties, jsonEncode(list));
  }

  /// Rebuild the shareable invite link for a party from the locally-stored
  /// secret. Returns null if this device doesn't hold the secret.
  Future<String?> shareLinkFor(Party party) async {
    final secret = await _secrets.load(party.id);
    if (secret == null) return null;
    return PartyInvite(code: party.inviteCode, secret: secret).toShareLink();
  }

  static const _kCachedParties = 'innawoods.parties.cached_json';

  Future<List<Party>> myParties() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = await _client
          .from('parties')
          .select()
          .order('created_at', ascending: false);
      final parties = (rows as List)
          .map((e) => Party.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      // Cache so a no-internet relaunch still lists what we already know
      // about — including the party you need to tap into when out of cell.
      await prefs.setString(
        _kCachedParties,
        jsonEncode([
          for (final p in parties)
            {
              'id': p.id,
              'name': p.name,
              'invite_code': p.inviteCode,
              'created_by': p.createdBy,
              'created_at': p.createdAt.toIso8601String(),
              'ephemeral': p.ephemeral,
            }
        ]),
      );
      return parties;
    } catch (_) {
      final raw = prefs.getString(_kCachedParties);
      if (raw == null) return const [];
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => Party.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        return list;
      } catch (_) {
        return const [];
      }
    }
  }

  Future<Party?> party(String partyId) async {
    try {
      final row = await _client
          .from('parties')
          .select()
          .eq('id', partyId)
          .maybeSingle();
      if (row != null) {
        final p = Party.fromJson(Map<String, dynamic>.from(row));
        await _rememberCachedParty(p);
        return p;
      }
    } catch (_) {/* fall through to cache */}
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCachedParties);
    if (raw == null) return null;
    try {
      for (final e in jsonDecode(raw) as List) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == partyId) return Party.fromJson(m);
      }
    } catch (_) {}
    return null;
  }

  Future<List<PartyMember>> members(String partyId) async {
    final rows = await _client
        .from('party_members')
        .select()
        .eq('party_id', partyId)
        .order('joined_at');
    return (rows as List)
        .map((e) => PartyMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Creator only: ends the session and self-destructs its data server-side.
  Future<void> endParty(String partyId) async {
    await _client.rpc('end_party', params: {'p_party_id': partyId});
    await _secrets.delete(partyId);
    _session.forget(partyId);
  }

  /// Any member: leave the party and wipe the local secret.
  Future<void> leaveParty(String partyId) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('party_members')
        .delete()
        .eq('party_id', partyId)
        .eq('user_id', uid);
    await _secrets.delete(partyId);
    _session.forget(partyId);
  }
}
