import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/routing/pasted_token.dart';

/// Whole-system review #2 (2026-07-28), finding 46: a pasted tournament join
/// code is not sanitised the way a team invite code is, so a perfectly valid
/// invite is reported as already used.
///
/// The organizer shares a two-sentence message with a newline in it. The old
/// tournament parser did `code.split('/join-tournament/').last.trim()`, which
/// keeps the newline AND the second sentence, so the token became
/// `"<token>\nOr enter this code in the app: <token>"`. That still travels as one
/// URI segment, so the screen loads, the RPC fails, and the recipient is told
/// the invite has already been used.
///
/// The other failure is quieter: a link with a trailing slash leaves an empty
/// tail, and the guard checked the RAW INPUT rather than the derived token, so
/// an empty token was pushed - and go_router normalises '/join-tournament/' to
/// '/join-tournament', which matches no route at all.
///
/// The team-invite flow always handled both. There were two parsers and only
/// one was right, so there is now one.
void main() {
  // The exact string manage_tournament_screen builds.
  const token = 'abc123XYZ';
  const shared =
      'Add your team to my cricket tournament on Pitch: '
      'https://pitch.app/join-tournament/$token\n'
      'Or enter this code in the app: $token';

  group('tournament join codes', () {
    const marker = '/join-tournament/';

    test('the whole shared message yields just the token', () {
      expect(pastedToken(shared, marker: marker), token,
          reason: 'this is what people actually paste - the newline and the '
              'second sentence used to travel with the token and the invite '
              'was reported as already used');
    });

    test('a bare code is left alone', () {
      expect(pastedToken(token, marker: marker), token);
    });

    test('a trailing slash yields empty, so callers can refuse it', () {
      expect(pastedToken('https://pitch.app/join-tournament/', marker: marker),
          '',
          reason: 'pushing this navigates to a route that does not exist');
    });

    test('a chat client\'s query or fragment is dropped', () {
      expect(
          pastedToken('https://pitch.app/join-tournament/$token?utm=whatsapp',
              marker: marker),
          token);
      expect(
          pastedToken('  https://pitch.app/join-tournament/$token#x  ',
              marker: marker),
          token);
    });
  });

  group('team invite codes keep working', () {
    // CONTROL: the team flow was the one that was RIGHT. Sharing the parser
    // must not regress it.
    const marker = '/invite/';
    test('bare, link, query, fragment and blank all behave', () {
      expect(pastedToken('abc123', marker: marker), 'abc123');
      expect(pastedToken('https://pitch.app/invite/abc123', marker: marker),
          'abc123');
      expect(
          pastedToken('https://pitch.app/invite/abc123?utm=whatsapp',
              marker: marker),
          'abc123');
      expect(pastedToken('  https://pitch.app/invite/abc123#x  ', marker: marker),
          'abc123');
      expect(pastedToken('   ', marker: marker), '');
    });
  });

  test('the tournament flow re-checks the DERIVED token before navigating', () {
    // The parser returning '' is only half the fix; the caller has to act on
    // it. Checking the raw input for emptiness is a different test and passes
    // on the trailing-slash paste.
    final src = File('lib/src/features/tournaments/presentation/'
            'tournaments_list_screen.dart')
        .readAsStringSync();
    final derived = src.indexOf('final token = pastedToken(');
    expect(derived, isNot(-1), reason: 'the shared parser is not being used');
    final push = src.indexOf('Routes.joinTournament(token)');
    expect(push, greaterThan(derived));
    expect(src.substring(derived, push), contains('token.isEmpty'),
        reason: 'an empty derived token must stop the navigation, or the user '
            'lands on a route that matches nothing');
  });
}
