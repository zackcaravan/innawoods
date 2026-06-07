import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera-based QR scanner that returns the decoded `innawoods://join/...`
/// link to the caller via `Navigator.pop`. The join screen pre-fills its
/// link field with whatever comes back, so the user never has to type the
/// 43-character secret by hand.
///
/// Only accepts strings that start with `innawoods://join/` so a random
/// QR (a wifi sticker, a URL on a flyer) can't accidentally drop the user
/// into a malformed join attempt.
class ScanInviteQrScreen extends StatefulWidget {
  const ScanInviteQrScreen({super.key});

  @override
  State<ScanInviteQrScreen> createState() => _ScanInviteQrScreenState();
}

class _ScanInviteQrScreenState extends State<ScanInviteQrScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _captured = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_captured) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      if (raw.startsWith('innawoods://join/')) {
        _captured = true;
        context.pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan invite QR'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) =>
                _ScannerError(error: error),
          ),
          // Reticle + instruction overlay drawn on top of the live preview.
          // Just a visual guide for the user; the decoder reads the whole
          // frame regardless of where the QR sits.
          const Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Colors.white70, width: 2),
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Text(
                'Point at the QR on the other phone',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, color: Colors.amber, size: 48),
            const SizedBox(height: 12),
            Text(
              'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure camera permission is granted and no other app is '
              'using the camera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
