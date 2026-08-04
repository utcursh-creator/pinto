import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/identity/data/identity_repository.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_models.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_providers.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_repository.dart';
import 'package:pitch_app/src/features/tournaments/presentation/manage_tournament_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 9 (HIGH): 'Add my team' offers
/// teams the organiser is not allowed to enter, and says nothing when the add
/// is refused.
///
/// The picker was built from myTeamsProvider, which returns EVERY team the user
/// belongs to with no role filter - including ones where they are just a
/// player. `add_tournament_team` raises 'you must be an admin of this team to
/// enter it' for exactly that case, and the call was awaited with no try/catch,
/// so the throw became an unhandled async error inside a tap callback: no
/// SnackBar, no team in the list, and the overview never invalidated. The
/// organiser taps the same team again and again and concludes the app is
/// broken.
///
/// The unguarded `await ref.read(myTeamsProvider.future)` at the top of the
/// same method had the same shape: offline, the button simply did nothing.
const _tid = 't1';

class _Teams extends Fake implements IdentityRepository {
  _Teams(this.rows, {this.boom = false});
  final List<Map<String, dynamic>> rows;
  final bool boom;

  @override
  Future<List<Map<String, dynamic>>> myTeams() async {
    if (boom) throw Exception('offline');
    return rows;
  }
}

class _Repo extends Fake implements TournamentRepository {
  _Repo({this.boom = false});
  final bool boom;
  final List<String> added = [];

  @override
  Future<void> addTournamentTeam(String tournamentId, String teamId,
      [String group = 'A']) async {
    if (boom) {
      throw Exception('you must be an admin of this team to enter it');
    }
    added.add(teamId);
  }
}

TournamentOverview _overview() => TournamentOverview.fromJson({
      'tournament': {
        'id': _tid,
        'name': 'Sunday Cup',
        'status': 'setup',
        'organizer_id': 'me',
        'format': 'groups_playoffs',
      },
      'teams': const [],
      'fixtures': const [],
      'standings': const {},
      'leaderboard': const {},
    });

Widget _screen({
  required _Repo repo,
  required List<Map<String, dynamic>> myTeams,
  bool teamsFail = false,
}) =>
    ProviderScope(
      overrides: [
        tournamentRepositoryProvider.overrideWithValue(repo),
        identityRepositoryProvider
            .overrideWithValue(_Teams(myTeams, boom: teamsFail)),
        tournamentOverviewProvider(_tid).overrideWith((ref) async => _overview()),
      ],
      child: const MaterialApp(home: ManageTournamentScreen(tournamentId: _tid)),
    );

Map<String, dynamic> _membership(String id, String name, String role) => {
      'role': role,
      'teams': {'id': id, 'name': name},
    };

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a team the organiser only plays for is not offered on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo: repo, myTeams: [
          _membership('t-cap', 'My Club', 'captain'),
          _membership('t-play', 'Someone Elses Club', 'player'),
        ]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add my team'));
        await tester.pumpAndSettle();

        expect(find.text('My Club'), findsOneWidget);
        expect(find.text('Someone Elses Club'), findsNothing,
            reason: 'add_tournament_team refuses a team you are not an admin '
                'of, so offering it can only end in a refusal the organiser '
                'was never shown');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a refused add is SAID, not swallowed on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo(boom: true);
        await tester.pumpWidget(_screen(repo: repo, myTeams: [
          _membership('t-cap', 'My Club', 'admin'),
        ]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add my team'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My Club'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget,
            reason: 'the await had no try/catch at all, so the throw became an '
                'unhandled async error inside the tap callback and the '
                'organiser saw nothing whatsoever');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and a failed team list does not leave a dead button on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(
            _screen(repo: repo, myTeams: const [], teamsFail: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add my team'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget,
            reason: 'offline, the read threw before the sheet could open and '
                'the button did nothing at all - the organiser cannot tell a '
                'dead button from a slow one');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a permitted team still gets added on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo: repo, myTeams: [
          _membership('t-cap', 'My Club', 'captain'),
        ]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add my team'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My Club'));
        await tester.pumpAndSettle();

        expect(repo.added, ['t-cap'],
            reason: 'filtering by role must not filter out the teams the '
                'organiser actually runs');
        expect(find.byType(SnackBar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
