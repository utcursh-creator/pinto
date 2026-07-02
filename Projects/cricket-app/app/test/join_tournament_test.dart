import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/tournaments/presentation/join_tournament_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('anon visitor is prompted to sign in to join on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAnonymousProvider.overrideWithValue(true),
          ],
          child: const MaterialApp(home: JoinTournamentScreen(token: 'tok')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sign in to join'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a signed-in admin sees their teams + "Add my team" on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAnonymousProvider.overrideWithValue(false),
            myTeamsProvider.overrideWith((ref) async => [
                  {
                    'role': 'owner',
                    'teams': {'id': 't1', 'name': 'Strikers'},
                  },
                ]),
          ],
          child: const MaterialApp(home: JoinTournamentScreen(token: 'tok')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add my team'), findsOneWidget);
      // the team picker rendered (its hint); open it and the team is offered
      expect(find.text('Choose your team'), findsOneWidget);
      await tester.tap(find.text('Choose your team'));
      await tester.pumpAndSettle();
      expect(find.text('Strikers'), findsWidgets);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a signed-in user with no teams is sent to create one on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAnonymousProvider.overrideWithValue(false),
            myTeamsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: JoinTournamentScreen(token: 'tok')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create a team first'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
