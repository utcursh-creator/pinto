import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/profile_provider.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/new_post_composer.dart';
import 'package:pitch_app/src/features/discover/presentation/search_screen.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/profile/presentation/profile_screen.dart';
import 'package:pitch_app/src/features/teams/presentation/claim_inbox_screen.dart';

/// Sweep Unit C: discover ball type (DISC-1), handle payoff (MISS-5), the anon
/// profile doorway (PROF-5), and the claim-inbox identity guard (TEAM-9).
void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('composer offers ball-type chips on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              myTeamsProvider.overrideWith((ref) async => []),
            ],
            child: const MaterialApp(home: NewPostComposer()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ball (optional)'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Tennis ball'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Leather ball'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Tape ball'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('search results show the @handle on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              searchProvider.overrideWith((ref, q) async => [
                    {
                      'kind': 'player',
                      'id': 'p1',
                      'name': 'Rohit Sharma',
                      'subtitle': null,
                      'photo_url': null,
                      'handle': 'hitman45',
                    },
                  ]),
            ],
            child: const MaterialApp(home: SearchScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'hitman');
        await tester.pumpAndSettle();
        expect(find.text('@hitman45'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('anonymous Profile tab is a doorway, not a wall on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              myProfileProvider.overrideWith((ref) async => null),
            ],
            child: const MaterialApp(home: ProfileScreen()),
          ),
        );
        await tester.pumpAndSettle();
        // PROF-5: real content for guests, not just a sign-in stub
        expect(find.text('Watch live matches'), findsOneWidget);
        expect(find.text('Find players and teams'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('claim inbox refuses to approve an unknown claimer on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              claimInboxProvider.overrideWith((ref) async => [
                    {
                      'id': 'r1',
                      'membership_id': 'm1',
                      'requested_by': 'u1',
                      'status': 'pending',
                      'team_members': {
                        'guest_name': 'Guesty',
                        'team_id': 't1',
                        'teams': {'name': 'Kings'},
                      },
                      'requester': null, // TEAM-9: unresolved profile
                    },
                  ]),
            ],
            child: const MaterialApp(home: ClaimInboxScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Unknown player wants to claim'),
            findsOneWidget);
        final approve = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve'));
        expect(approve.onPressed, isNull,
            reason: 'an unknown claimer cannot be blind-approved');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
