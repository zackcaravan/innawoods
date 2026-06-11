// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/party_provider.dart';

/// Landing screen. Gates on bootstrap (anonymous session + profile), then lists
/// the parties you belong to with Create / Join actions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider);
    return boot.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not start a secure session.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (_) => const _HomeBody(),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(myPartiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('innawoods'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(myPartiesProvider.future),
        child: parties.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text('Failed to load parties\n$e', textAlign: TextAlign.center)),
          ]),
          data: (list) {
            final active = list.where((p) => p.isActive).toList();
            if (active.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 140),
                Icon(Icons.terrain, size: 56, color: AppTheme.olive),
                SizedBox(height: 12),
                Center(child: Text('No active parties yet.')),
                SizedBox(height: 6),
                Center(child: Text('Create one, or join your crew’s invite.')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: active.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = active[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups, color: AppTheme.tan),
                    title: Text(p.displayLabel),
                    subtitle: Text(p.ephemeral ? 'Ephemeral · code ${p.inviteCode}' : 'Persistent · code ${p.inviteCode}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/party/${p.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/join'),
                  icon: const Icon(Icons.login),
                  label: const Text('Join'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/create'),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Create party'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
