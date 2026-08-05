import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/transfer_scorer_screen.dart';

/// Whole-system review #2 (2026-07-28), findings 44, 49, 68 and 76: four places
/// where the app does nothing and says nothing.
///
/// Each is an empty `catch`, a bare `return`, or a missing timeout. They are
/// grouped because the failure mode is identical from the user's side: they tap
/// something important, the app looks like it worked, and it did not.
void main() {
  /// 44: `Geolocator.getCurrentPosition()` with no LocationSettings waits
  /// FOREVER for a fix. Indoors, in a stadium basement, or on a cold-start GPS,
  /// "Use my current location" sets _busy, turns the button into a disabled
  /// spinner, and neither the `on LocationException` nor the generic catch ever
  /// runs, because the future never completes. There is no cancel: the spinner
  /// runs until the screen is popped.
  ///
  /// The iOS simulator serves a canned location in milliseconds, which is
  /// exactly why every verification pass on the sim looked green.
  test('the GPS lookup gives up instead of spinning forever', () {
    final src =
        File('lib/src/features/discover/data/location_service.dart')
            .readAsStringSync();
    final call = src.substring(src.indexOf('getCurrentPosition'));
    final args = call.substring(0, call.indexOf(';'));
    expect(args, contains('timeLimit'),
        reason: 'without a time limit the future never completes, so the '
            'error path cannot run and the spinner has no end:\n$args');
    expect(src, contains('TimeoutException'),
        reason: 'and the timeout has to be turned into something the screen '
            'can show - geolocator throws TimeoutException, which is not a '
            'LocationException and would otherwise reach the user as a raw '
            'type name');
  });

  /// 49: the keystone discover -> match bridge DMs the poster after creating
  /// the match, and the whole block was `catch (_) {}`. If the DM rate limit
  /// bites, or the poster has blocked the proposer, the proposer is carried on
  /// to the squad wizard believing the opponent was told. Both sides then wait.
  /// The schedule write above it was swallowed the same way, so the date the
  /// user carried over from the post vanished silently.
  test('the propose-a-match bridge does not swallow its two side effects', () {
    final src = File(
            'lib/src/features/scoring/presentation/start_match_screen.dart')
        .readAsStringSync();

    // KEYED ON THE SHAPE, NOT ON ONE OLD COMMENT. The first version of this
    // test asserted the ABSENCE of two exact comment strings, which review #3
    // caught: I re-swallowed the schedule write as `catch (_) {/* non-fatal */}`
    // - different wording, same bug - and the test stayed green. An empty catch
    // is an empty catch whatever is written inside it.
    final emptyCatch = RegExp(r'catch\s*\(_\)\s*\{\s*(/\*.*?\*/)?\s*\}',
        dotAll: true);
    final offenders = emptyCatch
        .allMatches(src)
        .map((m) => m.group(0)!.replaceAll('\n', ' '))
        .toList();
    expect(offenders, isEmpty,
        reason: 'this screen creates the match AND carries over the date and '
            'DMs the opponent. Both side effects were swallowed whole, so the '
            'proposer walked on believing a conversation was happening when it '
            'was not. No empty catch belongs here:\n${offenders.join('\n')}');

    // and the positive half: the user is told WHICH part did not happen
    expect(src, contains('could not be messaged'),
        reason: 'the match is created either way - the message has to name the '
            'half that failed');
    expect(src, contains('could not be saved'),
        reason: 'and the same for the carried-over date and ground');
  });

  /// 68: `_captureAndShare` returns silently when the boundary or the bytes are
  /// null, and nothing in it is wrapped, so a throw from toImage (a two-innings
  /// card at 3x can exceed the platform's max texture size) or from writing the
  /// file (no space left) is an unhandled async error. The user taps "Share
  /// image" on the scorecard they wanted to post to the team group and
  /// absolutely nothing happens.
  test('share-image failures are reported, including the silent returns', () {
    final src = File(
            'lib/src/features/scoring/presentation/match_viewer_screen.dart')
        .readAsStringSync();
    final start = src.indexOf('Future<void> _captureAndShare');
    expect(start, isNot(-1), reason: 'sanity: the capture path still exists');
    final body = src.substring(start, src.indexOf('\n  }', start));
    expect(body, contains('catch'),
        reason: 'toImage, toByteData and writeAsBytes can all throw, and an '
            'unhandled async error inside onPressed shows the user nothing:'
            '\n$body');
    expect(body.contains('if (boundary == null) return;'), isFalse,
        reason: 'a bare return is the same dead button with no explanation');
    expect(body.contains('if (bytes == null) return;'), isFalse);
  });

  /// 76: handing over scoring pops back to the Matches list without
  /// invalidating anything. myMatchesProvider still holds `eq('scorer_id', me)`
  /// rows from before the transfer, so the match stays listed under Live with a
  /// "Continue scoring" action - and every tap inside the console then fails
  /// with a raw `not authorized` from record_ball.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('handing over scoring drops the match off my list on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final repo = _Repo();
        var listReads = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            matchRepositoryProvider.overrideWithValue(repo),
            matchScorerCandidatesProvider('m1').overrideWith((ref) async => [
                  {'profile_id': 'p2', 'name': 'Priya'},
                ]),
            myMatchesProvider.overrideWith((ref) async {
              listReads++;
              return const <Map<String, dynamic>>[];
            }),
          ],
          child: MaterialApp(
            home: Stack(children: [
              // The Matches tab underneath is what keeps this provider alive -
              // an invalidate with no listener re-runs nothing, so without a
              // watcher this test would pass against any implementation.
              Consumer(builder: (_, ref, _) {
                ref.watch(myMatchesProvider);
                return const SizedBox.shrink();
              }),
              const TransferScorerScreen(matchId: 'm1'),
            ]),
          ),
        ));
        await tester.pumpAndSettle();
        final before = listReads;
        expect(before, 1, reason: 'sanity: the list has been read once');

        await tester.tap(find.text('Priya'));
        await tester.pumpAndSettle();

        expect(repo.transfers, 1, reason: 'sanity: the handover happened');
        expect(listReads, greaterThan(before),
            reason: 'the list is keyed on scorer_id = me and is not '
                'autoDispose, so without an invalidate the handed-over match '
                'stays listed with "Continue scoring" - and every tap in the '
                'console then fails with a raw "not authorized"');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

class _Repo extends Fake implements MatchRepository {
  int transfers = 0;

  @override
  Future<void> transferScorer({
    required String matchId,
    required String newScorerId,
  }) async {
    transfers++;
  }
}
