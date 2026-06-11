// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/services/party_service.dart';
import '../../../shared/widgets/color_picker_row.dart';
import '../providers/party_provider.dart';

class CreatePartyScreen extends ConsumerStatefulWidget {
  const CreatePartyScreen({super.key});

  @override
  ConsumerState<CreatePartyScreen> createState() => _CreatePartyScreenState();
}

class _CreatePartyScreenState extends ConsumerState<CreatePartyScreen> {
  final _callsign = TextEditingController();
  final _name = TextEditingController();
  String _color = AppTheme.memberPalette.first;
  bool _ephemeral = true;
  bool _busy = false;
  String? _error;
  CreatedParty? _created;

  @override
  void dispose() {
    _callsign.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final callsign = _callsign.text.trim();
    if (callsign.isEmpty) {
      setState(() => _error = 'Pick a callsign so your crew knows who you are.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref.read(partyServiceProvider).createParty(
            callsign: callsign,
            color: _color,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            ephemeral: _ephemeral,
          );
      ref.invalidate(myPartiesProvider);
      setState(() => _created = created);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create party')),
      body: SafeArea(
        child: _created != null
            ? _InviteResult(created: _created!)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _callsign,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Your callsign',
                      hintText: 'BIGBEAR',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Your color on the map'),
                  const SizedBox(height: 10),
                  ColorPickerRow(
                    selected: _color,
                    onChanged: (c) => setState(() => _color = c),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _ephemeral,
                    onChanged: (v) => setState(() => _ephemeral = v),
                    title: const Text('Ephemeral'),
                    subtitle: const Text(
                        'Self-destructs all data when the session ends. Off = named, recurring crew.'),
                  ),
                  if (!_ephemeral) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Crew name (optional)',
                        hintText: 'Saturday Riders',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create & get invite'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InviteResult extends StatelessWidget {
  const _InviteResult({required this.created});
  final CreatedParty created;

  @override
  Widget build(BuildContext context) {
    final link = created.shareLink;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.check_circle, color: AppTheme.olive, size: 56),
        const SizedBox(height: 12),
        Center(
          child: Text('Party ready',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 4),
        Center(child: Text('Code ${created.party.inviteCode}')),
        const SizedBox(height: 24),
        const Text('Send this invite to your crew. The secret in it never '
            'touches our servers — only people you send it to can decrypt the '
            'party.'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(link,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite copied')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Share.share(
                    'Join my innawoods party:\n$link',
                    subject: 'innawoods invite'),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        FilledButton.tonal(
          onPressed: () => context.go('/party/${created.party.id}'),
          child: const Text('Go to party'),
        ),
      ],
    );
  }
}
