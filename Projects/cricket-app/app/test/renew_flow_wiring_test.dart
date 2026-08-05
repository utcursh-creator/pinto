import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_repository.dart';
import 'package:pitch_app/src/features/discover/presentation/my_posts_screen.dart';

/// Review #3, finding 14 - THE WIRING half.
///
/// renew_feed_floor_test.dart proves the RULE. It cannot prove the screen calls
/// it, and that gap is not hypothetical: the same shape bit this project on the
/// run-out `crossed` flag, where the repository spy sat above the RPC and
/// deleting the parameter failed nothing. So this file drives the real pickers
/// on the real screen.
///
/// What must hold: the flow ASKS for a time (it only asked for a date, which is
/// why it reused the old time of day), and a renewal that would land past the
/// feed floor is refused out loud instead of writing a post nobody can see.
class _SpyRepo extends Fake implements DiscoverRepository {
  DateTime? sawMatchAt;
  var renewCalls = 0;

  @override
  Future<void> renewPost(String postId, {DateTime? matchAt}) async {
    renewCalls++;
    sawMatchAt = matchAt;
  }
}

/// An ad for a game that has been and gone: match_at well past the 6h floor,
/// expires_at past, status still open - which is exactly what puts the Expired
/// chip and the Renew button on screen.
List<Map<String, dynamic>> _expiredPost(DateTime matchAt) => [
      {
        'id': 'p1',
        'status': 'open',
        'mode': 'team_seeking_players',
        'flair': 'practice_match',
        'body': 'Need 2 players',
        'match_at': matchAt.toUtc().toIso8601String(),
        'expires_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      },
    ];

Future<void> _pump(WidgetTester tester, _SpyRepo spy, DateTime matchAt) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      discoverRepositoryProvider.overrideWithValue(spy),
      myPostsProvider.overrideWith((ref) async => _expiredPost(matchAt)),
    ],
    child: const MaterialApp(home: MyPostsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the renew flow asks for a TIME, not just a date, on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        // 09:00 four days ago - the fixture in the finding
        await _pump(
            tester, spy, DateTime.now().subtract(const Duration(days: 4)));

        expect(find.text('Renew'), findsOneWidget,
            reason: 'sanity: an expired open post offers Renew');
        await tester.tap(find.text('Renew'));
        await tester.pumpAndSettle();

        expect(find.text('When is the new game?'), findsOneWidget,
            reason: 'sanity: the date picker');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text('What time?'), findsOneWidget,
            reason: 'the flow only ever asked for a DATE, so it rebuilt the '
                'instant from the OLD time of day - the whole mechanism of the '
                'silent re-burial. There must be a way to say what time');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(spy.renewCalls, 1, reason: 'the renewal went through');
        expect(spy.sawMatchAt, isNotNull,
            reason: 'and it carried a new match time');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a renewal that would land past the feed floor is refused out '
        'loud on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        // The trap: the old fixture time is EARLIER TODAY, past the 6h floor.
        // Accepting the date picker's default and the time picker's default
        // therefore reproduces exactly what the old flow did silently.
        final now = DateTime.now();
        if (now.hour < 7) {
          // Before 07:00 there is no "earlier today, past the floor" hour to
          // use, so the trap cannot be set. Say so rather than assert nothing.
          markTestSkipped('needs a wall clock after 07:00 to set the trap');
          return;
        }
        await _pump(tester, spy,
            DateTime(now.year, now.month, now.day, 0, 30)
                .subtract(const Duration(days: 4)));

        await tester.tap(find.text('Renew'));
        await tester.pumpAndSettle();
        // pick TODAY, which the finding's captain does for a game later today
        await tester.tap(find.text('${now.day}').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // keep the old 00:30 - the time picker's default here
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(spy.renewCalls, 0,
            reason: 'renewing to a time already past the feed floor must not '
                'be written. It left the post invisible AND removed the '
                'Expired chip and the Renew button, because "expired" on this '
                'screen is computed from expires_at alone - the author ended '
                'up worse off than before they tapped it');
        expect(find.textContaining('nobody would see this post'), findsOneWidget,
            reason: 'and the refusal has to be said out loud, in the same '
                'words the composer uses for the same rule');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
