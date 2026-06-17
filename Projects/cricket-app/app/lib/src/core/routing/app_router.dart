import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/matches/presentation/matches_screen.dart';
import '../../features/onboarding/presentation/create_profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shell/presentation/adaptive_tab_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/teams/presentation/create_team_screen.dart';
import '../../features/teams/presentation/my_teams_screen.dart';
import '../../features/teams/presentation/team_page_screen.dart';
import '../auth/auth_gate.dart';
import 'router_refresh.dart';
import 'routes.dart';

/// The app router. The redirect implements the onboarding gate off a single
/// [AuthGate] value: loading holds on splash, anonymous lands on the (viewable)
/// shell, a real user with no profile is sent to create-profile, an onboarded
/// user goes to the shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  final discoverKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
  final matchesKey = GlobalKey<NavigatorState>(debugLabel: 'matches');
  final profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final gate = ref.read(authGateProvider);
      final loc = state.matchedLocation;

      switch (gate) {
        case AuthGate.loading:
          return loc == Routes.splash ? null : Routes.splash;
        case AuthGate.anonymous:
          return loc == Routes.splash ? Routes.discover : null;
        case AuthGate.needsProfile:
          return loc == Routes.createProfile ? null : Routes.createProfile;
        case AuthGate.ready:
          if (loc == Routes.splash ||
              loc == Routes.signIn ||
              loc == Routes.createProfile) {
            return Routes.discover;
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.createProfile,
        builder: (context, state) => const CreateProfileScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveTabShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: discoverKey,
            routes: [
              GoRoute(
                path: Routes.discover,
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: matchesKey,
            routes: [
              GoRoute(
                path: Routes.matches,
                builder: (context, state) => const MatchesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: profileKey,
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'teams',
                    builder: (context, state) => const MyTeamsScreen(),
                    routes: [
                      GoRoute(
                        path: 'create',
                        builder: (context, state) => const CreateTeamScreen(),
                      ),
                      GoRoute(
                        path: ':teamId',
                        builder: (context, state) => TeamPageScreen(
                          teamId: state.pathParameters['teamId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
