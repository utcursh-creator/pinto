import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/teams/presentation/team_page_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session _session(String uid) => Session(
      accessToken: 'tok',
      tokenType: 'bearer',
      user: User(
        id: uid,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

Future<void> _pump(WidgetTester tester, {required String viewerRole}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(_session('me')),
        teamProvider.overrideWith((ref, id) async =>
            {'id': 't1', 'name': 'Strikers', 'city': 'Mumbai', 'logo_url': null}),
        teamRosterProvider.overrideWith((ref, id) async => [
              {
                'id': 'm-me',
                'role': viewerRole,
                'guest_name': null,
                'profile_id': 'me',
                'profiles': {'display_name': 'Me', 'photo_url': null},
              },
              {
                'id': 'm-other',
                'role': 'player',
                'guest_name': null,
                'profile_id': 'p2',
                'profiles': {'display_name': 'Rahul', 'photo_url': null},
              },
            ]),
        teamGroundProvider.overrideWith((ref, id) async => null),
        teamStatsProvider.overrideWith((ref, id) async =>
            {'played': 3, 'won': 2, 'lost': 1, 'tied': 0, 'no_result': 0}),
        teamMatchesProvider.overrideWith((ref, id) async => []),
        pendingJoinRequestsProvider.overrideWith((ref, id) async => []),
      ],
      child: const MaterialApp(home: TeamPageScreen(teamId: 't1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('captain sees edit/leave/delete + per-member manage on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, viewerRole: 'captain');
        expect(tester.takeException(), isNull);
        // TEAM-5: the captain badge renders
        expect(find.textContaining('(C)'), findsOneWidget);
        // TEAM-1: the team overflow offers leave + delete + edit
        await tester.tap(find.byKey(const Key('team_menu')));
        await tester.pumpAndSettle();
        expect(find.text('Edit team'), findsOneWidget);
        expect(find.text('Leave team'), findsOneWidget);
        expect(find.text('Delete team'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5)); // dismiss
        await tester.pumpAndSettle();
        // TEAM-1/5: the other member's row offers remove + role changes
        await tester.tap(find.byKey(const Key('member_menu_m-other')));
        await tester.pumpAndSettle();
        expect(find.text('Remove from team'), findsOneWidget);
        expect(find.text('Make captain'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a plain member sees leave but not delete/manage on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, viewerRole: 'player');
        expect(tester.takeException(), isNull);
        // only the app-bar overflow exists (no member manage menus)
        expect(find.byKey(const Key('member_menu_m-other')), findsNothing);
        await tester.tap(find.byKey(const Key('team_menu')));
        await tester.pumpAndSettle();
        expect(find.text('Leave team'), findsOneWidget);
        expect(find.text('Delete team'), findsNothing);
        expect(find.text('Edit team'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a stranger sees the record + Request to join on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // viewer 'me' is NOT on the roster this time
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentSessionProvider.overrideWithValue(_session('me')),
              teamProvider.overrideWith((ref, id) async => {
                    'id': 't1',
                    'name': 'Strikers',
                    'city': 'Mumbai',
                    'logo_url': null
                  }),
              teamRosterProvider.overrideWith((ref, id) async => [
                    {
                      'id': 'm-other',
                      'role': 'captain',
                      'guest_name': null,
                      'profile_id': 'p2',
                      'profiles': {'display_name': 'Rahul', 'photo_url': null},
                    },
                  ]),
              teamGroundProvider.overrideWith((ref, id) async => null),
              teamStatsProvider.overrideWith((ref, id) async =>
                  {'played': 3, 'won': 2, 'lost': 1, 'tied': 0, 'no_result': 0}),
              teamMatchesProvider.overrideWith((ref, id) async => []),
              pendingJoinRequestsProvider.overrideWith((ref, id) async => []),
            ],
            child: const MaterialApp(home: TeamPageScreen(teamId: 't1')),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // TEAM-13: the record line renders
        expect(find.textContaining('Played 3'), findsOneWidget);
        // TEAM-11: the stranger gets a Request to join CTA
        expect(find.widgetWithText(FilledButton, 'Request to join'),
            findsOneWidget);
        // and no manage affordances
        expect(find.byKey(const Key('team_menu')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
