import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/teams/presentation/claim_inbox_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('claim inbox lists pending requests on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              claimInboxProvider.overrideWith(
                (ref) async => [
                  {
                    'id': 'c1',
                    'membership_id': 'mm1',
                    'requested_by': 'u1',
                    'status': 'pending',
                    'team_members': {
                      'guest_name': 'Rahul (guest)',
                      'team_id': 't1',
                      'teams': {'name': 'Mumbai United'},
                    },
                    'requester': {'display_name': 'Rahul Kumar'},
                  },
                ],
              ),
            ],
            child: const MaterialApp(home: ClaimInboxScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Rahul Kumar'), findsOneWidget);
        expect(find.textContaining('Rahul (guest)'), findsOneWidget);
        expect(find.textContaining('Mumbai United'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('claim inbox empty state on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [claimInboxProvider.overrideWith((ref) async => [])],
            child: const MaterialApp(home: ClaimInboxScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('No pending claim requests'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
