import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/transfer_scorer_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('transfer screen lists eligible scorers on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchScorerCandidatesProvider.overrideWith(
                (ref, id) async => [
                  {'profile_id': 'u1', 'name': 'Rahul K.'},
                  {'profile_id': 'u2', 'name': 'Imran K.'},
                ],
              ),
            ],
            child: const MaterialApp(
              home: TransferScorerScreen(matchId: 'm1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Rahul K.'), findsOneWidget);
        expect(find.text('Imran K.'), findsOneWidget);
        expect(find.textContaining('lose write'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('transfer screen empty state on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchScorerCandidatesProvider.overrideWith((ref, id) async => []),
            ],
            child: const MaterialApp(
              home: TransferScorerScreen(matchId: 'm1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('No other registered players'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
