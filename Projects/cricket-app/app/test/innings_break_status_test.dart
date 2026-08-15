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
  int resumes = 0;

  /// The SERVER's matches.status. The console now gates the resume on this
  /// rather than on a field of its own State, so the fake has to move like the
  /// real thing: a successful markInningsBreak really does change it. Pinning
  /// it to 'live' forever, as this fixture used to, modelled a server that
  /// ignores the write - and hid the bug where a scorer who reopened the
  /// console (fresh State, latch down) could never get the match back to live.
  String status = 'live';

  @override
  Future<void> markInningsBreak(String matchId) async {
    attempts++;
    if (failTimes > 0) {
      failTimes--;
      throw Exception('no connection');
    }
    status = 'innings_break';
  }

  /// How many resume attempts should fail before one succeeds.
  int failResumes = 0;
  int resumeAttempts = 0;

  @override
  Future<void> resumeFromInningsBreak(String matchId) async {
    resumeAttempts++;
    if (failResumes > 0) {
      failResumes--;
      throw Exception('no connection');
    }
    resumes++;
    status = 'live';
  }
}

/// `innings_status` is what the fold reports on each successive read, so a test
/// can say "ended, then reopened" - which is what a ball-log correction does.
class _StatusN extends Notifier<String> {
  @override
  String build() => 'completed';
  void set(String v) => state = v;
}

final _statusSrc = NotifierProvider<_StatusN, String>(_StatusN.new);

/// Lets the fold advance (the next ball) WITHOUT innings_status changing, which
/// is what actually happens after a correction reopens an innings: the scorer
/// carries on scoring. Without this a test can only re-notify by passing back
/// through 'completed', and that re-renders the innings-break panel, which
/// re-arms the latch and hides the defect.
class _SeqN extends Notifier<int> {
  @override
  int build() => 120;
  void next() => state = state + 1;
}

final _seqSrc = NotifierProvider<_SeqN, int>(_SeqN.new);

/// First innings complete, no target set - the innings-break panel.
///
/// Returns the CONTAINER rather than a list of overrides: riverpod 3's
/// `Override` type is not nameable from a test file, so the list cannot be
/// hoisted into a helper's return type.
ProviderContainer _container(_BreakRepo repo) => ProviderContainer(overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        matchProvider.overrideWith(
            (ref, id) async => {'balls_per_over': 6, 'status': repo.status}),
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
              'innings_status': ref.watch(_statusSrc),
              'last_seq': ref.watch(_seqSrc),
            }),
      ]);

Widget _console(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    // ── code review 2026-08-05 ───────────────────────────────────────────────
    // The review said the per-widget `_breakMarked` latch means a correction
    // made after REOPENING the console cannot resume. That half is REFUTED:
    // remounting re-renders the innings-break panel, which re-arms the latch,
    // so the fresh-mount path self-heals. A test for it passed against the old
    // code too - which is how I found out.
    //
    // The other half is real. `_breakMarked = false` was set BEFORE awaiting
    // the RPC, so a FAILED resume left nothing to re-trigger on and the comment
    // promising "the next correction or reopen will retry" could not happen.
    // Gating on the server's matches.status fixes it for free: the status is
    // still innings_break after a failure, so the next fold event tries again.
    testWidgets('a resume that FAILS is retried on the next fold event on '
        '\$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _BreakRepo(failTimes: 0)..failResumes = 1;
        final c = _container(repo);
        addTearDown(c.dispose);

        await tester.pumpWidget(_console(c));
        await tester.pumpAndSettle();
        expect(repo.status, 'innings_break', reason: 'sanity: break written');

        // the correction reopens the innings - and the resume RPC fails
        c.read(_statusSrc.notifier).set('in_progress');
        await tester.pumpAndSettle();
        expect(repo.resumeAttempts, 1, reason: 'sanity: it tried once');
        expect(repo.status, 'innings_break',
            reason: 'sanity: the server did not move, so viewers still read '
                'the match as being at the innings break');

        // The scorer simply carries on: the next ball advances the fold while
        // innings_status STAYS in_progress. Nothing returns to the break panel,
        // so nothing re-arms the latch - this is the real shape of the failure.
        c.read(_seqSrc.notifier).next();
        await tester.pumpAndSettle();

        expect(repo.resumeAttempts, greaterThan(1),
            reason: 'the old code cleared the latch BEFORE awaiting, so one '
                'failed resume meant the match stayed at innings_break for the '
                'rest of the innings with nothing able to try again - and the '
                'scorer was never told, because this path has no error UI');
        expect(repo.status, 'live');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a correction that reopens the innings puts the match back to '
        'live on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _BreakRepo(failTimes: 0);
        final container = _container(repo);
        addTearDown(container.dispose);
        await tester.pumpWidget(_console(container));
        await tester.pumpAndSettle();
        expect(repo.attempts, 1, reason: 'the break was written');
        expect(repo.resumes, 0);

        // the scorer deletes the wrong final wicket from the ball log
        container.read(_statusSrc.notifier).set('in_progress');
        await tester.pumpAndSettle();

        expect(repo.resumes, 1,
            reason: 'the innings is open again and balls are being recorded, '
                'so the viewer, the Watch-live list and the Matches tile must '
                'stop saying "innings break"');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a failed break write is shown, not swallowed on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _BreakRepo(failTimes: 99);
        final container = _container(repo);
        addTearDown(container.dispose);
        await tester.pumpWidget(_console(container));
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
        final container = _container(repo);
        addTearDown(container.dispose);
        await tester.pumpWidget(_console(container));
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
        final container = _container(repo);
        addTearDown(container.dispose);
        await tester.pumpWidget(_console(container));
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
