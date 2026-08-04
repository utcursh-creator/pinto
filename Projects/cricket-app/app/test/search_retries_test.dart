import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/search_screen.dart';

/// Whole-system review #2 (2026-07-28), findings 33 / 64 / 86: a search that
/// fails once can never be retried.
///
/// searchProvider is a plain `FutureProvider.family` keyed by the query string,
/// and in riverpod 3 FutureProvider defaults to isAutoDispose = false. The
/// screen watches it on every keystroke, so:
///
///   * every prefix a user types leaves a provider element alive for the whole
///     session ("r", "ra", "rah", "rahu", "rahul" from one name), and
///   * a query that failed on a dropped connection stays cached AS AN ERROR,
///     so retyping the exact same name re-watches the same dead element and
///     never re-hits the network. The user is stuck on "Search failed." until
///     they restart the app - and the only thing they will naturally try,
///     typing it again, is precisely the thing that cannot work.
///
/// The failure also rendered as a bare line of text with nothing to tap.
class _Boom implements Exception {
  @override
  String toString() => 'Exception: boom';
}

void main() {
  // The rule, so the next free-text provider does not repeat this. A family
  // keyed by an ID (teamId, matchId, inningsId) SHOULD cache and is
  // deliberately left alone - caching a match by its id is the point. A family
  // keyed by what someone is typing has an unbounded key space and must not.
  test('every search provider is autoDispose', () {
    final offenders = <String>[];
    final decl = RegExp(
        r'final (\w*[Ss]earch\w*Provider)\s*=\s*((?:.|\n){0,120}?)family<');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final m in decl.allMatches(entity.readAsStringSync())) {
        if (!m.group(2)!.contains('autoDispose')) {
          offenders.add('${entity.path}: ${m.group(1)}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a search provider keyed by the query string must be '
            'autoDispose, or every prefix typed leaks for the session and a '
            'failed query is cached as a failure that retyping cannot clear: '
            '\n${offenders.join('\n')}');
  });

  test('a repeated search actually runs again', () async {
    var calls = 0;
    final container = ProviderContainer(overrides: [
      searchProvider.overrideWith((ref, q) async {
        calls++;
        return const <Map<String, dynamic>>[];
      }),
    ]);
    addTearDown(container.dispose);

    // the screen watches while it is on screen...
    final sub = container.listen(searchProvider('rahul'), (_, _) {});
    await container.read(searchProvider('rahul').future);
    expect(calls, 1);

    // ...and stops when the user types something else or leaves
    sub.close();
    await Future<void>.delayed(Duration.zero);

    await container.read(searchProvider('rahul').future);
    expect(calls, 2,
        reason: 'searching the same name again must re-run the query. While '
            'the element survives with nothing listening, a search that failed '
            'is cached as a failure forever, and retyping the name - the one '
            'thing a user will try - re-reads the same dead result.');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a failed search offers a way to try again on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var attempt = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            searchProvider.overrideWith((ref, q) async {
              attempt++;
              throw _Boom();
            }),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'rahul');
        await tester.pumpAndSettle();

        expect(find.textContaining('Try again'), findsOneWidget,
            reason: 'a dropped connection is the common case, and the screen '
                'left the user nothing to tap');
        final before = attempt;
        await tester.tap(find.textContaining('Try again'));
        await tester.pumpAndSettle();
        expect(attempt, greaterThan(before),
            reason: 'the retry must actually re-issue the search, not just '
                'rebuild the same cached error');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a genuinely empty result still says so on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // "nobody by that name" and "the search broke" are different answers
        // and must stay different - collapsing them would be a regression in
        // the other direction.
        await tester.pumpWidget(ProviderScope(
          overrides: [
            searchProvider.overrideWith(
                (ref, q) async => const <Map<String, dynamic>>[]),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'zzzz');
        await tester.pumpAndSettle();

        expect(find.textContaining('found'), findsOneWidget);
        expect(find.textContaining('Try again'), findsNothing,
            reason: 'there is nothing to retry - the search worked');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
