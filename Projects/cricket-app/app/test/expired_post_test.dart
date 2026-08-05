import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_repository.dart';
import 'package:pitch_app/src/features/discover/presentation/my_posts_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 43: an expired post reads as
/// 'open' to its author, with no expiry shown and no way to renew.
///
/// discover_posts filters on expires_at AND on the match date, so the morning
/// after a Saturday game the ad is invisible to everyone else. My posts showed a
/// chip saying "open" and offered Mark filled / Cancel; nothing in the app ever
/// read expires_at. The author is told the ad is live, sees no replies, and can
/// only guess. The only way back into the feed was to post again.
class _Repo extends Fake implements DiscoverRepository {
  final List<String> renewed = [];
  DateTime? lastMatchAt;

  @override
  Future<void> renewPost(String postId, {DateTime? matchAt}) async {
    renewed.add(postId);
    lastMatchAt = matchAt;
  }
}

Map<String, dynamic> _post({
  required String id,
  required String status,
  String? expiresAt,
  String? matchAt,
}) =>
    {
      'id': id,
      'mode': 'team_seeking_players',
      'flair': 'practice_match',
      'title': 'Need 2 players $id',
      'status': status,
      'created_at': '2026-07-01T10:00:00Z',
      'expires_at': expiresAt,
      'match_at': matchAt,
    };

Widget _screen(_Repo repo, List<Map<String, dynamic>> rows) => ProviderScope(
      overrides: [
        discoverRepositoryProvider.overrideWithValue(repo),
        myPostsProvider.overrideWith((ref) async => rows),
      ],
      child: const MaterialApp(home: MyPostsScreen()),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('an expired post says so instead of "open" on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen(_Repo(), [
          _post(id: 'dead', status: 'open', expiresAt: '2026-07-20T10:00:00Z'),
        ]));
        await tester.pumpAndSettle();

        expect(find.text('Expired'), findsOneWidget,
            reason: 'the row said "open" while the feed had already dropped it '
                '- the author waits for replies that cannot come');
        expect(find.text('open'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and can be put back in the feed on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        await tester.pumpWidget(_screen(repo, [
          _post(id: 'dead', status: 'open', expiresAt: '2026-07-20T10:00:00Z'),
        ]));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renew'));
        await tester.pumpAndSettle();

        expect(repo.renewed, ['dead'],
            reason: 'nothing in the app could write expires_at at all, so the '
                'only cure was to notice and post again');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a live post shows when it runs out on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final soon = DateTime.now().add(const Duration(days: 3));
        await tester.pumpWidget(_screen(_Repo(), [
          _post(
              id: 'live',
              status: 'open',
              expiresAt: soon.toUtc().toIso8601String()),
        ]));
        await tester.pumpAndSettle();

        expect(find.textContaining('Expires in 3 days'), findsOneWidget,
            reason: 'an ad with a life span has to show it, or the author '
                'cannot tell a quiet week from a dead post');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a cancelled post is not offered a renew on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen(_Repo(), [
          _post(
              id: 'gone',
              status: 'cancelled',
              expiresAt: '2026-07-20T10:00:00Z'),
        ]));
        await tester.pumpAndSettle();

        expect(find.text('Renew'), findsNothing,
            reason: 'the server refuses it, and cancelling was a decision - '
                'renew is for an ad that ran out, not an undo');
        expect(find.text('Expired'), findsNothing,
            reason: 'and "cancelled" is the truer word for that row');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
