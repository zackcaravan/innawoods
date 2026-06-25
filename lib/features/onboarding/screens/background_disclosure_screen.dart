// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Prominent in-app disclosure for background location. Required by Google
/// before requesting `ACCESS_BACKGROUND_LOCATION`; rejection during the Play
/// Console submission is automatic without it. The screen explains in plain
/// language what we collect, who sees it, when it stops, and lets the user
/// accept before any OS prompt fires.
///
/// This is presented as a full-screen modal (`fullscreenDialog: true`) rather
/// than a settings tile because the disclosure has to actively interrupt the
/// flow — passive copy elsewhere in the app doesn't satisfy the requirement.
class BackgroundDisclosureScreen extends StatelessWidget {
  const BackgroundDisclosureScreen({super.key});

  /// Push the screen as a modal route. Returns true if the user accepted
  /// (caller should then trigger the OS permission prompt), false if
  /// declined / dismissed.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const BackgroundDisclosureScreen(),
        fullscreenDialog: true,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Background location'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 8),
                    Icon(Icons.shield_outlined,
                        color: AppTheme.amber, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'So your crew can see you with the screen off',
                      style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Innawoods needs background location access so your '
                      "position keeps updating to the rest of your party "
                      'while your phone is in your pocket or pack. Without '
                      'it, the crew sees you go stale the moment the screen '
                      'turns off.',
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    _DisclosureRow(
                      icon: Icons.lock_outline,
                      title: 'End-to-end encrypted',
                      body: 'Your coordinates are sealed with a key only '
                          'your party holds. The server stores ciphertext. '
                          "We can't see where you are, ever.",
                    ),
                    _DisclosureRow(
                      icon: Icons.groups_outlined,
                      title: 'Only your party members see it',
                      body: 'Position updates flow only to people you '
                          'shared the party invite link with. No advertisers, '
                          "no third parties, no 'partners.'",
                    ),
                    _DisclosureRow(
                      icon: Icons.timer_outlined,
                      title: 'Stops the moment you leave the party',
                      body: 'Background updates run only while you have an '
                          'active party. Leave the party or uninstall the '
                          'app and broadcasting ends immediately.',
                    ),
                    _DisclosureRow(
                      icon: Icons.notifications_active_outlined,
                      title: "You'll see a notification while it's on",
                      body: 'A persistent notification shows whenever the '
                          'app is sharing your position in the background. '
                          'Tap it to return to the app or stop sharing.',
                    ),
                    _DisclosureRow(
                      icon: Icons.battery_saver_outlined,
                      title: 'Battery-aware',
                      body: 'Trip mode reduces fix accuracy and update rate '
                          'for multi-hour outings. You can configure or '
                          'disable background sharing in Settings any time.',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Colors.white60, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              // Platform-specific so iOS users don't see
                              // an Android-only instruction. Apple flagged
                              // the previous "Next, Android will ask…"
                              // text under 2.3.10 (third-party-platform
                              // references in app binary).
                              Platform.isIOS
                                  ? "Next, you'll be asked to choose "
                                      "'Always Allow' for this to work."
                                  : "Next, you'll be asked to choose "
                                      "'Allow all the time' for this to work.",
                              style: t.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Continue',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: AppTheme.amber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
