import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/toss_openers_screen.dart';

/// Review #3: nothing invalidates myMatchesProvider when a match goes
/// setup -> live, so the scorer's own Matches tab keeps showing a live game as
/// "Setup - not started".
///
/// That is not cosmetic - it is the doorway to the other finding in this screen.
/// The stale tile sits under "Upcoming", its overflow offers "Resume setup"
/// instead of "Continue scoring", and tapping it opens the SQUAD EDITOR for a
/// match that is four overs old. From there the scorer walks onto a blank toss
/// form and re-tosses a live match. The backend now refuses that
/// (`the toss cannot be changed once play has started`, pgTAP 148); this is the
/// half that stops the scorer being led there in the first place.
///
/// myMatchesProvider is not autoDispose, and MatchesScreen stays mounted
/// underneath the pushed setup pages, so the row it cached at creation time -
/// status 'setup' - is what it keeps until something says otherwise.
const _matchId = 'm1';
const _teamA = 'ta';
const _teamB = 'tb';

class _Repo extends Fake implements MatchRepository {
  int startCalls = 0;

  @override
  Future<void> setToss({
    required String matchId,
    required String winnerTeamId,
    required String decision,
  }) async {}

  @override
  Future<String> startInnings({
    required String matchId,
    required int inningsNumber,
    required String battingTeam,
    required String bowlingTeam,
    required String openingStriker,
    required String openingNonStriker,
    int? target,
  }) async {
    startCalls++;
    return 'in1';
  }
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('starting a match refreshes the Matches list on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        var listReads = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            matchRepositoryProvider.overrideWithValue(repo),
            matchProvider(_matchId).overrideWith((ref) async => {
                  'id': _matchId,
                  'team_a_id': _teamA,
                  'team_b_id': _teamB,
                  'status': 'setup',
                }),
            matchTeamNamesProvider(_matchId).overrideWith(
                (ref) async => {_teamA: 'Bat XI', _teamB: 'Bowl XI'}),
            matchSquadProvider(_matchId).overrideWith((ref) async => [
                  {
                    'team_id': _teamA, 'team_member_id': 'a1',
                    'batting_order': 1,
                    'team_members': {'guest_name': 'Bat1', 'profiles': null},
                  },
                  {
                    'team_id': _teamA, 'team_member_id': 'a2',
                    'batting_order': 2,
                    'team_members': {'guest_name': 'Bat2', 'profiles': null},
                  },
                  {
                    'team_id': _teamB, 'team_member_id': 'b1',
                    'batting_order': 1,
                    'team_members': {'guest_name': 'Bowl1', 'profiles': null},
                  },
                  // TWO on the bowling side: the screen refuses to start with
                  // fewer, and a one-man fixture makes the test fail at its own
                  // sanity check rather than at the thing it is testing.
                  {
                    'team_id': _teamB, 'team_member_id': 'b2',
                    'batting_order': 2,
                    'team_members': {'guest_name': 'Bowl2', 'profiles': null},
                  },
                ]),
            // the Matches tab underneath, which is what holds the stale row
            myMatchesProvider.overrideWith((ref) async {
              listReads++;
              return const <Map<String, dynamic>>[];
            }),
          ],
          child: MaterialApp(
            home: Stack(children: [
              Consumer(builder: (_, ref, _) {
                ref.watch(myMatchesProvider);
                return const SizedBox.shrink();
              }),
              const TossOpenersScreen(matchId: _matchId),
            ]),
          ),
        ));
        await tester.pumpAndSettle();
        final before = listReads;
        expect(before, 1, reason: 'sanity: the list has been read once');

        // toss, openers, start
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bat XI'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bat'));
        await tester.pumpAndSettle();
        // the opening-pair dropdowns only render once the toss is decided
        final dd = find.byType(DropdownButton<String>);
        expect(dd.evaluate().length, 2, reason: 'sanity: the pair pickers');
        await tester.tap(dd.at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bat1').last);
        await tester.pumpAndSettle();
        await tester.tap(dd.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bat2').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Start match'));
        await tester.pumpAndSettle();

        expect(repo.startCalls, 1, reason: 'sanity: the innings started');
        expect(listReads, greaterThan(before),
            reason: 'the match is live now. Without this the scorer\'s own '
                'Matches tile still says "Setup - not started", offers "Resume '
                'setup", and walks them back into the squad editor and a blank '
                'toss form for a game already in progress');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
