import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_squads_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 53: a squad bigger than eleven
/// silently changes the FORMAT of the match, and nothing said so.
///
/// all_out is squad_size - 1 (_innings_fold_params), and squad_size comes from
/// the declared match squad with no upper bound anywhere - the screen only
/// checked `a < 2 || b < 2`. Tick a 13-man roster and the innings does not
/// close at ten wickets: a 12th and a 13th batter come in, and "won by N
/// wickets" is computed off 12 rather than 10. That sentence is persisted into
/// matches.result.note and is what the public viewer, the share card and match
/// history show forever.
///
/// Club rosters are routinely bigger than the XI, so ticking everyone available
/// is a natural mistake.
///
/// NOT a hard cap. Twelve- and thirteen-a-side social games are real and the
/// backend supports them deliberately - squad_size lives in matches.rules and
/// pgTAP 76/77 rely on it. The fix is that choosing a non-standard format has
/// to be a DECISION rather than an accident, so the consequence is stated in
/// the terms a scorer cares about: how many wickets is all out.
List<Map<String, dynamic>> _members(String prefix, int n) => [
      for (var i = 1; i <= n; i++)
        {'id': '$prefix$i', 'guest_name': '$prefix Player $i', 'profiles': null},
    ];

Widget _squads({required int teamASize, required int teamBSize}) =>
    ProviderScope(
      overrides: [
        matchProvider.overrideWith(
            (ref, id) async => {'id': 'm1', 'team_a_id': 'A', 'team_b_id': 'B'}),
        matchTeamNamesProvider
            .overrideWith((ref, id) async => {'A': 'Mumbai', 'B': 'Chennai'}),
        teamMembersProvider.overrideWith((ref, teamId) async =>
            teamId == 'A' ? _members('a', teamASize) : _members('b', teamBSize)),
        matchSquadProvider.overrideWith((ref, id) async => []),
      ],
      child: const MaterialApp(home: MatchSquadsScreen(matchId: 'm1')),
    );

/// Ticks the first [n] players of a side.
Future<void> _tick(WidgetTester tester, String prefix, int n) async {
  for (var i = 1; i <= n; i++) {
    final row = find.text('$prefix Player $i');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a 13-man squad says the match is 13-a-side on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_squads(teamASize: 13, teamBSize: 13));
        await tester.pumpAndSettle();
        await _tick(tester, 'a', 13);

        expect(find.textContaining('13 players a side'), findsOneWidget,
            reason: 'ticking a whole roster silently makes this a 13-a-side '
                'match; the scorer has to be told');
        expect(find.textContaining('all out at 12 wickets'), findsOneWidget,
            reason: 'and told in the terms that decide the result - the '
                'winning margin is computed off that number and is written '
                'into the match record permanently');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: an ordinary XI says nothing on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // Eleven is the normal case and must stay silent, or the warning is
        // noise that gets ignored on the one occasion it matters.
        await tester.pumpWidget(_squads(teamASize: 13, teamBSize: 13));
        await tester.pumpAndSettle();
        await _tick(tester, 'a', 11);

        expect(find.textContaining('players a side'), findsNothing);
        expect(find.textContaining('all out at'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
