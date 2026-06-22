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
  static const String location = '/discover/location';
  static const String messages = '/discover/messages';
  static String postDetail(String postId) => '/discover/post/$postId';
  static String dmThread(String threadId) => '/discover/messages/$threadId';

  // Scoring (slice 4) - nested under the Matches branch.
  static const String startMatch = '/matches/new';
  // Slice 6: pre-seed the wizard with an opponent from a discover post.
  static String proposeMatch(String opponentTeamId) =>
      '/matches/new?opponent=$opponentTeamId';
  static String matchSquads(String matchId) => '/matches/$matchId/squads';
  static const String liveMatches = '/matches/live';
  static String matchToss(String matchId) => '/matches/$matchId/toss';
  static String scoreMatch(String matchId) => '/matches/$matchId/score';
  static String viewMatch(String matchId) => '/matches/$matchId/view';
  static String transferScorer(String matchId) => '/matches/$matchId/transfer';
}
