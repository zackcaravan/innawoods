// End-to-end verification of the innawoods privacy model against a live
// Supabase instance (local or hosted). It proves the core Phase-1 claim:
//
//   * two members of a party can share an encrypted location and read it back,
//   * the row stored on the server is ciphertext only (no plaintext coords),
//   * a non-member is blocked by RLS from reading the party's data.
//
// Run (local stack):
//   eval "$(supabase status -o env | sed 's/^/export /')"   # or set manually
//   dart run tool/verify_e2e.dart --url "$API_URL" --anon "$ANON_KEY"
//
// Run (hosted):
//   dart run tool/verify_e2e.dart --url https://xxx.supabase.co --anon eyJ...
//
// Exit code 0 = all checks passed.
import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:innawoods/core/crypto/crypto_service.dart';
import 'package:innawoods/core/crypto/encrypted_payload.dart';
import 'package:innawoods/core/crypto/party_invite.dart';

late String url;
late String anonKey;
String? serviceKey; // optional: service-role key to create pre-confirmed users
bool anonAuth = false; // --anon-auth: use signInAnonymously (the real app path)
SupabaseClient? adminClient;
final List<String> createdUserIds = [];

int _checks = 0;
void check(bool cond, String label) {
  _checks++;
  if (!cond) {
    stderr.writeln('  ✗ FAIL: $label');
    throw _VerifyFailure(label);
  }
  stdout.writeln('  ✓ $label');
}

