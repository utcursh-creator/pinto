import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/location_screen.dart';
import '../../features/discover/presentation/my_posts_screen.dart';
import '../../features/discover/presentation/new_post_composer.dart';
import '../../features/discover/presentation/post_detail_screen.dart';
import '../../features/matches/presentation/matches_screen.dart';
import '../../features/messages/presentation/dm_inbox_screen.dart';
import '../../features/messages/presentation/dm_thread_screen.dart';
import '../../features/scoring/presentation/match_squads_screen.dart';
import '../../features/scoring/presentation/match_viewer_screen.dart';
import '../../features/scoring/presentation/scoring_console_screen.dart';
import '../../features/scoring/presentation/start_match_screen.dart';
import '../../features/scoring/presentation/toss_openers_screen.dart';
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
                routes: [
                  GoRoute(
                    path: 'compose',
                    builder: (context, state) => const NewPostComposer(),
                  ),
                  GoRoute(
                    path: 'my-posts',
                    builder: (context, state) => const MyPostsScreen(),
                  ),
                  GoRoute(
                    path: 'location',
                    builder: (context, state) => const LocationScreen(),
                  ),
                  GoRoute(
                    path: 'post/:postId',
                    builder: (context, state) => PostDetailScreen(
                      postId: state.pathParameters['postId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'messages',
                    builder: (context, state) => const DmInboxScreen(),
                    routes: [
                      GoRoute(
                        path: ':threadId',
                        builder: (context, state) => DmThreadScreen(
                          threadId: state.pathParameters['threadId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: matchesKey,
            routes: [
              GoRoute(
                path: Routes.matches,
                builder: (context, state) => const MatchesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const StartMatchScreen(),
                  ),
                  GoRoute(
                    path: ':matchId/squads',
                    builder: (context, state) => MatchSquadsScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':matchId/toss',
                    builder: (context, state) => TossOpenersScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':matchId/score',
                    builder: (context, state) => ScoringConsoleScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':matchId/view',
                    builder: (context, state) => MatchViewerScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                ],
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
