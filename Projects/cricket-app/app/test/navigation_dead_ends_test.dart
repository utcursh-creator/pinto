import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pitch_app/src/core/routing/routes.dart';
import 'package:pitch_app/src/core/platform/adaptive_scaffold.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_repository.dart';
import 'package:pitch_app/src/features/messages/presentation/notifications_screen.dart';
import 'package:pitch_app/src/features/teams/presentation/my_teams_screen.dart';

/// The navigation dead ends from the 2026-07-07 penetration review: rows and
/// screens that a user can reach and then cannot act on or get out of.

/// The screen marks everything read on open; that write must land somewhere.
class _NoopDiscoverRepo implements DiscoverRepository {
  @override
  Future<void> markNotificationsRead() async {}

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> _n(String type, String? refId) => {
      'id': 'n-$type',
      'type': type,
      'ref_id': refId,
      'body': 'body for $type',
      'created_at': '2026-07-07T10:00:00Z',
      'read_at': null,
    };

/// Pumps the screen behind a real router so a tap can be checked for where it
/// actually LANDS. Asserting `onTap != null` would prove nothing: every row
/// already had a non-null onTap - it just fell through the switch and did
/// nothing, which is exactly the defect.
late GoRouter _router;

Future<void> _pumpNotifications(
  WidgetTester tester,
  List<Map<String, dynamic>> rows,
) async {
  _router = GoRouter(
    initialLocation: Routes.notifications,
    routes: [
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
          path: Routes.claimInbox,
          builder: (_, s) => _Stub(s.uri.toString())),
      GoRoute(
          path: '/profile/teams/:id',
          builder: (_, s) => _Stub(s.uri.toString())),
      GoRoute(
          path: '/discover/post/:id',
          builder: (_, s) => _Stub(s.uri.toString())),
      GoRoute(
          path: '/discover/messages/:id',
          builder: (_, s) => _Stub(s.uri.toString())),
      GoRoute(path: '/watch/:id', builder: (_, s) => _Stub(s.uri.toString())),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) async => rows),
        discoverRepositoryProvider.overrideWithValue(_NoopDiscoverRepo()),
      ],
      child: MaterialApp.router(routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
}

/// The landed-on screen renders its own location, so the assertion is on what
/// the user is actually looking at rather than on router bookkeeping.
class _Stub extends StatelessWidget {
  const _Stub(this.location);
  final String location;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(location));
}

void main() {
  group('invite code entry', () {
    // A captain shares https://pitch.app/invite/<token>, and that domain is not
    // registered for deep links yet - so the recipient needs to be able to
    // redeem the code by hand. People paste the whole link, not the token.
    test('accepts a bare token', () {
      expect(inviteTokenFrom('abc123'), 'abc123');
    });
    test('accepts the whole shared link', () {
      expect(inviteTokenFrom('https://pitch.app/invite/abc123'), 'abc123');
    });
    test('accepts a link a chat client decorated', () {
      expect(inviteTokenFrom('https://pitch.app/invite/abc123?utm=whatsapp'),
          'abc123');
      expect(inviteTokenFrom('  https://pitch.app/invite/abc123#x  '), 'abc123');
    });
    test('an empty paste yields nothing to navigate to', () {
      expect(inviteTokenFrom('   '), '');
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('on $platform', () {
      testWidgets('a claim request opens the claim inbox', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pumpNotifications(tester, [_n('claim_request', 'member-1')]);
          // It used to fall through the switch's default and go NOWHERE, which
          // reads as a broken app to a captain trying to act on it.
          await tester.tap(find.byType(ListTile).first);
          await tester.pumpAndSettle();
          expect(find.text(Routes.claimInbox), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('a join request opens the team that was asked', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pumpNotifications(tester, [_n('join_request', 'team-1')]);
          await tester.tap(find.byType(ListTile).first);
          await tester.pumpAndSettle();
          expect(find.text(Routes.teamPage('team-1')), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('the rows that already worked still work', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pumpNotifications(tester, [_n('match_live', 'match-9')]);
          await tester.tap(find.byType(ListTile).first);
          await tester.pumpAndSettle();
          expect(find.text(Routes.viewMatch('match-9')), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('a row that leads nowhere is not a fake tap target',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          // an unknown type, and a known type with no target
          await _pumpNotifications(
              tester, [_n('something_new', 'x'), _n('dm', null)]);
          final tiles =
              tester.widgetList<ListTile>(find.byType(ListTile)).toList();
          expect(tiles.every((t) => t.onTap == null), isTrue);
          expect(find.byIcon(Icons.chevron_right), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('a cold-started public page offers a way into the app',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          var entered = false;
          await tester.pumpWidget(MaterialApp(
            home: AdaptiveScaffold(
              title: 'Live',
              onEnterApp: () => entered = true,
              body: const SizedBox(),
            ),
          ));
          await tester.pumpAndSettle();
          // Nothing to pop: a shared link cold-started straight onto this page,
          // outside the tab shell, so without this it is an island.
          await tester.tap(find.byIcon(Icons.home_outlined));
          expect(entered, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('the same page inside a stack keeps the ordinary back button',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdaptiveScaffold(
                          title: 'Live',
                          onEnterApp: () {},
                          body: const SizedBox(),
                        ),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ));
          await tester.tap(find.text('go'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.home_outlined), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });
  }
}
