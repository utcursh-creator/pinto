import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/search_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('search prompts for input then lists players + teams on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchProvider.overrideWith((ref, q) async => [
                  {
                    'kind': 'player',
                    'id': 'p1',
                    'name': 'Rohit Sharma',
                    'subtitle': null,
                    'photo_url': null,
                  },
                  {
                    'kind': 'team',
                    'id': 't1',
                    'name': 'Mumbai Strikers',
                    'subtitle': 'Mumbai',
                    'photo_url': null,
                  },
                ]),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // before typing, the min-length hint shows
      expect(find.text('Type at least 2 letters to search.'), findsOneWidget);
      // type a query -> the overridden results render, labelled by kind
      await tester.enterText(find.byType(TextField), 'rohit');
      await tester.pumpAndSettle();
      expect(find.text('Rohit Sharma'), findsOneWidget);
      expect(find.text('Mumbai Strikers'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget);
      expect(find.textContaining('Team'), findsWidgets);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