Future<void> main(List<String> args) async {
  _parseArgs(args);
  final crypto = CryptoService();

  // Each member is a separate authenticated client, like separate phones.
  // Implicit flow: headless script, no PKCE async storage needed.
  SupabaseClient newClient() => SupabaseClient(url, anonKey,
      authOptions:
          const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  final alice = newClient();
  final bob = newClient();
  final mallory = newClient(); // not invited to the party
  if (serviceKey != null) {
    adminClient = SupabaseClient(url, serviceKey!);
  }

  try {
    stdout.writeln('\n[1] Register users with X25519 identity keys');
    final aliceKp = await crypto.generateIdentityKeyPair();
    final bobKp = await crypto.generateIdentityKeyPair();
    final aliceId = await _signUpAndProfile(alice, crypto, aliceKp, 'Alice');
    final bobId = await _signUpAndProfile(bob, crypto, bobKp, 'Bob');
    await _signUpAndProfile(
        mallory, crypto, await crypto.generateIdentityKeyPair(), 'Mallory');
    check(aliceId != bobId, 'distinct user ids issued');

    stdout.writeln('\n[2] Alice creates a party (group secret stays client-side)');
    final groupSecret = crypto.generateGroupSecret();
    final invite = PartyInvite.create(secret: groupSecret);
    // create_party assigns its own id; we read it back rather than forcing one.
    final partyRow = await alice.rpc('create_party', params: {
      'p_invite_code': invite.code,
      'p_callsign': 'BIGBEAR',
      'p_color': '#C19A6B',
      'p_ephemeral': true,
    }) as Map<String, dynamic>;
    final realPartyId = partyRow['id'] as String;
    check(realPartyId.isNotEmpty, 'party created via RPC');
    check(partyRow['invite_code'] == invite.code, 'invite code stored');
    // The shareable link Alice would text to Bob:
    stdout.writeln('     share link: ${invite.toShareLink()}');

    stdout.writeln('\n[3] Alice encrypts a location and upserts it');
    final groupKey =
        await crypto.deriveGroupKey(groupSecret: groupSecret, partyId: realPartyId);
    final location = {
      'lat': 47.6062,
      'lng': -122.3321,
      'speed': 12.4,
      'heading': 270,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    final sealed = await crypto.encryptJson(data: location, groupKey: groupKey);
    await alice.from('location_updates').upsert({
      'party_id': realPartyId,
      'user_id': aliceId,
      'encrypted_payload': sealed.toWire(),
    }, onConflict: 'party_id,user_id');
    check(true, 'encrypted location written to Supabase');

    stdout.writeln('\n[4] Server stores ciphertext ONLY (zero-knowledge)');
    final rawRows = await alice
        .from('location_updates')
        .select('encrypted_payload')
        .eq('party_id', realPartyId) as List<dynamic>;
    final storedBlob = (rawRows.first as Map)['encrypted_payload'] as String;
    check(!storedBlob.contains('47.6062'), 'latitude not present in stored row');
    check(!storedBlob.contains('122.3321'), 'longitude not present in stored row');
    check(!storedBlob.contains('"lat"'), 'json keys not present in stored row');

    stdout.writeln('\n[5] Bob joins from the invite and decrypts Alice\'s ping');
    final joinRow = await bob.rpc('join_party', params: {
      'p_invite_code': invite.code,
      'p_callsign': 'REDFOX',
      'p_color': '#8A9A5B',
    }) as Map<String, dynamic>;
    check(joinRow['id'] == realPartyId, 'Bob joined the same party');
    // Bob derives the SAME key from the secret in the invite + the party id.
    final bobKey =
        await crypto.deriveGroupKey(groupSecret: invite.secret, partyId: realPartyId);
    final bobView = await bob
        .from('location_updates')
        .select('encrypted_payload')
        .eq('party_id', realPartyId) as List<dynamic>;
    final bobBlob = (bobView.first as Map)['encrypted_payload'] as String;
    final decrypted = await crypto.decryptJson(
        payload: EncryptedPayload.fromWire(bobBlob), groupKey: bobKey);
    check(decrypted['lat'] == 47.6062 && decrypted['lng'] == -122.3321,
        'Bob decrypted Alice\'s exact coordinates');

    stdout.writeln('\n[6] RLS blocks a non-member (Mallory) from reading data');
    final malloryView = await mallory
        .from('location_updates')
        .select('encrypted_payload')
        .eq('party_id', realPartyId) as List<dynamic>;
    check(malloryView.isEmpty, 'non-member sees zero rows (RLS enforced)');

    stdout.writeln('\n[7] Ending the ephemeral party self-destructs session data');
    await alice.rpc('end_party', params: {'p_party_id': realPartyId});
    final afterEnd = await bob
        .from('location_updates')
        .select('id')
        .eq('party_id', realPartyId) as List<dynamic>;
    check(afterEnd.isEmpty, 'location data purged on session end');

    // Tidy up: remove every throwaway verify-*@innawoods.test user (this run
    // and any prior runs) so the project is left clean.
    if (adminClient != null) {
      stdout.writeln('\n[8] Cleaning up throwaway test users');
      final toDelete = <String>{...createdUserIds};
      final users = await adminClient!.auth.admin.listUsers();
      for (final u in users) {
        final e = u.email ?? '';
        if (e.startsWith('verify-') && e.endsWith('@innawoods.test')) {
          toDelete.add(u.id);
        }
      }
      for (final id in toDelete) {
        await adminClient!.auth.admin.deleteUser(id);
      }
      stdout.writeln('  ✓ removed ${toDelete.length} test user(s)');
    }

    stdout.writeln('\n──────────────────────────────────────────────');
    stdout.writeln('ALL $_checks CHECKS PASSED — encrypted payload round-trips '
        'end to end, server holds ciphertext only.');
    stdout.writeln('──────────────────────────────────────────────\n');
  } on _VerifyFailure {
    stderr.writeln('\nVERIFICATION FAILED.');
    exitCode = 1;
  } catch (e, st) {
    stderr.writeln('\nUNEXPECTED ERROR: $e\n$st');
    exitCode = 2;
  } finally {
    alice.dispose();
    bob.dispose();
    mallory.dispose();
    adminClient?.dispose();
  }
}

Future<String> _signUpAndProfile(
  SupabaseClient client,
  CryptoService crypto,
  dynamic keyPair,
  String name,
) async {
  final email = 'verify-${const Uuid().v4()}@innawoods.test';
  const password = 'Innawoods!2026';
  final User? user;
  if (anonAuth) {
    // The real app path: anonymous sign-in, no email at all.
    final res = await client.auth.signInAnonymously();
    user = res.user;
    if (user == null) throw StateError('anonymous sign-in returned no user');
  } else if (adminClient != null) {
    // Hosted: create a pre-confirmed user via the service-role admin API,
    // then sign in on the user's own client to get a user-scoped session.
    await adminClient!.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    user = res.user;
    if (user == null) throw StateError('sign-in failed for $email');
  } else {
    final res = await client.auth.signUp(email: email, password: password);
    user = res.user;
    if (user == null || res.session == null) {
      throw StateError(
          'No session after signUp — pass --service <service_role_key> to '
          'create pre-confirmed users, or use the local stack.');
    }
  }
  final pub = await crypto.publicKeyBytes(keyPair);
  await client.from('users').insert({
    'id': user.id,
    'display_name': name,
    'public_key': base64.encode(pub),
  });
  createdUserIds.add(user.id);
  return user.id;
}

void _parseArgs(List<String> args) {
  String? u, a;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--url') u = args[i + 1];
    if (args[i] == '--anon') a = args[i + 1];
    if (args[i] == '--service') serviceKey = args[i + 1];
  }
  if (args.contains('--anon-auth')) anonAuth = true;
  serviceKey ??= Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  u ??= Platform.environment['SUPABASE_URL'] ?? Platform.environment['API_URL'];
  a ??= Platform.environment['SUPABASE_ANON_KEY'] ??
      Platform.environment['ANON_KEY'];
  if (u == null || a == null) {
    stderr.writeln('Usage: dart run tool/verify_e2e.dart --url <url> --anon <key>');
    exit(64);
  }
  url = u;
  anonKey = a;
}

class _VerifyFailure implements Exception {
  _VerifyFailure(this.label);
  final String label;
}
