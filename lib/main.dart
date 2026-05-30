import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/settings/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  // One container so the notification channel is ready before any alert.
  final container = ProviderContainer();
  await container.read(notificationServiceProvider).init();
  // First-launch users land on /onboarding instead of /.
  final seenOnboarding = await OnboardingScreen.seen();
  final router = buildRouter(
      initialLocation: seenOnboarding ? '/' : '/onboarding');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: InnawoodsApp(router: router),
    ),
  );
}

class InnawoodsApp extends ConsumerWidget {
  const InnawoodsApp({super.key, required this.router});
  final GoRouter router;

  // Red-only color matrix — keeps the red channel (slightly damped), zeros
  // green + blue. Preserves dark-adapted vision while keeping the UI legible.
  static const _nightFilter = ColorFilter.matrix(<double>[
    0.45, 0, 0, 0, 0,
    0,    0, 0, 0, 0,
    0,    0, 0, 0, 0,
    0,    0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(settingsControllerProvider).valueOrNull?.nightMode
        ?? false;
    return MaterialApp.router(
      title: 'innawoods',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return night ? ColorFiltered(colorFilter: _nightFilter, child: child) : child;
      },
    );
  }
}
