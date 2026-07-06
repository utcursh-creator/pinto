import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/location_screen.dart';
import '../../features/discover/presentation/my_posts_screen.dart';
import '../../features/discover/presentation/new_post_composer.dart';
import '../../features/discover/presentation/post_detail_screen.dart';
import '../../features/discover/presentation/search_screen.dart';
import '../../features/matches/presentation/matches_screen.dart';
import '../../features/messages/presentation/dm_inbox_screen.dart';
import '../../features/messages/presentation/notifications_screen.dart';
import '../../features/messages/presentation/dm_thread_screen.dart';
import '../../features/scoring/presentation/ball_log_screen.dart';
import '../../features/scoring/presentation/live_matches_screen.dart';
import '../../features/scoring/presentation/match_squads_screen.dart';
import '../../features/scoring/presentation/match_viewer_screen.dart';
import '../../features/scoring/presentation/scoring_console_screen.dart';
import '../../features/scoring/presentation/start_match_screen.dart';
import '../../features/scoring/presentation/toss_openers_screen.dart';
import '../../features/scoring/presentation/transfer_scorer_screen.dart';
import '../../features/stats/presentation/player_stats_screen.dart';
import '../../features/onboarding/presentation/create_profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/shell/presentation/adaptive_tab_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/teams/presentation/claim_inbox_screen.dart';
import '../../features/teams/presentation/create_team_screen.dart';
import '../../features/teams/presentation/invite_accept_screen.dart';
import '../../features/teams/presentation/my_teams_screen.dart';
import '../../features/teams/presentation/team_page_screen.dart';
import '../../features/tournaments/presentation/create_tournament_screen.dart';
import '../../features/tournaments/presentation/join_tournament_screen.dart';
import '../../features/tournaments/presentation/manage_tournament_screen.dart';
import '../../features/tournaments/presentation/tournament_page_screen.dart';
import '../../features/tournaments/presentation/tournaments_list_screen.dart';
import '../auth/auth_gate.dart';
import 'router_refresh.dart';
import 'routes.dart';

/// Pure onboarding-gate redirect (extracted for testability). Returns the
/// location to redirect to, or null to stay.
///
/// `/watch/...` is a PUBLIC, login-free live view: it bypasses the gate entirely
/// so a shared/deep link resolves even before auth settles and even for a user
/// with no profile. This (plus being a top-level route) is the deep-link
/// cold-start fix - StatefulShellRoute branch routes do not cold-start reliably.
String? onboardingRedirect(AuthGate gate, String loc) {
  // Public, login-free deep links bypass the onboarding gate entirely. /invite
  // renders for anyone (the screen prompts anonymous users to sign in).
  if (loc.startsWith('/watch/') ||
      loc.startsWith('/player/') ||
      loc.startsWith('/invite/') ||
      loc.startsWith('/join-tournament/') ||
      loc.startsWith('/tournament/')) {
    return null;
  }
  switch (gate) {
    case AuthGate.loading:
    case AuthGate.error:
      // Both hold on splash: a spinner while loading, a retry when the profile
      // read failed (AUTH-4) - never misroute an onboarded user to create-profile.
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
}

/// The app router. The redirect implements the onboarding gate off a single
/// [AuthGate] value: loading holds on splash, anonymous lands on the (viewable)
/// shell, a real user with no profile is sent to create-profile, an onboarded
/// user goes to the shell. The public `/watch/:id` viewer sits outside the
/// shell so deep/share links cold-start correctly.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  final discoverKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
  final matchesKey = GlobalKey<NavigatorState>(debugLabel: 'matches');
  final profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        onboardingRedirect(ref.read(authGateProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      // Public, login-free, shareable live view - top-level so deep/share links
      // cold-start correctly (outside the StatefulShellRoute branches).
      GoRoute(
        path: '/watch/:matchId',
        builder: (context, state) => MatchViewerScreen(
          matchId: state.pathParameters['matchId']!,
        ),
      ),
      // Public, login-free, shareable player career stats - top-level so deep/
      // share links cold-start correctly (outside the StatefulShellRoute).
      // STAT-2: guests (unclaimed roster spots) get the same page keyed by
      // member id. Declared FIRST so '/player/guest/...' never matches ':profileId'.
      GoRoute(
        path: '/player/guest/:memberId',
        builder: (context, state) => PlayerStatsScreen(
          profileId: state.pathParameters['memberId']!,
          isGuest: true,
        ),
      ),
      GoRoute(
        path: '/player/:profileId',
        builder: (context, state) => PlayerStatsScreen(
          profileId: state.pathParameters['profileId']!,
        ),
      ),
      // Team invite acceptance from a shared link (top-level; the screen handles
      // the anonymous case by prompting sign-in).
      GoRoute(
        path: '/invite/:token',
        builder: (context, state) => InviteAcceptScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      // Tournament join from a shared invite link / PIN (top-level; a team admin
      // enters THEIR team = consent). SEC-8 CricHeroes-style self-registration.
      GoRoute(
        path: '/join-tournament/:token',
        builder: (context, state) => JoinTournamentScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      // Public, login-free, shareable tournament page (top-level, like /watch).
      GoRoute(
        path: '/tournament/:id',
        builder: (context, state) => TournamentPageScreen(
          tournamentId: state.pathParameters['id']!,
        ),
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
                    path: 'search',
                    builder: (context, state) => const SearchScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) => const NotificationsScreen(),
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
                    builder: (context, state) => StartMatchScreen(
                      initialOpponentId:
                          state.uri.queryParameters['opponent'],
                      initialOvers: state.uri.queryParameters['overs'],
                      initialVenue: state.uri.queryParameters['venue'],
                      initialMatchAt: state.uri.queryParameters['at'],
                      proposeToAuthorId: state.uri.queryParameters['author'],
                    ),
                  ),
                  GoRoute(
                    path: 'live',
                    builder: (context, state) => const LiveMatchesScreen(),
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
                    path: ':matchId/transfer',
                    builder: (context, state) => TransferScorerScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':matchId/balls',
                    builder: (context, state) => BallLogScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'tournaments',
                    builder: (context, state) => const TournamentsListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const CreateTournamentScreen(),
                      ),
                      GoRoute(
                        path: ':tid/manage',
                        builder: (context, state) => ManageTournamentScreen(
                          tournamentId: state.pathParameters['tid']!,
                        ),
                      ),
                    ],
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
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: 'claims',
                    builder: (context, state) => const ClaimInboxScreen(),
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
