import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 13: the bowler picker enforces
/// the RAW rules cap instead of the effective one, so a short match with a small
/// bowling squad dead-ends and cannot be finished.
///
/// The app stamps rules.max_overs_per_bowler = ceil(overs/5) at match creation.
/// For a 10-over game that is 2. But the server deliberately enforces
///
///   greatest(rule, ceil(overs / bowling_squad_size))
///
/// (_bowler_over_cap, migration 20260707130700_bowler_cap_feasible.sql) so that
/// a side with fewer than five bowlers can still bowl the innings out. Measured
/// on exactly this fixture: raw rule 2, effective cap 4.
///
/// The picker read the raw rule straight off the match row, making the CLIENT
/// twice as strict as the server. With three bowlers in a 10-over match, after
/// six overs every row reads "At over limit" and is disabled, _bowlerId stays
/// null, the run pad stays behind its AbsorbPointer, and tapping it just
/// reopens the same all-disabled sheet. The match cannot be scored further -
/// the migration's own comment says the server fix exists to remove precisely
/// this dead end.
Widget _console({required int? effectiveCap}) => ProviderScope(
      overrides: [
        matchProvider.overrideWith((ref, id) async => {
              'balls_per_over': 6,
              'status': 'live',
              'overs_limit': 10,
              // what the app itself stamps for a 10-over match
              'rules': {'max_overs_per_bowler': 2},
            }),
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
                'team_id': 'A', 'team_member_id': 's2',
                'team_members': {'guest_name': 'Arjun', 'profiles': null},
              },
              for (final (id, name) in const [
                ('b1', 'Bumrah'), ('b2', 'Shami'), ('b3', 'Siraj'),
              ])
                {
                  'team_id': 'B', 'team_member_id': id,
                  'team_members': {'guest_name': name, 'profiles': null},
                },
            ]),
        bowlerOverCapProvider.overrideWith((ref, id) async => effectiveCap),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 48,
              'wickets': 2,
              'wickets_remaining': 8,
              // six overs gone: each of the three bowlers has bowled two
              'legal_balls': 36,
              'over': '6.0',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 36,
              'bowling': [
                for (final id in const ['b1', 'b2', 'b3'])
                  {
                    'bowler_id': id, 'legal_balls': 12, 'overs': '2.0',
                    'runs_conceded': 16, 'wickets': 0,
                  },
              ],
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the picker honours the effective cap, not the raw rule '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_console(effectiveCap: 4));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();

        expect(find.text('At over limit'), findsNothing,
            reason: 'each bowler has bowled 2 of an allowed 4 - the server '
                'would accept the next over, so the picker must offer it');
        expect(find.text('Max 4 overs each'), findsOneWidget,
            reason: 'and the sheet must quote the cap actually in force');

        // and the scorer can genuinely carry on
        await tester.tap(find.text('Bumrah'));
        await tester.pumpAndSettle();
        expect(find.text('Bowling: Bumrah'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a bowler at the effective cap is still blocked '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // Same fixture, but the cap really is 2. The quota is a Law of the
        // competition, not a suggestion - if the fix were "stop enforcing the
        // cap" a bowler could bowl the whole innings.
        await tester.pumpWidget(_console(effectiveCap: 2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();

        expect(find.text('At over limit'), findsNWidgets(3),
            reason: 'all three really have bowled their quota');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: no cap configured leaves everyone available '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_console(effectiveCap: null));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();

        expect(find.text('At over limit'), findsNothing);
        expect(find.textContaining('Max'), findsNothing,
            reason: 'a match with no quota must not claim one');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
