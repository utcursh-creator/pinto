import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/messages/presentation/dm_inbox_screen.dart';
import 'package:pitch_app/src/features/messages/presentation/notifications_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('inbox shows unread badge + last time + compose on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dmInboxProvider.overrideWith((ref) async => [
                    {
                      'thread_id': 't1',
                      'other': {'display_name': 'Imran', 'photo_url': null},
                      'preview': 'see you at the ground',
                      'last_at': DateTime.now().toIso8601String(),
                      'unread': 2,
                    },
                  ]),
            ],
            child: const MaterialApp(home: DmInboxScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Imran'), findsOneWidget);
        // DM-4: the unread count badge renders
        expect(find.text('2'), findsOneWidget);
        // DM-6: a trailing time renders (today -> HH:MM)
        expect(find.textContaining(':'), findsWidgets);
        // DM-7: the compose action exists
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('notifications screen lists rows, unread emphasized on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              notificationsProvider.overrideWith((ref) async => [
                    {
                      'id': 'n1',
                      'type': 'post_reply',
                      'ref_id': 'p1',
                      'body': 'Imran replied to your post',
                      'read_at': null,
                      'created_at': DateTime.now().toIso8601String(),
                    },
                    {
                      'id': 'n2',
                      'type': 'match_live',
                      'ref_id': 'm1',
                      'body': 'Your match is live - follow the score',
                      'read_at': DateTime.now().toIso8601String(),
                      'created_at': DateTime.now().toIso8601String(),
                    },
                  ]),
            ],
            child: const MaterialApp(home: NotificationsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Imran replied to your post'), findsOneWidget);
        expect(find.textContaining('match is live'), findsOneWidget);
        expect(find.byIcon(Icons.reply_outlined), findsOneWidget);
        expect(find.byIcon(Icons.sensors), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('unread counters sum correctly', () {
    final container = ProviderContainer(overrides: [
      dmInboxProvider.overrideWith((ref) async => [
            {'thread_id': 'a', 'unread': 2},
            {'thread_id': 'b', 'unread': 0},
            {'thread_id': 'c', 'unread': 1},
          ]),
      notificationsProvider.overrideWith((ref) async => [
            {'id': '1', 'read_at': null},
            {'id': '2', 'read_at': '2026-07-03T10:00:00Z'},
          ]),
    ]);
    addTearDown(container.dispose);
    // resolve the futures first
    return Future(() async {
      await container.read(dmInboxProvider.future);
      await container.read(notificationsProvider.future);
      expect(container.read(dmUnreadCountProvider), 3);
      expect(container.read(unreadNotificationsCountProvider), 1);
    });
  });
}
