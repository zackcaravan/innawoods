import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// First-launch intro — three swipeable pages explaining the app, then
/// "Get started" lands on the home screen. Sets a SharedPreferences flag so
/// the user never sees it again unless they wipe app data.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _kSeenKey = 'innawoods.onboarding.seen';

  /// Returns true if the user has already gone through onboarding.
  static Future<bool> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctl = PageController();
  int _page = 0;

  static const _pages = <_OnboardPage>[
    _OnboardPage(
      icon: Icons.forest_outlined,
      title: 'Welcome to innawoods',
      body:
          'Private real-time coordination for off-grid crews — map, chat, '
          'tracks, all end-to-end encrypted.\n\n'
          'The server stores ciphertext only. It never sees a coordinate, '
          'pin, route, or message.',
    ),
    _OnboardPage(
      icon: Icons.groups_outlined,
      title: 'Start or join a crew',
      body:
          'Tap Create to start a party, or Join with an invite link.\n\n'
          'The invite link includes a secret that the server never sees — '
          'only people you send it to can decrypt the party.',
    ),
    _OnboardPage(
      icon: Icons.map_outlined,
      title: 'Download a map',
      body:
          'The map only works when at least one region is on the device. '
          'Pick one from Settings → Downloaded regions before you head out '
          'of cell service.',
    ),
  ];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await OnboardingScreen.markSeen();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _ctl,
                onPageChanged: (p) => setState(() => _page = p),
                children: [for (final p in _pages) _PageView(page: p)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i == _page ? AppTheme.tan : Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  if (!last)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: Icon(last ? Icons.check : Icons.arrow_forward),
                    label: Text(last ? 'Get started' : 'Next'),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (last) {
                        _finish();
                      } else {
                        _ctl.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage {
  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});
  final _OnboardPage page;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.amber.withValues(alpha: 0.15),
              ),
              child: Icon(page.icon, size: 72, color: AppTheme.amber),
            ),
            const SizedBox(height: 32),
            Text(page.title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(page.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 15, height: 1.4)),
          ],
        ),
      );
}
