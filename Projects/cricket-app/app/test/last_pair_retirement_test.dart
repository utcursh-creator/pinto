import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 85 - the client half.
///
/// The Retire button was `onPressed: incoming == null ? null : ...`. At the last
/// wicket there is nobody left to pick, so the dropdown is empty, `incoming`
/// stays null and the button is dead. A genuine last-pair retirement could not
/// be recorded at all - the scorer's only options were to leave the match
/// wrong or to invent a dismissal that never happened.
///
/// The server rule (pgTAP 135) is: somebody must come in UNLESS this retirement
/// is itself the last wicket, and only a RETIRED OUT can be a wicket. This
/// mirrors it, so the two cannot drift.
class _SpyRepo extends Fake implements MatchRepository {
  bool called = false;
  bool? sawOut;
  String? sawIncoming;

  @override
  Future<void> retireBatter({
    required String inningsId,
    required String batterId,
    required bool out,
    String? incomingBatterId,
  }) async {
    called = true;
    sawOut = out;
    sawIncoming = incomingBatterId;
  }
}

/// `wickets_remaining: 1` and every other batter already dismissed, so the
/// incoming dropdown is genuinely empty - the real last-pair situation.
Widget _console(_SpyRepo spy) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(spy),
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
                'team_id': 'A', 'team_member_id': 's2',
                'team_members': {'guest_name': 'Arjun', 'profiles': null},
              },
              {
                'team_id': 'B', 'team_member_id': 'b1',
                'team_members': {'guest_name': 'Bumrah', 'profiles': null},
              },
            ]),
        bowlerOverCapProvider.overrideWith((ref, id) async => null),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 95,
              'wickets': 9,
              'wickets_remaining': 1,
              'legal_balls': 60,
              'over': '10.0',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 60,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

Future<void> _openRetire(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Retire'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a last-pair retired OUT can be recorded on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await _openRetire(tester);

        await tester.tap(find.widgetWithText(SwitchListTile, 'Retired out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
        await tester.pumpAndSettle();

        expect(spy.called, isTrue,
            reason: 'with nobody left to bat the button was dead, so a real '
                'last-pair retirement could not be recorded at all');
        expect(spy.sawOut, isTrue);
        expect(spy.sawIncoming, isNull,
            reason: 'there is nobody to send in - the retirement is the wicket');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a last-pair retired HURT is still refused '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // The server rejects this (pgTAP 135): a retired-hurt counts no wicket,
        // so nothing would end the innings and the retired batter would keep
        // facing. The client must not offer it either, or the scorer meets a
        // raw refusal instead of an explanation.
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await _openRetire(tester);

        // "Retired out" left OFF
        final btn = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Retire'));
        expect(btn.onPressed, isNull,
            reason: 'a hurt batter who cannot be replaced ends the innings, '
                'which is a retired OUT - the sheet says so rather than '
                'letting the scorer hit a server error');
        expect(find.textContaining('Nobody left to bat'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
