// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/user_error.dart';
import '../providers/party_provider.dart';

/// Crew-alert button. Long-press 2 seconds to fire — short taps are
/// deliberately ignored so a phone in a pack pocket won't accidentally
/// trigger a mayday for the whole crew. Visual + haptic feedback grows
/// over the 2s window so the user knows the button is "charging," and a
/// release at any point before the timeout cancels cleanly.
class ManDownButton extends ConsumerStatefulWidget {
  const ManDownButton({
    super.key,
    required this.partyId,
    this.onSent,
  });

  final String partyId;

  /// Optional callback fired after the broadcast goes out (regardless of
  /// transport success). Useful for the parent to dismiss a sheet or
  /// flash a confirmation.
  final VoidCallback? onSent;

  @override
  ConsumerState<ManDownButton> createState() => _ManDownButtonState();
}

class _ManDownButtonState extends ConsumerState<ManDownButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 2000);

  late final AnimationController _charge;
  bool _sending = false;
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();
    _charge = AnimationController(vsync: this, duration: _holdDuration);
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _charge.dispose();
    super.dispose();
  }

  void _onPressStart() {
    if (_sending) return;
    HapticFeedback.selectionClick();
    _charge.forward(from: 0);
    // Periodic haptic ticks while the user holds — they get a feel for
    // how much longer to keep their finger down.
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      HapticFeedback.lightImpact();
    });
    _charge.addStatusListener(_onStatus);
  }

  void _onPressEnd() {
    _hapticTimer?.cancel();
    _charge.removeStatusListener(_onStatus);
    if (_charge.status == AnimationStatus.completed) return; // already fired
    _charge.reverse();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_sending) {
      _hapticTimer?.cancel();
      HapticFeedback.heavyImpact();
      _fire();
    }
  }

  Future<void> _fire() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      // Best fix we can get right now. Don't block on it for too long —
      // mayday is more useful late-with-stale-fix than not-at-all.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.high))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {/* nothing usable; mayday will go out without a fix */}
      }
      final loc = pos != null
          ? LatLng(pos.latitude, pos.longitude)
          // Geographic origin as a "no fix available" sentinel. The
          // receive sheet checks for (0,0) and shows "no fix attached"
          // instead of routing to a bogus point.
          : const LatLng(0, 0);
      await ref.read(chatServiceProvider).sendMayday(
            partyId: widget.partyId,
            location: loc,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Man down sent. Your party has been alerted.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      widget.onSent?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _charge.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onPressStart(),
      onPointerUp: (_) => _onPressEnd(),
      onPointerCancel: (_) => _onPressEnd(),
      child: AnimatedBuilder(
        animation: _charge,
        builder: (_, _) {
          final progress = _charge.value;
          return SizedBox(
            width: double.infinity,
            height: 64,
            child: Stack(
              children: [
                // Idle background
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFF6e1116),
                  ),
                ),
                // Charge fill — grows left-to-right as the hold progresses.
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFcc2127),
                    ),
                  ),
                ),
                Center(
                  child: _sending
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.white),
                            const SizedBox(width: 10),
                            Text(
                              progress == 0
                                  ? 'Hold for Man down'
                                  : progress < 1
                                      ? 'Keep holding…'
                                      : 'Sending…',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
