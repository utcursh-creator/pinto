import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pitch_app/src/core/routing/routes.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_squads_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/toss_openers_screen.dart';

/// THE SQUAD HANDOFF (found by driving the simulator, 2026-07-07).
///
/// The squads screen watches matchSquadProvider from the moment it opens, which
/// keeps that provider alive holding the value it had then - an EMPTY squad.
/// `_save` wrote every member and then pushReplacement'd to the toss screen in
/// the same frame, so the toss screen inherited that stale empty list: the
/// Striker and Non-striker dropdowns had nothing in them and the scorer could
/// not start the match at all. The whole point of the app, dead on the last
/// screen before it.
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

/// Stands in for the server: empty until the screen writes, populated after.
class _FakeMatchRepo implements MatchRepository {
  final List<String> added = [];

  @override
  Future<void> addSquadMember({
    required String matchId,
    required String teamId,
    required String teamMemberId,
    int? battingOrder,
    bool isCaptain = false,
    bool isKeeper = false,
  }) async {
    added.add(teamMemberId);
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  // CONFIRMED HIGH (re-review 2026-07-07): a player who LEFT the team kept their
  // match_squad rows - correct, the left_at tombstone exists so old scorecards
  // can still name them - but teamMembersProvider filters them off the roster,
  // so prefilling the resumed squad from match_squad put an id into _selected
  // with no tile to un-tick. Invisible, unremovable, and re-written to the
  // server on "Next: toss".
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a departed player is not carried back into a resumed squad '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _FakeMatchRepo();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchRepositoryProvider.overrideWithValue(repo),
              matchProvider(_matchId).overrideWith((ref) async =>
                  {'id': _matchId, 'team_a_id': _teamA, 'team_b_id': _teamB}),
              matchTeamNamesProvider(_matchId).overrideWith(
                  (ref) async => {_teamA: 'Bat XI', _teamB: 'Bowl XI'}),
              // a2 has LEFT: gone from the roster, still in the saved squad
              teamMembersProvider(_teamA).overrideWith((ref) async => [
                    {'id': 'a1', 'guest_name': 'Bat1', 'profiles': null},
                  ]),
              teamMembersProvider(_teamB).overrideWith((ref) async => [
                    {'id': 'b1', 'guest_name': 'Bowl1', 'profiles': null},
                    {'id': 'b2', 'guest_name': 'Bowl2', 'profiles': null},
                  ]),
              matchSquadProvider(_matchId).overrideWith((ref) async => [
                    _member('a1', _teamA, 'Bat1', 1),
                    _member('a2', _teamA, 'Bat2', 2), // the departed player
                    _member('b1', _teamB, 'Bowl1', 1),
                    _member('b2', _teamB, 'Bowl2', 2),
                  ]),
            ],
            child: const MaterialApp(
              home: MatchSquadsScreen(matchId: _matchId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // they are not on screen at all...
        expect(find.text('Bat2'), findsNothing);
        // ...and the count must not be silently counting them
        expect(find.textContaining('Next: toss (3 picked)'), findsOneWidget,
            reason: 'three selectable players remain, not four');

        // one selectable player per side is not enough, so add the other side's
        // - the point is only that a2 is never written back.
        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();
        expect(repo.added, isNot(contains('a2')),
            reason: 'a player who left the team must never be re-written into '
                'the squad by a resumed setup');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the squad saved on the squads screen reaches the toss screen '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _FakeMatchRepo();
        var squadFetches = 0;

        final router = GoRouter(
          initialLocation: Routes.matchSquads(_matchId),
          routes: [
            GoRoute(
              path: '/matches/:id/squads',
              builder: (_, _) => const MatchSquadsScreen(matchId: _matchId),
            ),
            GoRoute(
              path: '/matches/:id/toss',
              builder: (_, _) => const TossOpenersScreen(matchId: _matchId),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchRepositoryProvider.overrideWithValue(repo),
              matchProvider(_matchId).overrideWith((ref) async =>
                  {'id': _matchId, 'team_a_id': _teamA, 'team_b_id': _teamB}),
              matchTeamNamesProvider(_matchId)
                  .overrideWith((ref) async => {_teamA: 'Bat XI', _teamB: 'Bowl XI'}),
              teamMembersProvider(_teamA).overrideWith((ref) async => [
                    {'id': 'a1', 'guest_name': 'Bat1', 'profiles': null},
                    {'id': 'a2', 'guest_name': 'Bat2', 'profiles': null},
                  ]),
              teamMembersProvider(_teamB).overrideWith((ref) async => [
                    {'id': 'b1', 'guest_name': 'Bowl1', 'profiles': null},
                    {'id': 'b2', 'guest_name': 'Bowl2', 'profiles': null},
                  ]),
              // The server is empty on the first read and populated afterwards.
              // Only a genuine re-read gets the second answer, so this fails
              // unless the screen actually invalidates before navigating.
              matchSquadProvider(_matchId).overrideWith((ref) async {
                squadFetches++;
                if (squadFetches == 1) return const <Map<String, dynamic>>[];
                return [
                  _member('a1', _teamA, 'Bat1', 1),
                  _member('a2', _teamA, 'Bat2', 2),
                  _member('b1', _teamB, 'Bowl1', 1),
                  _member('b2', _teamB, 'Bowl2', 2),
                ];
              }),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        for (final name in ['Bat1', 'Bat2', 'Bowl1', 'Bowl2']) {
          await tester.tap(find.text(name));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.textContaining('Next: toss'));
        await tester.pumpAndSettle();

        expect(repo.added.length, 4, reason: 'all four were written');
        expect(find.text('Toss winner'), findsOneWidget);

        // Choose the toss so the opening-pair pickers become active.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bat XI'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bat'));
        await tester.pumpAndSettle();

        // THE ASSERTION: the batting side's players are actually offered. With
        // the stale empty list these dropdowns held no items whatsoever.
        final striker = tester.widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>));
        expect(striker.isNotEmpty, isTrue);
        expect(striker.first.items, isNotNull);
        expect(striker.first.items!.length, greaterThan(0),
            reason: 'the opening-pair picker must offer the squad we just saved');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
