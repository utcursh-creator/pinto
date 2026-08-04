/// Pulls a token out of whatever somebody actually pasted.
///
/// People paste the whole shared message far more often than the bare code, and
/// the messages this app generates are two sentences with a newline between
/// them:
///
///   Add your team to my cricket tournament on Pitch:
///   `https://pitch.app/join-tournament/<token>`
///   `Or enter this code in the app: <token>`
///
/// So the tail after the marker is not the token - it is the token, a newline,
/// and another sentence containing the token again. Splitting on whitespace as
/// well as query/fragment characters is what makes the paste work.
///
/// Returns '' when there is nothing usable, which callers MUST re-check: a link
/// ending in a trailing slash yields an empty tail, and pushing an empty token
/// navigates to a route that does not exist (go_router normalises the trailing
/// slash away). Checking the RAW INPUT for emptiness is not the same test and
/// does not catch it (review #2, finding 46).
///
/// One implementation, used by both the team-invite and tournament flows. They
/// had two, and only one of them was right.
String pastedToken(String input, {required String marker}) {
  final t = input.trim();
  if (t.isEmpty) return '';
  final at = t.lastIndexOf(marker);
  final tail = at >= 0 ? t.substring(at + marker.length) : t;
  return tail.split(RegExp(r'[?#\s]')).first.trim();
}
