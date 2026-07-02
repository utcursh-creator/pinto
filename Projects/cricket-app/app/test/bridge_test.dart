import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/post_detail_screen.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

Future<void> _pumpPost(WidgetTester tester, String mode) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(null),
        postRepliesProvider.overrideWith((ref, id) async => []),
        postProvider.overrideWith(
          (ref, id) async => {
            'id': 'p1',
            'author_id': 'someone-else',
            'team_id': 'team-b',
            'mode': mode,
            'flair': 'practice_match',
            'title': 'Need an opponent Sunday',
            'description': '20 overs at Shivaji Park',
            'place_label': 'Dadar',
            'author_name': 'Imran',
            'team_name': 'Dadar CC',
          },
        ),
      ],
      child: const MaterialApp(home: PostDetailScreen(postId: 'p1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('team_seeking_opponent post offers Propose a match on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpPost(tester, 'team_seeking_opponent');
        expect(tester.takeException(), isNull);
        expect(find.text('Propose a match'), findsOneWidget);
        expect(find.text('Message'), findsOneWidget);
        // DISC-5: the detail shows the poster's name + team (via post_detail).
        expect(find.textContaining('Posted by Imran (Dadar CC)'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('non-opponent post hides Propose a match on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpPost(tester, 'team_seeking_players');
        expect(tester.takeException(), isNull);
        expect(find.text('Propose a match'), findsNothing);
        expect(find.text('Message'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('wizard pre-selects the bridged opponent on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              myTeamsProvider.overrideWith((ref) async => []),
              allTeamsProvider.overrideWith(
                (ref) async => [
                  {'id': 'team-b', 'name': 'Dadar CC', 'city': 'Mumbai'},
                ],
              ),
            ],
            child: const MaterialApp(
              home: StartMatchScreen(initialOpponentId: 'team-b'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The opponent dropdown shows the bridged team as selected.
        expect(find.text('Dadar CC'), findsOneWidget);
        final dropdowns =
            tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>));
        expect(dropdowns.any((d) => d.value == 'team-b'), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('bridge pre-fills the overs from the post (MTCH-7) on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              myTeamsProvider.overrideWith((ref) async => []),
              allTeamsProvider.overrideWith(
                (ref) async => [
                  {'id': 'team-b', 'name': 'Dadar CC', 'city': 'Mumbai'},
                ],
              ),
            ],
            child: const MaterialApp(
              home: StartMatchScreen(
                initialOpponentId: 'team-b',
                initialOvers: '15',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // the overs field carries the post's overs, not the default 20
        expect(find.text('15'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
