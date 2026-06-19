// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/chat_message.dart';

/// Result of the mayday alert dialog.
enum MaydayResponse {
  /// User wants to be routed to the sender's last known position.
  navigate,

  /// User dismissed the alert — no navigation, but they've been told.
  dismiss,
}

/// Full-screen modal shown when an inbound mayday lands. Red-themed, large
/// touch targets, default action is Navigate. Use [MaydayAlertDialog.show]
/// to display — returns the picked response.
class MaydayAlertDialog extends StatelessWidget {
  const MaydayAlertDialog({
    super.key,
    required this.message,
    required this.selfLocation,
  });

  final ChatMessage message;
  final LatLng? selfLocation;

  static Future<MaydayResponse?> show(
    BuildContext context, {
    required ChatMessage message,
    required LatLng? selfLocation,
  }) {
    return Navigator.of(context, rootNavigator: true).push<MaydayResponse>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => MaydayAlertDialog(
          message: message,
          selfLocation: selfLocation,
        ),
      ),
    );
  }

  String? _distanceLabel() {
    final m = message.mayday;
    final me = selfLocation;
    if (m == null || me == null) return null;
    if (m.location.latitude == 0 && m.location.longitude == 0) return null;
    const d = Distance();
    final meters = d.as(LengthUnit.Meter, me, m.location);
    final miles = meters / 1609.344;
    if (miles < 0.1) return '${(meters * 3.28084).round()} ft away';
    return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi away';
  }

  bool get _hasFix {
    final loc = message.mayday?.location;
    return loc != null && !(loc.latitude == 0 && loc.longitude == 0);
  }

  @override
  Widget build(BuildContext context) {
    final dist = _distanceLabel();
    return Scaffold(
      backgroundColor: const Color(0xFF1a0e0e),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFff5252), size: 96),
              const SizedBox(height: 24),
              Text(
                'MAN DOWN',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                        color: Colors.red.withValues(alpha: 0.6),
                        blurRadius: 12),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message.callsign,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFffd6d6),
                ),
              ),
              if (message.text.isNotEmpty &&
                  message.text.toLowerCase() != 'man down') ...[
                const SizedBox(height: 12),
                Text(
                  '"${message.text}"',
                  style: const TextStyle(
                      color: Color(0xFFffd6d6), fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (_hasFix) ...[
                if (dist != null)
                  Text(
                    dist,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 24),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No GPS fix attached to this alert. Open the chat to '
                    'coordinate verbally — their last known position is '
                    'on the map.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Spacer(),
              if (_hasFix)
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                        MaydayResponse.navigate),
                    icon: const Icon(Icons.navigation, size: 26),
                    label: const Text(
                      'Navigate to them',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.amber,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                      MaydayResponse.dismiss),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  child: const Text(
                    'I see it — close',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
