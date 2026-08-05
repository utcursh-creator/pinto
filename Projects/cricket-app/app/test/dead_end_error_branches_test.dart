import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/core/platform/error_retry.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/live_matches_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

/// Review #3, findings 18 (real) and 16 (REFUTED - see below).
///
/// Both providers are plain FutureProviders, not autoDispose, so an AsyncError
/// is cached for the process: backing out and re-entering re-watches the same
/// errored element and shows the same line. Whether that is a dead end depends
/// entirely on whether the screen offers ANY way to re-read.
///
/// Every test here disables riverpod's automatic retry
/// (`ProviderScope(retry: ...)`). Without that a failing provider is re-read
/// about a dozen times on its own backoff schedule, and a test counting reads
/// measures the backoff instead of the user's recovery - the first version of
/// this file reported 11 reads before a single gesture.
class _Boom implements Exception {
  @override
  String toString() => 'Exception: boom';
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    // ── finding 18: a dead end, and worse than the empty case ──────────────
    testWidgets('Start a match offers a retry when the team read fails on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var reads = 0;
        await tester.pumpWidget(ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            myTeamsProvider.overrideWith((ref) async {
              reads++;
              throw _Boom();
            }),
          ],
          child: const MaterialApp(home: StartMatchScreen()),
        ));
        await tester.pumpAndSettle();
        expect(reads, 1, reason: 'sanity: the team read failed exactly once');

        expect(find.byType(ErrorRetry), findsOneWidget,
            reason: 'a FAILED read showed strictly LESS than an EMPTY read: '
                'the "Create a team" escape hatch lives in the data branch, so '
                'this branch had no dropdown and no button, while "Next: '
                'squads" stayed enabled and answered "Still needed: your team" '
                '- naming a field the screen never drew a control for. And '
                'unlike Watch live there is no RefreshIndicator here to fall '
                'back on: this is a form, not a list');

        await tester.tap(find.descendant(
            of: find.byType(ErrorRetry), matching: find.text('Retry')));
        await tester.pumpAndSettle();
        expect(reads, greaterThan(1),
            reason: 'the only in-app cure was to leave the tab entirely, go to '
                'Profile -> My teams and retry THERE, which nothing on this '
                'screen suggests');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // ── finding 16: REFUTED, and pinned so it stays refuted ────────────────
    /// The finding said Watch live's error branch is a dead end because the
    /// drag never reaches the RefreshIndicator: one short child does not
    /// overflow, and `ScrollPhysics.shouldAcceptUserOffset` returns
    /// `pixels != 0 || minScrollExtent != maxScrollExtent`, which is false.
    ///
    /// That is true of the DEFAULT physics and this ListView does not have
    /// them. A vertical ListView with no controller is `primary`, and
    /// ScrollView then supplies AlwaysScrollableScrollPhysics, whose
    /// shouldAcceptUserOffset returns true unconditionally. Driven here rather
    /// than argued: the fling re-reads the provider.
    ///
    /// So the allowlist reason in error_branches_have_retry_test.dart is
    /// correct and no ErrorRetry is needed. What was missing is this test -
    /// the excuse rests on a property nothing checked, and handing that
    /// ListView a controller (or `primary: false`) would silently take the
    /// only recovery away.
    testWidgets('Watch live: the pull-to-refresh its excuse rests on really '
        'does fire on the error branch on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var reads = 0;
        await tester.pumpWidget(ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            liveMatchesProvider.overrideWith((ref) async {
              reads++;
              throw _Boom();
            }),
          ],
          child: const MaterialApp(home: LiveMatchesScreen()),
        ));
        await tester.pumpAndSettle();
        expect(reads, 1, reason: 'sanity: the list was read and it failed');
        expect(find.byType(RefreshIndicator), findsOneWidget);

        await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(reads, greaterThan(1),
            reason: 'the error branch is excused from the ErrorRetry sweep on '
                'the grounds that pull-to-refresh IS its retry. If this ever '
                'stops being true the screen becomes a genuine dead end, '
                'because the excuse will still be sitting in the allowlist');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Watch live: the same drag works on the EMPTY branch on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var reads = 0;
        await tester.pumpWidget(ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            liveMatchesProvider.overrideWith((ref) async {
              reads++;
              return const <Map<String, dynamic>>[];
            }),
          ],
          child: const MaterialApp(home: LiveMatchesScreen()),
        ));
        await tester.pumpAndSettle();
        expect(find.text('No live matches right now.'), findsOneWidget);

        await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(reads, greaterThan(1),
            reason: 'somebody opening Watch live before the first match of the '
                'day starts is the most likely person to pull down');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
