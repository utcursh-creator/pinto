import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 77: the innings-break status
/// write is swallowed and latched off, so viewers keep seeing "Live now".
///
/// `_breakMarked = true` was set BEFORE the await and the call ended in
/// `.catchError((_) {})` with an empty body. That write is the ONLY thing
/// keeping the public status honest - the viewer, the Watch-live list and the
/// Matches list all read matches.status - and the failure it swallows is a
/// connection blip, which is most likely at exactly this moment, when the
/// phones come out at the interval.
///
/// One blip and every viewer read "Live now" for the whole break while the
/// console privately showed "Innings break". The scorer was never told, and the
/// latch meant it was never retried for the life of the widget.
class _BreakRepo extends Fake implements MatchRepository {
  _BreakRepo({required this.failTimes});
  int failTimes;
  int attempts = 0;

  @override
  Future<void> markInningsBreak(String matchId) async {
    attempts++;
    if (failTimes > 0) {
      failTimes--;
      throw Exception('no connection');
    }
  }
}

/// First innings complete, no target set - the innings-break panel.
Widget _console(_BreakRepo repo) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        matchProvider.overrideWith(
            (ref, id) async => {'balls_per_over': 6, 'status': 'live'}),
        currentInningsProvider.overrideWith((ref, id) async => {
              'id': 'in1',
              'batting_team_id': 'A',
              'bowling_team_id': 'B',
              'target': null,
            }),
        matchSquadProvider.overrideWith((ref, id) async => [
              {
                'team_id': 'A', 'team_member_id': 's1',
                'team_members': {'guest_name': 'Rahul', 'profiles': null},
              },
              {
                'team_id': 'B', 'team_member_id': 'b1',
                'team_members': {'guest_name': 'Bumrah', 'profiles': null},
              },
            ]),
        bowlerOverCapProvider.overrideWith((ref, id) async => null),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 142,
              'wickets': 10,
              'wickets_remaining': 0,
              'legal_balls': 120,
              'over': '20.0',
              'innings_status': 'completed',
              'last_seq': 120,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a failed break write is shown, not swallowed on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _BreakRepo(failTimes: 99);
        await tester.pumpWidget(_console(repo));
        await tester.pumpAndSettle();

        expect(find.text('Innings break'), findsOneWidget,
            reason: 'sanity: this is the break panel');
        expect(repo.attempts, greaterThan(0), reason: 'the write was tried');
        expect(find.textContaining('still sees this match as live'),
            findsOneWidget,
            reason: 'the scorer must learn that viewers were not told - this '
                'was an empty catchError, so nothing was said at all');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and can be retried on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // fails once, then the connection comes back
        final repo = _BreakRepo(failTimes: 1);
        await tester.pumpWidget(_console(repo));
        await tester.pumpAndSettle();
        expect(repo.attempts, 1);
        expect(find.textContaining('still sees this match as live'),
            findsOneWidget);

        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(repo.attempts, 2,
            reason: 'the latch was set BEFORE the await and never reset, so '
                'the write was never attempted again for the life of the '
                'widget');
        expect(find.textContaining('still sees this match as live'),
            findsNothing,
            reason: 'and the warning clears once viewers have been told');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a successful write says nothing and fires once '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _BreakRepo(failTimes: 0);
        await tester.pumpWidget(_console(repo));
        await tester.pumpAndSettle();

        expect(find.textContaining('still sees this match as live'),
            findsNothing);
        expect(repo.attempts, 1,
            reason: 'the latch still does its job - un-latching on failure '
                'must not turn into an RPC on every rebuild');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
