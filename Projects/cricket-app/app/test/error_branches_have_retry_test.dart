import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/matches/presentation/matches_screen.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';

/// Whole-system review #2 (2026-07-28), finding 39: a screen that fails once
/// stays failed for the life of the app.
///
/// Every list here is a non-autoDispose FutureProvider, so an AsyncError is
/// CACHED. `error: (e, _) => Center(child: Text(...))` gives the user nothing
/// to tap, and switching tabs or navigating away and back re-watches the same
/// errored element without re-running the query. A phone that lost signal in a
/// tunnel shows "Could not load matches." until the app is killed - signal
/// coming back does not fix it.
///
/// The rule: an error branch either offers a retry, or is on the list below
/// with a reason. Not a style preference - without one of the two, the screen
/// is dead.
void main() {
  /// Error branches that deliberately do NOT carry their own retry, each keyed
  /// by FILE AND LINE-ANCHOR plus the reason.
  ///
  /// This list used to be keyed on code SHAPES - 'error: (e, _) => Center(\n',
  /// 'error: (e, _) => Text(humanError(e))'. Review #3 caught what that means
  /// and it is worse than it sounds: those shapes are what a DELETED ErrorRetry
  /// leaves behind, so the allowlist excused exactly the regression the guard
  /// exists to catch. Proved it by deleting the retry from My teams - a screen
  /// with no behavioural test - and the whole suite stayed green.
  ///
  /// Keyed on the file now, so an excuse covers the one place it was written
  /// for. A new bare branch in an already-excused file still has to be added
  /// deliberately, with its own reason.
  const allowed = <String, String>{
    'lib/src/core/auth/auth_gate.dart':
        'not a widget - this is the gate enum itself; the splash screen it '
            'routes to owns the retry',
    'lib/src/features/teams/presentation/invite_accept_screen.dart':
        'an invite preview that fails still renders the invite screen, which '
            'has its own Accept action - there is nothing to re-read',
    'lib/src/features/discover/presentation/post_detail_screen.dart':
        'the replies list, inline under a post that loaded fine; posting a '
            'reply re-reads them. The screen BODY has its own ErrorRetry',
    'lib/src/features/discover/presentation/new_post_composer.dart':
        'the team picker is optional - the post can be published without one',
    'lib/src/features/scoring/presentation/start_match_screen.dart':
        'inline beside the opponent picker and in a past-opponents sheet the '
            'user can close and reopen',
    'lib/src/features/scoring/presentation/match_squads_screen.dart':
        'one roster section, whose screen-level branch has the retry',
    'lib/src/features/teams/presentation/team_page_screen.dart':
        'the home-ground strip - a decoration on a page that loaded; the team '
            'and roster branches both have retries',
    'lib/src/features/scoring/presentation/live_matches_screen.dart':
        'already inside a RefreshIndicator AND scrollable, so pull-to-refresh '
            'IS the retry',
    'lib/src/features/discover/presentation/search_screen.dart':
        'uses AppEmpty, which carries its own action',
    'lib/src/features/scoring/presentation/scoring_console_screen.dart':
        'uses AppEmpty, which carries its own action',
    'lib/src/features/tournaments/presentation/join_tournament_screen.dart':
        'the team picker on the join screen has its own ErrorRetry; this is '
            'the inline hint beside it',
  };


  test('every async error branch offers a way to try again', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('error: (')) continue;
        // the branch body: this line plus the next few
        final body = lines.sublist(i, (i + 4).clamp(0, lines.length)).join('\n');
        if (body.contains('ErrorRetry') || body.contains('AppEmpty')) continue;
        final excused = allowed.containsKey(entity.path);
        if (!excused) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'These error branches cache a failure with nothing to tap, so '
            'the screen stays dead for the rest of the session. Give them an '
            'ErrorRetry that invalidates the provider, or add them to the '
            'allowlist in this test WITH a reason:\n${offenders.join('\n')}');
  });

  // A guard on source alone proves nothing about whether the button works.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the Matches retry actually re-runs the query on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var attempts = 0;
        await tester.pumpWidget(ProviderScope(
          // Riverpod 3 retries a failed provider on its own with a growing
          // backoff. That is a safety net, not an answer: the user is still
          // looking at "Could not load matches." with nothing to tap, and the
          // gap between attempts only gets longer. Disabled here so the test
          // measures the BUTTON rather than the backoff.
          retry: (_, _) => null,
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            myMatchesProvider.overrideWith((ref) async {
              attempts++;
              if (attempts <= 1) throw Exception('no signal');
              return const <Map<String, dynamic>>[];
            }),
          ],
          child: const MaterialApp(home: MatchesScreen()),
        ));
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not load matches'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(attempts, 2,
            reason: 'the provider caches its failure, so the retry has to '
                'INVALIDATE it - re-watching the same errored element is what '
                'made coming back to the tab useless');
        expect(find.textContaining('Could not load matches'), findsNothing,
            reason: 'and the screen recovers');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
