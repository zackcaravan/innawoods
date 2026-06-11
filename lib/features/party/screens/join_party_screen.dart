// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/color_picker_row.dart';
import '../providers/party_provider.dart';
import 'scan_invite_qr_screen.dart';

class JoinPartyScreen extends ConsumerStatefulWidget {
  const JoinPartyScreen({super.key, this.initialLink});

  /// Prefilled when arriving from a deep link (Phase 2: manual paste).
  final String? initialLink;

  @override
  ConsumerState<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends ConsumerState<JoinPartyScreen> {
  late final TextEditingController _link =
      TextEditingController(text: widget.initialLink ?? '');
  final _callsign = TextEditingController();
  String _color = AppTheme.memberPalette[1];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    _callsign.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final link = _link.text.trim();
    final callsign = _callsign.text.trim();
    if (link.isEmpty) {
      setState(() => _error = 'Paste the invite link your crew sent you.');
      return;
    }
    if (callsign.isEmpty) {
      setState(() => _error = 'Pick a callsign.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final party = await ref.read(partyServiceProvider).joinFromLink(
            link: link,
            callsign: callsign,
            color: _color,
          );
      ref.invalidate(myPartiesProvider);
      if (mounted) context.go('/party/${party.id}');
    } on FormatException {
      setState(() => _error = 'That doesn’t look like a valid innawoods invite.');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join party')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      // Push the camera scanner; it pops back with the
                      // decoded invite link or null if the user canceled.
                      final result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const ScanInviteQrScreen(),
                          fullscreenDialog: true,
                        ),
                      );
                      if (result != null && mounted) {
                        setState(() {
                          _link.text = result;
                          _error = null;
                        });
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR from the other phone'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Or paste the invite link below:',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _link,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Invite link',
                hintText: 'innawoods://join/…',
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _callsign,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Your callsign',
                hintText: 'REDFOX',
              ),
            ),
            const SizedBox(height: 20),
            const Text('Your color on the map'),
            const SizedBox(height: 10),
            ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
