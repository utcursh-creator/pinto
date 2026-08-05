import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/discover_screen.dart';

/// Review #3 (HIGH), and review #2's deferred finding 40: the Discover mail and
/// bell badges are fetched once per app launch and never refreshed.
///
/// Discover is the initial branch of the shell so it stays mounted all session,
/// and both providers are plain FutureProviders - not autoDispose - so each
/// resolves once and holds. There was no realtime subscription of ANY kind
/// outside the Messages screens. Ten minutes and three DMs later, both badges
/// were still empty, and opening the inbox showed the ten-minute-old rows.
///
/// The live half is a per-user realtime topic (backend: pgTAP 149; client:
/// UserRealtime, watched by the app shell). That cannot be exercised without a
/// socket, so it is pinned structurally below. What IS driven here is the
/// recovery the socket cannot give you: a phone that slept through the
/// conversation must catch up when it wakes.
void main() {
  test('the badges have a live signal at all', () {
    final app = File('lib/src/app.dart').readAsStringSync();
    expect(app, contains('userRealtimeProvider'),
        reason: 'the per-user channel has to be WATCHED by the shell or it is '
            'never created - a listener nothing holds is not a listener. This '
            'is the same trap the password-recovery listener hit');

    final rt =
        File('lib/src/features/messages/data/user_realtime.dart').readAsStringSync();
    expect(rt, contains('dmInboxProvider'));
    expect(rt, contains('notificationsProvider'),
        reason: 'both badges are drawn from these two providers, so an event '
            'on the user topic has to re-read both');
    expect(rt, contains('RealtimeSubscribeStatus.subscribed'),
        reason: 'and re-read on (re)subscribe too: whatever arrived while the '
            'socket was down is exactly what the badges are not showing');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('coming back to the app re-reads both badges on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var inboxReads = 0;
        var notifReads = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            isAnonymousProvider.overrideWithValue(false),
            dmInboxProvider.overrideWith((ref) async {
              inboxReads++;
              return const <Map<String, dynamic>>[];
            }),
            notificationsProvider.overrideWith((ref) async {
              notifReads++;
              return const <Map<String, dynamic>>[];
            }),
            discoverFeedProvider.overrideWith(
                (ref, q) async => const <Map<String, dynamic>>[]),
            homeLocationProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: DiscoverScreen()),
        ));
        await tester.pumpAndSettle();
        final inboxBefore = inboxReads;
        final notifBefore = notifReads;
        expect(inboxBefore, greaterThan(0), reason: 'sanity: first fetch');

        // the phone sleeps through three messages and a reply, then wakes
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

        expect(inboxReads, greaterThan(inboxBefore),
            reason: 'the OS tears the socket down on a locked phone and does '
                'not always re-subscribe, so resume is a recovery the live '
                'channel cannot provide');
        expect(notifReads, greaterThan(notifBefore));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
