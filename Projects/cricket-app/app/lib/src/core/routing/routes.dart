/// Route path constants for the foundation shell + gates.
class Routes {
  const Routes._();

  static const String splash = '/splash';
  static const String signIn = '/sign-in';
  static const String createProfile = '/onboarding/create-profile';
  static const String discover = '/discover';
  static const String matches = '/matches';
  static const String profile = '/profile';

  // Identity (slice 2) - nested under the Profile branch.
  static const String editProfile = '/profile/edit';
  static const String myTeams = '/profile/teams';
  static const String claimInbox = '/profile/claims';
  static const String createTeam = '/profile/teams/create';
  static String teamPage(String teamId) => '/profile/teams/$teamId';

  // Discover / Matchmaking (slice 3) - nested under the Discover branch.
  static const String compose = '/discover/compose';
  static const String myPosts = '/discover/my-posts';
  static const String search = '/discover/search';
  static const String location = '/discover/location';
  static const String messages = '/discover/messages';
  static const String notifications = '/discover/notifications';
  static String postDetail(String postId) => '/discover/post/$postId';
  static String dmThread(String threadId) => '/discover/messages/$threadId';

  // Scoring (slice 4) - nested under the Matches branch.
  static const String startMatch = '/matches/new';
  // Pre-seed the wizard with an opponent (+ overs, and the poster to notify)
  // from a discover post (MTCH-7).
  static String proposeMatch(String opponentTeamId, {int? overs, String? authorId}) {
    final params = <String>['opponent=$opponentTeamId'];
    if (overs != null) params.add('overs=$overs');
    if (authorId != null) params.add('author=$authorId');
    return '/matches/new?${params.join('&')}';
  }
  static String matchSquads(String matchId) => '/matches/$matchId/squads';
  static const String liveMatches = '/matches/live';
  static String matchToss(String matchId) => '/matches/$matchId/toss';
  static String scoreMatch(String matchId) => '/matches/$matchId/score';
  // Corrections: the ball-by-ball log for edit/insert/delete.
  static String ballLog(String matchId) => '/matches/$matchId/balls';

  // Tournaments (under the Matches branch + a public top-level page).
  static const String tournaments = '/matches/tournaments';
  static const String newTournament = '/matches/tournaments/new';
  static String manageTournament(String id) => '/matches/tournaments/$id/manage';
  // Public, login-free, shareable tournament page (top-level, like /watch).
  static String tournamentPage(String id) => '/tournament/$id';
  // Public, login-free, shareable live view. Top-level (NOT under the shell)
  // so it cold-starts correctly from a deep/share link, unlike a branch route.
  static String viewMatch(String matchId) => '/watch/$matchId';
  static String transferScorer(String matchId) => '/matches/$matchId/transfer';

  // Public, login-free, shareable player career stats (top-level, like /watch).
  static String playerStats(String profileId) => '/player/$profileId';

  // Team invite acceptance (opened from a shared invite link).
  static String acceptInvite(String token) => '/invite/$token';

  // Tournament join (opened from a shared tournament invite link / PIN). Public
  // top-level like /invite so it cold-starts + bypasses onboarding.
  static String joinTournament(String token) => '/join-tournament/$token';
}
