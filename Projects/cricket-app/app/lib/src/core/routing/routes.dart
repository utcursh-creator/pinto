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
  static const String createTeam = '/profile/teams/create';
  static String teamPage(String teamId) => '/profile/teams/$teamId';
}
