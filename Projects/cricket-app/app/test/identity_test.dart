import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/profile_provider.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/profile/presentation/profile_screen.dart';
import 'package:pitch_app/src/features/teams/presentation/create_team_screen.dart';
import 'package:pitch_app/src/features/teams/presentation/my_teams_screen.dart';

void main() {
  testWidgets('Profile screen renders the profile + identity actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => <String, dynamic>{
              'display_name': 'Utkarsh A.',
              'city': 'Mumbai',
              'batting_style': 'right',
              'playing_role': 'all_rounder',
            },
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Utkarsh A.'), findsOneWidget);
    expect(find.textContaining('Mumbai'), findsWidgets);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('My teams'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('My teams lists the user teams + a create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamsProvider.overrideWith(
            (ref) async => [
              <String, dynamic>{
                'role': 'captain',
                'teams': {'id': 't1', 'name': 'Mumbai United', 'city': 'Mumbai'},
              },
            ],
          ),
        ],
        child: const MaterialApp(home: MyTeamsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mumbai United'), findsOneWidget);
    expect(find.text('Captain'), findsOneWidget);
    expect(find.text('Create team'), findsOneWidget);
  });

  testWidgets('Create team requires a name', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreateTeamScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('A team name is required.'), findsOneWidget);
  });
}
