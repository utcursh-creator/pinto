import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), findings 82 / 75 / 71: three controls
/// that pointed nowhere.
///
///   82 - the toss screen's blocking error said "Tap Edit squads below to add
///        them" and there was no Edit squads control anywhere on that screen.
///        The scorer is stopped from starting the match and told to press
///        something that does not exist.
///   75 - GoRouter had no errorBuilder, so a stale or mistyped deep link landed
///        on go_router's built-in Page Not Found, whose Home button pushes '/'
///        - a route this app does not define. The one control on the error
///        screen did nothing.
///   71 - approving a guest claim invalidated the claim inbox but not the team
///        roster, so a team page still in the stack kept showing the guest row
///        with its "This is me" button.
///
/// File guards: each is a wiring fact with no runtime surface of its own, and
/// each reverts silently to the broken state if the code is refactored.
String _code(String path) => File(path)
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  test('82: the toss error only names controls that exist', () {
    const p = 'lib/src/features/scoring/presentation/toss_openers_screen.dart';
    final src = _code(p);
    // If the copy still tells the scorer to tap something, that thing has to
    // be on the screen.
    if (src.contains('Tap Edit squads')) {
      fail('the error still instructs the scorer to tap a control that has to '
          'exist - either drop the instruction or add the button');
    }
    expect(src, contains("Text('Edit squads')"),
        reason: 'the screen should offer the way out it is talking about, '
            'rather than leaving the scorer to find the back arrow');
    expect(src, contains('Routes.matchSquads('),
        reason: 'and that button must actually go to the squads screen');
  });

  test('75: the router has an errorBuilder that goes somewhere real', () {
    const p = 'lib/src/core/routing/app_router.dart';
    final src = _code(p);
    expect(src, contains('errorBuilder:'),
        reason: "without one, go_router's default Page Not Found offers a Home "
            "button that pushes '/', which this app does not define");

    final at = src.indexOf('errorBuilder:');
    final block = src.substring(at, at + 900);
    expect(block, contains('Routes.'),
        reason: 'the escape route must be a named route this app actually has, '
            'not a hardcoded path');
    expect(block, isNot(contains("context.go('/')")),
        reason: "'/' is the route that did not exist in the first place");
  });

  test('71: approving a claim refreshes the roster it just changed', () {
    const p = 'lib/src/features/teams/presentation/claim_inbox_screen.dart';
    final src = _code(p);
    final approve = src.indexOf('approveGuestClaim(');
    expect(approve, isNot(-1), reason: 'anchor lost');
    final after = src.substring(approve);
    expect(after, contains('invalidate(claimInboxProvider)'),
        reason: 'the inbox itself was always refreshed');
    expect(after, contains('invalidate(teamRosterProvider)'),
        reason: 'the approval rewrites the membership row, so a team page in '
            'the stack keeps offering "This is me" on a guest who has just '
            'been claimed');
  });
}
