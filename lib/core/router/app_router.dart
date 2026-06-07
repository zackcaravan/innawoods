import 'package:go_router/go_router.dart';

import '../../features/map/screens/party_map3d_screen.dart';
import '../../features/maps/screens/maps_screen.dart';
import '../../features/mesh/screens/mesh_settings_screen.dart';
import '../../features/mesh/screens/mesh_setup_wizard.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/tracks/screens/tracks_screen.dart';
import '../../features/party/screens/chat_screen.dart';
import '../../features/party/screens/create_party_screen.dart';
import '../../features/party/screens/home_screen.dart';
import '../../features/party/screens/join_party_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// App routes. Deep-linking the `innawoods://join/...` scheme into `/join` is a
/// later-phase polish; for now the invite is pasted on the Join screen.
///
/// `initialLocation` is `/onboarding` on first launch (set in `main()` based
/// on a SharedPreferences flag), else `/`.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/settings/lora',
          builder: (context, state) => const MeshSettingsScreen(),
        ),
        GoRoute(
          path: '/settings/lora/setup',
          builder: (context, state) => const MeshSetupWizard(),
        ),
        GoRoute(
          path: '/maps',
          builder: (context, state) => const MapsScreen(),
        ),
        GoRoute(
          path: '/tracks',
          builder: (context, state) => const TracksScreen(),
        ),
        GoRoute(
          path: '/create',
          builder: (context, state) => const CreatePartyScreen(),
        ),
        GoRoute(
          path: '/join',
          builder: (context, state) =>
              JoinPartyScreen(initialLink: state.uri.queryParameters['link']),
        ),
        // The party map is now the MapLibre 3D vector map (replaced flutter_map).
        GoRoute(
          path: '/party/:id',
          builder: (context, state) =>
              PartyMap3dScreen(partyId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/party/:id/chat',
          builder: (context, state) =>
              ChatScreen(partyId: state.pathParameters['id']!),
        ),
      ],
    );

/// Kept for backward-compat with any imports that haven't switched to
/// `buildRouter`. Defaults to the home screen.
final appRouter = buildRouter();
