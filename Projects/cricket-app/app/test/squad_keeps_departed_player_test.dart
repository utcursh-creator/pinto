import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_squads_screen.dart';

/// Code review, 2026-08-05: resuming setup silently drops a player who has left
/// the team, and if he has already faced a ball the screen becomes impassable.
///
/// `_prefillFrom` skips any saved squad member who is no longer on the roster
/// (`if (!selectable.contains(memberId)) continue;`). That was harmless while
/// saving was additive. It is not harmless now: `set_match_squad` is
/// AUTHORITATIVE - it deletes every match_squad row not in the payload - so the
/// departed player is dropped from the squad on the next save.
///
/// And the RPC refuses to drop anybody who has played. Verified against the
/// live database: with a striker who faced one ball and then left the team,
/// omitting him raises `that player has already played in this match`
/// (set_match_squad line 55). So the captain reopens setup, taps Next, gets a
/// raw refusal, and there is no tile on screen to tick him back on with. The
/// only escape is to never touch the squads screen again.
///
/// A match squad is a HISTORICAL record of who played. Leaving the team
/// afterwards cannot un-pick you from a match that already happened.
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
}

/// 'a2' is in the SAVED SQUAD but NOT on the roster any more - he left the team
/// after the match started.
Widget _screen(_Repo repo) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        matchProvider(_matchId).overrideWith((ref) async =>
            {'id': _matchId, 'team_a_id': _teamA, 'team_b_id': _teamB, 'status': 'live'}),
        matchTeamNamesProvider(_matchId)
            .overrideWith((ref) async => {_teamA: 'Bat XI', _teamB: 'Bowl XI'}),
        teamMembersProvider(_teamA).overrideWith((ref) async => [
              {'id': 'a1', 'guest_name': 'Bat1', 'profiles': null},
              // a2 is GONE from the roster
              {'id': 'a3', 'guest_name': 'Bat3', 'profiles': null},
            ]),
        teamMembersProvider(_teamB).overrideWith((ref) async => [
              {'id': 'b1', 'guest_name': 'Bowl1', 'profiles': null},
              {'id': 'b2', 'guest_name': 'Bowl2', 'profiles': null},
              {'id': 'b3', 'guest_name': 'Bowl3', 'profiles': null},
            ]),
        matchSquadProvider(_matchId).overrideWith((ref) async => [
              _member('a1', _teamA, 'Bat1', 1),
              _member('a2', _teamA, 'Bat2', 2), // played, then left the team
              _member('b1', _teamB, 'Bowl1', 1),
              _member('b2', _teamB, 'Bowl2', 2),
              _member('b3', _teamB, 'Bowl3', 3),
            ]),
      ],
      child: const MaterialApp(home: MatchSquadsScreen(matchId: _matchId)),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a squad member who left the team is still saved on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();

        expect(repo.saves, hasLength(1), reason: 'sanity: one save');
        final ids = repo.saves.single
            .map((m) => m['team_member_id'] as String)
            .toSet();
        expect(ids, contains('a2'),
            reason: 'set_match_squad is authoritative and REFUSES to drop a '
                'player who has already played. Omitting him makes the screen '
                'answer "that player has already played in this match" with no '
                'tile on screen to tick him back on - a dead end reached by '
                'nothing more exotic than a guest leaving the team mid-match');
        expect(ids, containsAll(<String>['a1', 'b1', 'b2']),
            reason: 'and everyone still on the roster is unaffected');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: dropping a player who is still on the roster still '
        'works on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();

        // Bowl2 is on the roster and selected - untick him
        await tester.tap(find.textContaining('Bowl2'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();

        final ids = repo.saves.single
            .map((m) => m['team_member_id'] as String)
            .toSet();
        expect(ids, isNot(contains('b2')),
            reason: 'keeping departed players must not also make ordinary '
                'removals stick - that is the bug review #2 finding 10 fixed');
        expect(ids, contains('a2'),
            reason: 'while the departed player is still carried through');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
