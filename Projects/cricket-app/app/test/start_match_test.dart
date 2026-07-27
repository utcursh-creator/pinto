import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

/// Start-a-match is the primary CTA of the whole app, and two defects lived in
/// it until the 2026-07-07 fix run:
///   * the Opponent picker was a DropdownButton fed by EVERY team in the
///     database (`from('teams').select(...)` with no limit)
///   * "Pick both teams and overs." fired even when two of the three were
///     filled, so the one missing field had to be hunted for - and 0 overs was
///     accepted, producing a match whose innings ends before a ball is bowled
List<Map<String, dynamic>> _teamRow(String id, String name) => [
      {'teams': {'id': id, 'name': name}},
    ];

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> opponents = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myTeamsProvider.overrideWith((ref) async => _teamRow('a', 'My XI')),
        opponentSearchProvider((query: '', excludeTeamId: null))
            .overrideWith((ref) async => opponents),
        opponentSearchProvider((query: '', excludeTeamId: 'a'))
            .overrideWith((ref) async => opponents),
      ],
      child: const MaterialApp(home: StartMatchScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the opponent picker searches instead of listing every team '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, opponents: [
          {
            'id': 'b',
            'name': 'Dadar CC',
            'city': 'Mumbai',
            'logo_url': null,
            'last_played': '2026-07-01T00:00:00Z',
          },
        ]);
        expect(find.text('Choose the opponent'), findsOneWidget);
        // No unbounded dropdown of teams anywhere on the screen: the only
        // DropdownButton left is "Your team", which is bounded by membership.
        expect(find.byType(DropdownButton<String>), findsOneWidget);

        await tester.tap(find.text('Choose the opponent'));
        await tester.pumpAndSettle();
        expect(find.text('Search teams'), findsOneWidget);
        // A club you have played before is offered before you type anything.
        expect(find.text('Dadar CC'), findsOneWidget);
        expect(find.textContaining('played before'), findsOneWidget);

        await tester.tap(find.text('Dadar CC'));
        await tester.pumpAndSettle();
        expect(find.text('Dadar CC'), findsOneWidget);
        expect(find.text('Choose the opponent'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('an empty search sheet says so rather than showing nothing '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('Choose the opponent'));
        await tester.pumpAndSettle();
        expect(find.text('No past opponents yet'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('validation names the field that is actually missing '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('Next: squads'));
        await tester.pumpAndSettle();
        // Overs is pre-filled with 20, so only the two teams are outstanding -
        // and the message says which, instead of the old blanket line.
        expect(find.text('Still needed: your team, the opponent.'),
            findsOneWidget);
        expect(find.text('Pick both teams and overs.'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('0 overs is refused before it reaches the server on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, opponents: [
          {
            'id': 'b',
            'name': 'Dadar CC',
            'city': 'Mumbai',
            'logo_url': null,
            'last_played': null,
          },
        ]);
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My XI').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose the opponent'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dadar CC'));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Overs'), '0');
        await tester.tap(find.text('Next: squads'));
        await tester.pumpAndSettle();
        expect(find.text('Overs must be between 1 and 100.'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
