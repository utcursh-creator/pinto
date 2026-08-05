import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_repository.dart';
import 'package:pitch_app/src/features/teams/presentation/claim_inbox_screen.dart';

/// Review #3 (LOW), finding 23: a guest claim can be approved but never
/// declined, so a bogus claim sits in the captain's inbox forever.
///
/// Approving rewrites team_members.profile_id - it hands over that guest's
/// entire batting and bowling history. A stranger who taps "This is me" on a
/// public team page is asking for somebody's career, and the row's only control
/// was Approve. No Decline, no dismiss, no swipe action. The request stayed
/// pending and came back on every visit; the requester could not withdraw it
/// either. Backend half: pgTAP 154.
class _SpyRepo extends Fake implements IdentityRepository {
  String? declinedMembership;
  String? declinedClaimer;
  var approveCalls = 0;
  var declineCalls = 0;

  @override
  Future<void> approveGuestClaim({
    required String membershipId,
    required String claimerId,
  }) async {
    approveCalls++;
  }

  @override
  Future<void> declineGuestClaim({
    required String membershipId,
    required String claimerId,
  }) async {
    declineCalls++;
    declinedMembership = membershipId;
    declinedClaimer = claimerId;
  }
}

List<Map<String, dynamic>> _oneClaim() => [
      {
        'id': 'req1',
        'membership_id': 'mem1',
        'requested_by': 'rando',
        'status': 'pending',
        'team_members': {
          'guest_name': 'Ravi',
          'team_id': 't1',
          'teams': {'name': 'Claim XI'},
        },
        'requester': {'display_name': 'Rando', 'photo_url': null},
      },
    ];

Future<void> _pump(WidgetTester tester, _SpyRepo spy) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      identityRepositoryProvider.overrideWithValue(spy),
      claimInboxProvider.overrideWith((ref) async => _oneClaim()),
    ],
    child: const MaterialApp(home: ClaimInboxScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a captain can decline a claim on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await _pump(tester, spy);
        expect(find.textContaining('wants to claim'), findsOneWidget,
            reason: 'sanity: the claim is in the inbox');

        expect(find.text('Decline'), findsOneWidget,
            reason: 'the row offered only Approve, so a bogus claim on '
                'somebody else\'s career could be accepted or ignored, and '
                'ignoring it meant seeing it again every single visit');
        await tester.tap(find.text('Decline'));
        await tester.pumpAndSettle();

        expect(spy.declineCalls, 1);
        expect(spy.approveCalls, 0,
            reason: 'declining must never fall through to approving - these '
                'two buttons sit next to each other and one of them hands over '
                'a career');
        expect(spy.declinedMembership, 'mem1');
        expect(spy.declinedClaimer, 'rando',
            reason: 'the claim is identified by BOTH the membership and who '
                'asked - a membership can have competing claims');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: Approve still approves on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await _pump(tester, spy);
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        expect(spy.approveCalls, 1);
        expect(spy.declineCalls, 0,
            reason: 'and adding a second control must not have swapped the '
                'meaning of the first');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('an unresolvable claimer can be declined but not approved on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            identityRepositoryProvider.overrideWithValue(spy),
            claimInboxProvider.overrideWith((ref) async {
              final rows = _oneClaim();
              // TEAM-9: a claimer whose profile cannot be resolved
              rows[0]['requester'] = null;
              return rows;
            }),
          ],
          child: const MaterialApp(home: ClaimInboxScreen()),
        ));
        await tester.pumpAndSettle();

        final approve = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve'));
        expect(approve.onPressed, isNull,
            reason: 'never blind-approve an unknown claimer (TEAM-9)');
        await tester.tap(find.text('Decline'));
        await tester.pumpAndSettle();
        expect(spy.declineCalls, 1,
            reason: 'but declining one is exactly what a captain should be '
                'able to do - it is the most suspicious row on the screen, and '
                'before this it was the one they could do least about');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
