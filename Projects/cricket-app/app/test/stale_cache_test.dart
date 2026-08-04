import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_providers.dart';
import 'package:pitch_app/src/features/tournaments/presentation/tournaments_list_screen.dart';

/// Whole-system review #2 (2026-07-28), findings 34, 55 and 87: three caches
/// that keep answering after the thing they describe has changed.
///
/// Riverpod providers here are NOT autoDispose, so a value fetched once is held
/// for the whole process. That is deliberate - it is what stops the app
/// re-fetching a match on every tab switch - but it means anything that changes
/// the underlying row has to say so, and three places did not.
void main() {
  // ---- 34: abandoning a match tells only the Matches list -------------------
  //
  // The scorer opens the console (caching matchProvider(id) with status 'live'),
  // pops back, and abandons the match from the tile menu. The tile moves to
  // Completed, but matchProvider(id), liveMatchesProvider and
  // teamMatchesProvider all still hold the pre-abandon row: the viewer renders
  // the red LIVE badge with no result, the Info tab says "Status: live", and
  // Watch-live still lists it. The viewer's realtime re-fold cannot save it -
  // it subscribes when opened, long after the UPDATE broadcast fired.
  test('abandoning a match refreshes every cache that describes it', () {
    final src = File('lib/src/features/matches/presentation/matches_screen.dart')
        .readAsStringSync();
    final at = src.indexOf('await run();');
    expect(at, isNot(-1), reason: 'sanity: the confirm-and-run helper');
    final after = src.substring(at, src.indexOf('} catch', at));

    for (final p in const [
      'myMatchesProvider',
      'matchProvider',
      'liveMatchesProvider',
      'teamMatchesProvider',
    ]) {
      expect(after, contains(p),
          reason: 'abandoning or deleting a match changes what EVERY one of '
              'these providers would answer. $p was left holding the old row, '
              'so the match still reads as live to viewers:\n$after');
    }
  });

  // ---- 55: the anchor outlives the user who chose it -----------------------
  test('the discover anchor does not follow one user into the next signed-in '
      'session', () async {
    final container = ProviderContainer(overrides: [
      currentSessionProvider.overrideWith((ref) => _sessionFor(ref)),
    ]);
    addTearDown(container.dispose);
    container.listen(anchorProvider, (_, _) {}, fireImmediately: true);

    // A signs in and pins the feed to Delhi
    container.read(_whoProvider.notifier).who = 'user-a';
    container
        .read(anchorProvider.notifier)
        .set((lat: 28.61, lng: 77.20, radiusM: 25000.0));
    expect(container.read(anchorProvider), isNotNull);

    // A signs out, B signs in on the same phone
    container.read(_whoProvider.notifier).who = null;
    container.read(_whoProvider.notifier).who = 'user-b';

    expect(container.read(anchorProvider), isNull,
        reason: 'the anchor is a personal choice, not a device setting. Left '
            'behind, B\'s feed centres on A\'s city AND every looking-for post '
            'B publishes is geotagged there - nobody near B ever sees it, and '
            'nothing on screen shows the coordinates to explain why');
  });

  test('CONTROL: the anchor survives everything that is not a change of user',
      () async {
    final container = ProviderContainer(overrides: [
      currentSessionProvider.overrideWith((ref) => _sessionFor(ref)),
    ]);
    addTearDown(container.dispose);
    container.listen(anchorProvider, (_, _) {}, fireImmediately: true);
    container.read(_whoProvider.notifier).who = 'user-a';
    container
        .read(anchorProvider.notifier)
        .set((lat: 28.61, lng: 77.20, radiusM: 25000.0));

    // a token refresh yields a NEW Session object for the SAME person - if that
    // cleared the anchor, "Near me" would silently reset itself about once an
    // hour
    container.read(_tokenProvider.notifier).refresh();
    expect(container.read(anchorProvider)?.lat, 28.61,
        reason: 'a JWT refresh is not a new user');
  });

  // ---- 87: the tournaments list never hears about a status change ----------
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the tournaments list re-reads when it is opened on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var reads = 0;
        final rows = [
          {
            'id': 't1',
            'name': 'Sunday Cup',
            'status': 'setup',
            'organizer_id': 'me',
            'champion_team_id': null,
          },
        ];
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            tournamentsListProvider.overrideWith((ref) async {
              reads++;
              return rows;
            }),
          ],
          child: MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Matches')),
          ),
        ));
        await tester.pumpAndSettle();

        Future<void> openList() async {
          nav.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const TournamentsListScreen()));
          await tester.pumpAndSettle();
        }

        await openList();
        expect(reads, 1);
        expect(find.text('Sunday Cup'), findsOneWidget);

        // off to Manage, run the whole tournament, come back. Every one of
        // those actions invalidated only the OVERVIEW - one process, one
        // container, the list's cached row untouched.
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        rows[0]['status'] = 'completed';
        rows[0]['champion_team_id'] = 'team-x';
        await openList();

        expect(reads, greaterThan(1),
            reason: 'opening the list must re-read it. Without that the row is '
                'chipped "Registration open" for a tournament that already has '
                'a champion, and the only cure is restarting the app');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and can be pulled to refresh on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var reads = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            tournamentsListProvider.overrideWith((ref) async {
              reads++;
              return [
                {
                  'id': 't1',
                  'name': 'Sunday Cup',
                  'status': 'setup',
                  'organizer_id': 'me',
                  'champion_team_id': null,
                },
              ];
            }),
          ],
          child: const MaterialApp(home: TournamentsListScreen()),
        ));
        await tester.pumpAndSettle();
        final before = reads;

        await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
        await tester.pumpAndSettle();

        expect(reads, greaterThan(before),
            reason: 'a list a second person can change under you needs the '
                'gesture everyone tries first');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

/// Who is signed in, and a token counter, so a test can distinguish "a new
/// person" from "the same person with a fresh JWT".
class _Who extends Notifier<String?> {
  @override
  String? build() => null;
  set who(String? v) => state = v;
}

class _Token extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state = state + 1;
}

final _whoProvider = NotifierProvider<_Who, String?>(_Who.new);
final _tokenProvider = NotifierProvider<_Token, int>(_Token.new);

Session? _sessionFor(Ref ref) {
  final who = ref.watch(_whoProvider);
  final token = ref.watch(_tokenProvider);
  if (who == null) return null;
  return Session(
    accessToken: 'token-$token',
    tokenType: 'bearer',
    user: User(
      id: who,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );
}
