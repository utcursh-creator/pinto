import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_squads_screen.dart';

/// Whole-system review #2 (2026-07-28), findings 10 and 25 (both HIGH):
/// un-ticking a saved player is cosmetic, and a half-written squad cannot be
/// repaired.
///
/// The screen wrote the XI one `add_squad_member` at a time. That RPC is
/// additive and idempotent and nothing in the app ever deleted a match_squad
/// row, so a player dropped on a resumed setup stayed in the squad: he kept
/// appearing in the toss screen's opening pair, in the console's batter, bowler
/// and fielder pickers, and on the public scorecard. Once a ball was credited
/// to him, player_career_stats baked a permanent public career record for a man
/// who never played.
///
/// The loop was also N separate round-trips. A failure on the 8th of 12 left 7
/// rows committed under the message "Could not save the squads", which says the
/// opposite. THAT is the half no database test can pin - inside one transaction
/// Postgres rolls back for free - so it is pinned here: one call, not a loop.
const _matchId = 'm1';
const _teamA = 'ta';
const _teamB = 'tb';

Map<String, dynamic> _member(String id, String team, String name, int order) => {
      'team_id': team,
      'team_member_id': id,
      'batting_order': order,
      'is_captain': false,
      'is_wicket_keeper': false,
      'team_members': {'id': id, 'guest_name': name, 'profiles': null},
    };

class _Repo extends Fake implements MatchRepository {
  final List<List<Map<String, dynamic>>> saves = [];

  @override
  Future<void> setMatchSquad({
    required String matchId,
    required List<Map<String, dynamic>> members,
  }) async {
    saves.add(members);
  }

  // Anything else the screen reaches for throws (Fake.noSuchMethod), so a
  // second write path cannot creep back in unnoticed.
}

Widget _screen(_Repo repo) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        matchProvider(_matchId).overrideWith((ref) async =>
            {'id': _matchId, 'team_a_id': _teamA, 'team_b_id': _teamB}),
        matchTeamNamesProvider(_matchId)
            .overrideWith((ref) async => {_teamA: 'Bat XI', _teamB: 'Bowl XI'}),
        teamMembersProvider(_teamA).overrideWith((ref) async => [
              {'id': 'a1', 'guest_name': 'Bat1', 'profiles': null},
              {'id': 'a2', 'guest_name': 'Bat2', 'profiles': null},
              {'id': 'a3', 'guest_name': 'Bat3', 'profiles': null},
            ]),
        teamMembersProvider(_teamB).overrideWith((ref) async => [
              {'id': 'b1', 'guest_name': 'Bowl1', 'profiles': null},
              {'id': 'b2', 'guest_name': 'Bowl2', 'profiles': null},
            ]),
        // a squad saved on an earlier visit - this is "Resume setup"
        matchSquadProvider(_matchId).overrideWith((ref) async => [
              _member('a1', _teamA, 'Bat1', 1),
              _member('a2', _teamA, 'Bat2', 2),
              _member('b1', _teamB, 'Bowl1', 1),
              _member('b2', _teamB, 'Bowl2', 2),
            ]),
      ],
      child: const MaterialApp(home: MatchSquadsScreen(matchId: _matchId)),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a player dropped on a resumed setup is actually removed '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();
        expect(find.textContaining('Next: toss (4 picked)'), findsOneWidget,
            reason: 'sanity: the saved XI is prefilled');

        // Bat2 cannot make it; Bat3 comes in
        // a SELECTED player renders as "2.  Bat2" - his batting slot is part
        // of the tile title
        await tester.tap(find.textContaining('Bat2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bat3'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();

        expect(repo.saves.length, 1,
            reason: 'the squad is stated ONCE. Twelve separate round-trips is '
                'what let a failure on the 8th leave seven rows committed '
                'under an error saying nothing was saved');
        final ids = [
          for (final m in repo.saves.single) m['team_member_id'] as String,
        ];
        expect(ids, isNot(contains('a2')),
            reason: 'the dropped player must not be in the squad the server is '
                'told about - un-ticking him only ever changed a local Set, so '
                'he stayed in the opening-pair dropdown, the fielder picker '
                'and the public scorecard');
        expect(ids, contains('a3'), reason: 'his replacement is in');
        expect(ids.length, 4);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: the squad states both sides and its roles on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();

        final saved = repo.saves.single;
        // A "fix" that sent only the players of the side being edited would
        // wipe the other side, since anything absent is now deleted.
        expect(saved.where((m) => m['team_id'] == _teamA).length, 2);
        expect(saved.where((m) => m['team_id'] == _teamB).length, 2);
        for (final m in saved) {
          expect(m.containsKey('is_captain'), isTrue,
              reason: 'the captain and keeper flags travel with the squad, or '
                  'stating the whole squad silently clears them');
          expect(m.containsKey('is_keeper'), isTrue);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
