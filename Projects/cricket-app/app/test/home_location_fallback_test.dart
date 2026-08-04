import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), finding 70: a FAILED home-location read
/// is indistinguishable from "no home ground set", so Discover silently pins
/// itself to a fallback city for the session.
///
/// `homeLocationProvider.value` is null both when the home ground is unset and
/// when the RPC failed, and `effectiveAnchor` then quietly returns
/// kFallbackAnchor (Mumbai). A user in Delhi with no connectivity at cold start
/// gets Mumbai games with nothing said. The feed's Retry invalidated only the
/// FEED, so the wrong anchor survived the retry, and nothing recovered it short
/// of reopening Location and re-saving by hand.
///
/// The half that is not cosmetic: composing a post uses the same anchor, so the
/// ad is PUBLISHED geotagged to a city the author may be a thousand kilometres
/// from - where nobody near them will ever see it, permanently.
///
/// Three separate properties, so three assertions. File guards: `.value` on an
/// AsyncValue is exactly the kind of thing that reappears in a refactor.
String _code(String path) => File(path)
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  const composer =
      'lib/src/features/discover/presentation/new_post_composer.dart';
  const discover =
      'lib/src/features/discover/presentation/discover_screen.dart';

  test('a post is never geotagged from a home read that failed', () {
    final src = _code(composer);
    expect(src, contains('hasError'),
        reason: 'the composer distinguishes "no home ground" from "we could '
            'not read it" - collapsing them publishes an ad pinned to the '
            'wrong city, and that is permanent');
    final guard = src.indexOf('hasError');
    final create = src.indexOf('createPost(');
    expect(create, isNot(-1), reason: 'anchor lost');
    expect(guard, lessThan(create),
        reason: 'the check has to happen BEFORE the post is written');
  });

  test('retrying the feed also re-reads the home ground', () {
    final src = _code(discover);
    final at = src.indexOf('onRetry:');
    expect(at, isNot(-1), reason: 'anchor lost');
    final block = src.substring(at, at + 400);
    expect(block, contains('invalidate(homeLocationProvider)'),
        reason: 'the home read is what failed first - retrying only the feed '
            'keeps the wrong anchor for the rest of the session');
  });

  test('and the feed says when it is guessing', () {
    final src = _code(discover);
    expect(src, contains('hasError'),
        reason: 'error and unset must be told apart to know we are guessing');
    expect(src, contains('could not read your home ground'),
        reason: 'the user is being shown another city\'s games and was told '
            'nothing at all');
  });
}
