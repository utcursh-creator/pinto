import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_repository.dart';
import 'package:pitch_app/src/features/messages/data/dm_realtime.dart';
import 'package:pitch_app/src/features/messages/presentation/dm_thread_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 41: an open DM thread never
/// re-syncs, so any message that arrives while the socket is down is lost from
/// the conversation until the screen is closed and reopened.
///
/// The thread loaded its history exactly once in initState and every message
/// after that came from a broadcast callback. A tunnel, a locked phone, a
/// dropped socket - and the missed messages simply never appeared. Worse than
/// the equivalent bug on the match viewer (fixed in 0ed439d): there the score
/// froze visibly, here the conversation looks complete and healthy while the
/// other person is replying into a void. The user is actively typing back at
/// someone whose last three messages they cannot see.
///
/// The same three recoveries the viewer got: on (re)subscribe, on return to the
/// foreground, and pull-to-refresh.
class _Repo extends Fake implements DiscoverRepository {
  _Repo(this.rows);

  /// Everything the server holds for the thread, oldest first.
  List<Map<String, dynamic>> rows;

  /// Every `after` argument the screen has asked with, in order. `null` is the
  /// initial load.
  final List<String?> asks = [];
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> threadMessages(String threadId,
      {String? after, int limit = 200}) async {
    asks.add(after);
    if (after == null) return List.of(rows);
    return [
      for (final r in rows)
        if ((r['created_at'] as String).compareTo(after) > 0) r,
    ];
  }

  @override
  Future<void> markThreadRead(String threadId) async => reads++;
}

/// A realtime double whose subscribe moment the test controls, because that is
/// precisely the moment a real socket comes back after a gap.
class _Realtime extends Fake implements DmRealtime {
  void Function(Map<String, dynamic>)? onInsert;
  void Function()? onSubscribed;
  int attaches = 0;

  @override
  void Function() listen(
    String threadId,
    void Function(Map<String, dynamic>) onInsert, {
    void Function()? onSubscribed,
  }) {
    attaches++;
    this.onInsert = onInsert;
    this.onSubscribed = onSubscribed;
    return () {
      this.onInsert = null;
      this.onSubscribed = null;
    };
  }
}

Map<String, dynamic> _msg(String id, String at, {String from = 'them'}) =>
    {'id': id, 'sender_id': from, 'body': 'msg $id', 'created_at': at};

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

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the socket coming back pulls in what was missed on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([_msg('a', '2026-08-05T10:00:00Z')]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();
        expect(find.text('msg a'), findsOneWidget, reason: 'sanity: history');

        // the phone goes through a tunnel; Priya replies twice; the socket
        // comes back and re-joins the topic
        repo.rows = [
          ...repo.rows,
          _msg('b', '2026-08-05T10:05:00Z'),
          _msg('c', '2026-08-05T10:06:00Z'),
        ];
        rt.onSubscribed?.call();
        await tester.pumpAndSettle();

        expect(find.text('msg b'), findsOneWidget,
            reason: 'a re-subscribe means the socket was down, and what was '
                'missed while it was down is exactly what is not on screen');
        expect(find.text('msg c'), findsOneWidget);
        expect(repo.reads, greaterThan(1),
            reason: 'and messages caught up while the thread is open are read');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('coming back to the app catches up on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([_msg('a', '2026-08-05T10:00:00Z')]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();

        // locked phone: the socket is torn down by the OS with no re-subscribe
        // when it wakes, so this is a separate recovery, not a duplicate one
        repo.rows = [...repo.rows, _msg('b', '2026-08-05T10:05:00Z')];
        // the real transition order the framework asserts on
        for (final s in const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        await tester.pumpAndSettle();

        expect(find.text('msg b'), findsOneWidget,
            reason: 'a phone that was asleep through a conversation must catch '
                'up when it wakes');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and the user can always pull to refresh on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([
          for (var i = 0; i < 12; i++)
            _msg('m$i', '2026-08-05T10:${i.toString().padLeft(2, '0')}:00Z'),
        ]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();

        repo.rows = [...repo.rows, _msg('late', '2026-08-05T11:00:00Z')];
        // the thread opens pinned to the newest message, so reaching the top is
        // part of the gesture
        await tester.drag(find.byType(ListView), const Offset(0, 900));
        await tester.pumpAndSettle();
        await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
        await tester.pumpAndSettle();

        expect(find.text('msg late'), findsOneWidget,
            reason: 'the last resort a user reaches for must work - both other '
                'recoveries depend on events the user cannot trigger');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a re-sync asks only for what it lacks and never '
        'doubles a message on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo([
          _msg('a', '2026-08-05T10:00:00Z'),
          _msg('b', '2026-08-05T10:01:00Z'),
        ]);
        final rt = _Realtime();
        final container = _container(repo, rt);
        addTearDown(container.dispose);
        await tester.pumpWidget(_screen(container));
        await tester.pumpAndSettle();
        expect(repo.asks, [null], reason: 'the first load takes the history');

        rt.onSubscribed?.call();
        await tester.pumpAndSettle();

        expect(repo.asks.last, '2026-08-05T10:01:00Z',
            reason: 're-downloading the whole thread on every reconnect is the '
                'bug this fix must not introduce - ask from the newest message '
                'held');
        expect(find.text('msg a'), findsOneWidget);
        expect(find.text('msg b'), findsOneWidget,
            reason: 'a message already on screen must not appear twice');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
