import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_repository.dart';
import 'package:pitch_app/src/features/messages/data/dm_realtime.dart';
import 'package:pitch_app/src/features/messages/presentation/dm_inbox_screen.dart';
import 'package:pitch_app/src/features/messages/presentation/dm_thread_screen.dart';

/// Sent / delivered / seen ticks in a DM thread (user request, 2026-08-05).
///
///   one tick            the server has the message
///   two ticks           the other person's app has it   (delivered_at)
///   two coloured ticks  they opened the thread          (read_at)
///
/// The distinction that matters to a captain chasing a fixture is between "my
/// message never reached them" and "they have read it and not replied". Ticks
/// only ever appear on YOUR OWN messages - a receipt on somebody else's bubble
/// would be meaningless.
const _seen = Color(0xFF8AD8FF);

class _Repo extends Fake implements DiscoverRepository {
  _Repo(this.rows);
  List<Map<String, dynamic>> rows;
  int deliveredCalls = 0;
  int receiptReads = 0;

  @override
  Future<List<Map<String, dynamic>>> threadMessages(String threadId,
          {String? after, int limit = 200}) async =>
      after == null
          ? List.of(rows)
          : [
              for (final r in rows)
                if ((r['created_at'] as String).compareTo(after) > 0) r,
            ];

  @override
  Future<List<Map<String, dynamic>>> myReceipts(String threadId,
      {int limit = 50}) async {
    receiptReads++;
    return [
      for (final r in rows)
        if (r['sender_id'] == 'me')
          {
            'id': r['id'],
            'delivered_at': r['delivered_at'],
            'read_at': r['read_at'],
          },
    ];
  }

  @override
  Future<void> markThreadRead(String threadId) async {}

  @override
  Future<void> markThreadDelivered(String threadId) async => deliveredCalls++;
}

class _Realtime extends Fake implements DmRealtime {
  void Function(Map<String, dynamic>)? onInsert;
  void Function()? onReceipt;

  @override
  void Function() listen(
    String threadId,
    void Function(Map<String, dynamic>) onInsert, {
    void Function()? onSubscribed,
    void Function()? onReceipt,
  }) {
    this.onInsert = onInsert;
    this.onReceipt = onReceipt;
    return () {};
  }
}

Map<String, dynamic> _mine(String id,
        {String? deliveredAt, String? readAt, String at = '2026-08-05T10:00:00Z'}) =>
    {
      'id': id,
      'sender_id': 'me',
      'body': 'msg $id',
      'created_at': at,
      'delivered_at': deliveredAt,
      'read_at': readAt,
    };

final _session = Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: User(
    id: 'me',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

ProviderContainer _container(_Repo repo, _Realtime rt) =>
    ProviderContainer(overrides: [
      discoverRepositoryProvider.overrideWithValue(repo),
      dmRealtimeProvider.overrideWithValue(rt),
      currentSessionProvider.overrideWithValue(_session),
      threadOtherProvider.overrideWith(
          (ref, id) async => {'id': 'them', 'display_name': 'Priya'}),
      dmInboxProvider.overrideWith((ref) async => const []),
    ]);

Widget _screen(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: DmThreadScreen(threadId: 't1')),
    );

/// The tick widget for a given bubble body, or null if that bubble has none.
Icon? _tickFor(WidgetTester tester, String body) {
  final bubble = find.ancestor(
    of: find.text(body),
    matching: find.byType(Column),
  );
  final icons = find.descendant(of: bubble.first, matching: find.byType(Icon));
  if (icons.evaluate().isEmpty) return null;
  return tester.widget<Icon>(icons.first);
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('one tick sent, two delivered, two coloured seen on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([
          _mine('a', at: '2026-08-05T10:00:00Z'),
          _mine('b',
              deliveredAt: '2026-08-05T10:01:30Z', at: '2026-08-05T10:01:00Z'),
          _mine('c',
              deliveredAt: '2026-08-05T10:02:30Z',
              readAt: '2026-08-05T10:03:00Z',
              at: '2026-08-05T10:02:00Z'),
        ]);
        final container = _container(repo, _Realtime());
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();

        expect(_tickFor(tester, 'msg a')?.icon, Icons.done,
            reason: 'on the server, not yet on their phone');
        expect(_tickFor(tester, 'msg b')?.icon, Icons.done_all,
            reason: 'their app has it');
        expect(_tickFor(tester, 'msg b')?.color, isNot(_seen),
            reason: 'delivered is not seen - that is the distinction the whole '
                'feature exists for');
        expect(_tickFor(tester, 'msg c')?.icon, Icons.done_all);
        expect(_tickFor(tester, 'msg c')?.color, _seen,
            reason: 'they opened the thread');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a receipt arriving updates the ticks in place on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([_mine('a')]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();
        expect(_tickFor(tester, 'msg a')?.icon, Icons.done);

        // Priya's phone picks the message up, then she opens the thread. The
        // server broadcasts a receipt on the same dm:<thread> topic.
        repo.rows = [
          _mine('a',
              deliveredAt: '2026-08-05T10:01:00Z',
              readAt: '2026-08-05T10:02:00Z'),
        ];
        rt.onReceipt?.call();
        await tester.pumpAndSettle();

        expect(_tickFor(tester, 'msg a')?.icon, Icons.done_all,
            reason: 'a tick that only updates when the screen is reopened is '
                'not a receipt, it is a guess');
        expect(_tickFor(tester, 'msg a')?.color, _seen);
        expect(repo.receiptReads, greaterThan(0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('receiving a message tells the sender it arrived on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();

        rt.onInsert?.call({
          'id': 'x',
          'sender_id': 'them',
          'body': 'on my way',
          'created_at': '2026-08-05T10:05:00Z',
        });
        await tester.pumpAndSettle();

        expect(repo.deliveredCalls, greaterThan(0),
            reason: 'the tick on THEIR side only moves because our app says it '
                'has the message');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a message that arrives while you are on the inbox is still '
        'delivered on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([]);
        final rt = _Realtime();
        final container = ProviderContainer(overrides: [
          discoverRepositoryProvider.overrideWithValue(repo),
          dmRealtimeProvider.overrideWithValue(rt),
          currentSessionProvider.overrideWithValue(_session),
          dmInboxProvider.overrideWith((ref) async => [
                {
                  'thread_id': 't1',
                  'other': {'id': 'them', 'display_name': 'Priya'},
                  'preview': 'hi',
                  'last_at': '2026-08-05T10:00:00Z',
                  'unread': 1,
                },
              ]),
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DmInboxScreen()),
        ));
        await tester.pumpAndSettle();

        rt.onInsert?.call({
          'id': 'y',
          'sender_id': 'them',
          'body': 'on my way',
          'created_at': '2026-08-05T10:05:00Z',
        });
        await tester.pumpAndSettle();

        expect(repo.deliveredCalls, greaterThan(0),
            reason: 'two ticks mean "their phone has it", not "they had the '
                'thread open". The inbox is where a message actually lands '
                'while someone is using the app');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: their messages carry no ticks on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([
          {
            'id': 'z',
            'sender_id': 'them',
            'body': 'see you at 3',
            'created_at': '2026-08-05T10:00:00Z',
            'delivered_at': '2026-08-05T10:00:05Z',
            'read_at': '2026-08-05T10:00:09Z',
          },
        ]);
        final container = _container(repo, _Realtime());
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();

        expect(_tickFor(tester, 'see you at 3'), isNull,
            reason: 'a receipt on somebody else\'s bubble tells you nothing - '
                'you already know you have it, and showing when THEY read '
                'their own message is nonsense');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
