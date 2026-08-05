import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/teams/presentation/team_page_screen.dart';

/// Review #3: a team admin can never remove a guest player, because the
/// "This is me" claim button shadows the admin menu on every guest row.
///
/// _MemberTile resolves its trailing widget in order: `if (onClaim != null)`
/// wins, `else if (adminMenu ...)`. At the call site onClaim is non-null for ANY
/// signed-in non-anonymous viewer looking at a row with no profile_id - the
/// captain included - so on a guest row the captain's only control is a button
/// that files a claim against their own team's guest. A typo ("Rahil") or a
/// one-off ringer stays on the roster for good, and keeps appearing in every
/// future match-squad picker.
///
/// Not a backend limitation: leave_team already handles guest rows, and an
/// admin is allowed to call it. Purely widget precedence.
const _teamId = 't1';
const _me = 'me';

final _session = Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: User(
    id: _me,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

/// captain = me, plus one guest with no account.
List<Map<String, dynamic>> _roster({required String myRole}) => [
      {
        'id': 'mem-me',
        'role': myRole,
        'guest_name': null,
        'profile_id': _me,
        'profiles': {'display_name': 'Me', 'photo_url': null},
      },
      {
        'id': 'mem-guest',
        'role': 'player',
        'guest_name': 'Rahil',
        'profile_id': null,
        'profiles': null,
      },
    ];

Widget _screen({required String myRole}) => ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(_session),
        isAnonymousProvider.overrideWithValue(false),
        teamProvider(_teamId).overrideWith(
            (ref) async => {'id': _teamId, 'name': 'Sunday XI', 'city': 'Pune'}),
        teamRosterProvider(_teamId)
            .overrideWith((ref) async => _roster(myRole: myRole)),
        teamGroundProvider(_teamId).overrideWith((ref) async => null),
        teamStatsProvider(_teamId).overrideWith((ref) async => const <String, dynamic>{}),
        pendingJoinRequestsProvider(_teamId).overrideWith((ref) async => []),
        teamMatchesProvider(_teamId).overrideWith((ref) async => []),
      ],
      child: const MaterialApp(home: TeamPageScreen(teamId: _teamId)),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a captain can remove a guest they added by mistake on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen(myRole: 'captain'));
        await tester.pumpAndSettle();
        expect(find.text('Rahil'), findsOneWidget, reason: 'sanity: the guest');

        final menu = find.byKey(const Key('member_menu_mem-guest'));
        expect(menu, findsOneWidget,
            reason: 'the claim button shadowed the admin menu on every guest '
                'row, so a mistyped guest could never be taken off the roster '
                'and kept turning up in every squad picker');

        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Remove from team'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and can still claim the guest as themselves on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen(myRole: 'captain'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member_menu_mem-guest')));
        await tester.pumpAndSettle();
        expect(find.text('This is me'), findsOneWidget,
            reason: 'a captain is also a player - moving the claim into the '
                'menu must not remove it. Captains are exactly the people who '
                'add a guest for themselves before their account exists');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: an ordinary member still gets the claim button, not '
        'a menu, on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen(myRole: 'player'));
        await tester.pumpAndSettle();

        expect(find.text('This is me'), findsOneWidget,
            reason: 'a non-admin sees the claim button exactly as before');
        expect(find.byKey(const Key('member_menu_mem-guest')), findsNothing,
            reason: 'and no admin menu - this fix must not hand roster powers '
                'to everyone who can see the team');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
