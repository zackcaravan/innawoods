// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Full-screen QR view for sharing a party invite without any internet,
/// SMS, or copy-paste. The receiving device scans this from the join
/// screen — zero typing means zero typos in the 43-character secret.
///
/// We render the QR on a white background even in dark mode because the
/// `mobile_scanner` decoder is much faster on a high-contrast white field.
class InviteQrDialog extends StatelessWidget {
  const InviteQrDialog({super.key, required this.link});

  /// Full innawoods://join/CODE#SECRET share link.
  final String link;

  /// Open the dialog. Convenience wrapper that picks a sensible barrier
  /// + animation for the lift-the-phone-up-to-the-camera UX.
  static Future<void> show(BuildContext context, String link) =>
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => InviteQrDialog(link: link),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan to join this party',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Open innawoods on the other device → Join → Scan QR',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 280,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              link,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11, height: 1.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'The fragment after # is the party\'s decryption key — '
              'innawoods\'s server never sees it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
