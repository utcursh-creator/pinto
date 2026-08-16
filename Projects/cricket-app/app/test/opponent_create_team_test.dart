import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_repository.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

/// Journey map B1 - THE DAY-ONE WALL.
///
/// On day one nobody's opponent is on Pitch. The opponent picker is a search
/// over existing teams, and its empty state says, in our own words:
///
///     "Check the spelling, or ask them to create their team on Pitch first."
///
/// That sentence IS the gap. It tells a man standing at a ground on Sunday that
/// his opposition must install an app and sign up before he can score the game.
/// He will not do that. He will create a second team he does not own and will
/// never use again - which is exactly what the user did, and exactly what every
/// journey in this repo silently did on his behalf.
///
/// CricHeroes does not treat the opponent as a lookup at all: you create the
/// team right there, name + location, then add players. A team is CHEAP - a
/// name and a place, not an account - which is what makes that safe. See
/// 2026-08-05-cricheroes-setup-and-scoring-research.md.
const _myTeam = 'mine';

class _FakeIdentityRepo extends Fake implements IdentityRepository {
  final List<({String name, String? city})> created = [];

  @override
  Future<String> createTeam({required String name, String? city}) async {
    created.add((name: name, city: city));
    return 'new-team-id';
  }
}

Widget _screen(_FakeIdentityRepo repo) => ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(null),
        identityRepositoryProvider.overrideWithValue(repo),
        myTeamsProvider.overrideWith((ref) async => [
              // myTeams rows are membership rows with a nested 'teams' object
              {'teams': {'id': _myTeam, 'name': 'My XI', 'city': 'Pune'}},
            ]),
        // NOBODY matches - the day-one reality
        opponentSearchProvider.overrideWith(
            (ref, arg) async => const <Map<String, dynamic>>[]),
      ],
      child: const MaterialApp(home: StartMatchScreen()),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the opponent sheet lets you create the team on the spot on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _FakeIdentityRepo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();

        final field = find.textContaining('Choose the opponent');
        await tester.ensureVisible(field.first);
        await tester.pumpAndSettle();
        await tester.tap(field.first);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.widgetWithText(TextField, 'Search teams'), "Sharma's XI");
        await tester.pumpAndSettle();

        expect(find.textContaining('Create "'), findsOneWidget,
            reason: 'the search found nobody, which on day one is EVERY user. '
                'The only way on must not be "ask them to install Pitch" - a '
                'team is a name and a place, so let him make it here');

        await tester.tap(find.textContaining('Create "'));
        await tester.pumpAndSettle();

        expect(repo.created, hasLength(1),
            reason: 'the team is created with the name he already typed - not '
                'a second form he has to fill in again');
        expect(repo.created.single.name, "Sharma's XI");
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and the created team becomes the selected opponent on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _FakeIdentityRepo();
        await tester.pumpWidget(_screen(repo));
        await tester.pumpAndSettle();

        final field = find.textContaining('Choose the opponent');
        await tester.ensureVisible(field.first);
        await tester.pumpAndSettle();
        await tester.tap(field.first);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.widgetWithText(TextField, 'Search teams'), "Sharma's XI");
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Create "'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextField, 'Search teams'), findsNothing,
            reason: 'the sheet must CLOSE on create - the earlier version of '
                'this test passed while the sheet was still open, which is why '
                'it now checks the sheet is gone rather than what is on top');
        expect(find.textContaining('Choose the opponent'), findsNothing,
            reason: 'creating it must SELECT it - dumping him back on an empty '
                'picker to search for the team he just made is the same wall '
                'with an extra step');
        expect(find.text("Sharma's XI"), findsWidgets,
            reason: 'and the field names the opponent he just created');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
