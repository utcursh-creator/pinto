import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/discover/presentation/my_posts_screen.dart';

/// Review #3 (MEDIUM), finding 14: renewing an expired post to "today" silently
/// re-buries it AND removes the one control that told the author it was buried.
///
/// A captain posted "Need 2 players, Sat 09:00". The game passed; My posts
/// correctly said "Expired / Nobody can see this any more" with a Renew button.
/// At 16:00 they tap Renew for a game later today. The renew flow showed a
/// DATE-only picker and then rebuilt the instant from the OLD 09:00 - so
/// match_at became today 09:00, seven hours ago.
///
/// renew_post's server-side "give this post a new date" guard does not fire,
/// because it only triggers when _match_at is null and the client always sends
/// one. discover_posts floors on `match_at >= now() - interval '6 hours'`, so
/// the ad stayed invisible to everyone - while `expired` on My posts is computed
/// purely from expires_at, which was now tomorrow. The Expired chip, the
/// "Nobody can see this any more" line and the Renew button all vanished.
///
/// The author ended up WORSE than before renewing: the post was still dead and
/// the only thing that said so was gone until the next morning.
///
/// The composer has had exactly this rule all along (isPastFeedFloor), and says
/// in its own comment that it is top-level and pure "so the rule can be tested
/// without driving two platform date pickers". Same reasoning here: the
/// composition and the refusal are one pure function, and the screen has
/// nothing left to get wrong but calling it.
void main() {
  // Saturday 09:00 - the game that has been and gone.
  final previous = DateTime(2026, 7, 25, 9, 0);
  // The author is looking at their phone at 16:00 the following Saturday.
  final now = DateTime(2026, 8, 1, 16, 0);

  test('the picked TIME is used, not the old one', () {
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 1),
      time: const TimeOfDay(hour: 18, minute: 30),
      previous: previous,
      now: now,
    );
    expect(out, DateTime(2026, 8, 1, 18, 30),
        reason: 'the flow rebuilt the instant from the OLD match time, so '
            'renewing a 09:00 fixture to "today" at 16:00 produced 09:00 '
            'today - seven hours in the past, and invisible');
  });

  test('renewing to a time already past the feed floor is refused', () {
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 1),
      time: const TimeOfDay(hour: 9, minute: 0),
      previous: previous,
      now: now,
    );
    expect(out, isNull,
        reason: 'this is precisely what the old flow did silently. Null is the '
            'screen\'s cue to say so instead of writing a post nobody can see');
  });

  test('a time inside the floor is still allowed - a game that just started', () {
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 1),
      time: const TimeOfDay(hour: 12, minute: 0),
      previous: previous,
      now: now,
    );
    expect(out, DateTime(2026, 8, 1, 12, 0),
        reason: 'the feed shows a match up to 6 hours old, and people do post '
            'about a game already under way. The renew rule must match the '
            'feed exactly, not be more conservative than it');
  });

  test('a future date is fine whatever the time of day', () {
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 8),
      time: const TimeOfDay(hour: 7, minute: 0),
      previous: previous,
      now: now,
    );
    expect(out, DateTime(2026, 8, 8, 7, 0));
  });

  test('no time picked keeps the old time of day', () {
    // Cancelling the time picker must not be the same as choosing midnight -
    // that would silently move a 09:00 fixture to 00:00 and, for today, bury it.
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 8),
      time: null,
      previous: previous,
      now: now,
    );
    expect(out, DateTime(2026, 8, 8, 9, 0),
        reason: 'the old time of day is the best guess when the author skips '
            'the time picker - clubs play at the same hour every week');
  });

  test('no time picked, and the old hour would bury it today, is refused', () {
    final out = renewedMatchAt(
      date: DateTime(2026, 8, 1),
      time: null,
      previous: previous,
      now: now,
    );
    expect(out, isNull,
        reason: 'the exact case in the finding: keeping 09:00 for TODAY is the '
            'silent re-burial, and skipping the time picker must not sneak '
            'past the guard');
  });
}
