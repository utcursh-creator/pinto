import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/prefs/scorer_prefs.dart';

/// Journey map C1 (ceiling). The wagon wheel used to be mandatory, which is
/// why a dot ball opened "Where did 0 run(s) go?" on the most common event in
/// cricket. Nobody ships placement capture that way - in CricHQ it is a setting
/// you turn on, with dot balls a further option inside it.
///
/// ABSENT MEANS OFF. Every one of these cases is a scorer who never asked for
/// the feature, and every one of them must get the plain, fast console.
void main() {
  test('a scorer who has never touched settings gets nothing switched on', () {
    final p = ScorerPrefs.fromProfile({'display_name': 'Rahul'});
    expect(p.wagonCapture, isFalse);
    expect(p.wagonDotBalls, isFalse,
        reason: 'a preference nobody asked for must not exist - guessing ON '
            'puts a modal in the scorer\'s face on the very next ball');
  });

  test('a null profile - signed out, or still loading - is also off', () {
    final p = ScorerPrefs.fromProfile(null);
    expect(p.wagonCapture, isFalse);
    expect(p.wagonDotBalls, isFalse,
        reason: 'never guess a preference ON while the profile is in flight; '
            'the cost of being wrong lands on the next delivery');
  });

  test('empty preferences read as off', () {
    final p = ScorerPrefs.fromProfile({'preferences': <String, dynamic>{}});
    expect(p.wagonCapture, isFalse);
  });

  test('the flags are read when actually set', () {
    final p = ScorerPrefs.fromProfile({
      'preferences': {'wagon_capture': true, 'wagon_dot_balls': true},
    });
    expect(p.wagonCapture, isTrue);
    expect(p.wagonDotBalls, isTrue);
  });

  test('dot-ball plotting is INDEPENDENT of capture in the data', () {
    // The console requires capture ON before it asks about anything at all, so
    // this combination is inert there - but the flags must not be conflated in
    // storage, or turning capture off would silently forget the dot choice.
    final p = ScorerPrefs.fromProfile({
      'preferences': {'wagon_capture': false, 'wagon_dot_balls': true},
    });
    expect(p.wagonCapture, isFalse);
    expect(p.wagonDotBalls, isTrue);
  });

  test('anything that is not exactly true is off', () {
    for (final junk in [null, 'true', 1, 'yes', <String, dynamic>{}]) {
      final p = ScorerPrefs.fromProfile({
        'preferences': {'wagon_capture': junk},
      });
      expect(p.wagonCapture, isFalse,
          reason: 'a stray value from an older client or a hand-edited row '
              'must not read as consent: $junk');
    }
  });
}
