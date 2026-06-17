import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/discover_screen.dart';
import 'package:pitch_app/src/features/discover/presentation/new_post_composer.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/messages/presentation/dm_inbox_screen.dart';

void main() {
  testWidgets('Discover feed shows a post with flair + distance', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoverFeedProvider.overrideWith(
            (ref, q) async => [
              <String, dynamic>{
                'post_id': 'p1',
                'mode': 'team_seeking_players',
                'flair': 'loser_pays',
                'title': 'Need 2 batters',
                'description': 'Sunday 8am',
                'approx_m': 1200,
              },
            ],
          ),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Need 2 batters'), findsOneWidget);
    expect(find.text('Loser pays'), findsWidgets);
    expect(find.text('1.2 km'), findsOneWidget);
  });

  testWidgets('New post composer requires a flair', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [myTeamsProvider.overrideWith((ref) async => [])],
        child: const MaterialApp(home: NewPostComposer()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a flair.'), findsOneWidget);
  });

  testWidgets('DM inbox lists a conversation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dmInboxProvider.overrideWith(
            (ref) async => [
              <String, dynamic>{
                'thread_id': 't1',
                'other': {'display_name': 'Rahul K.'},
                'preview': 'Yes Sunday works',
              },
            ],
          ),
        ],
        child: const MaterialApp(home: DmInboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rahul K.'), findsOneWidget);
    expect(find.text('Yes Sunday works'), findsOneWidget);
  });
}
