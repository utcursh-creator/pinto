import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/search_screen.dart';

/// Variant A: user leaves the screen EARLY (mid-retry).
/// Variant B: user stays until the error appears (retries exhausted).
void main() {
  for (final leaveEarly in [true, false]) {
    testWidgets('PROBE leaveEarly=$leaveEarly', (tester) async {
      var offline = true;
      var calls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchProvider.overrideWith((ref, q) async {
              if (q.trim().length < 2) return const [];
              calls++;
              if (offline) {
                throw const SocketException('Failed host lookup: fake');
              }
              return [
                {
                  'kind': 'player',
                  'id': 'p1',
                  'name': 'Rohit Sharma',
                  'subtitle': null,
                  'photo_url': null,
                },
              ];
            }),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SearchScreen()),
                    ),
                    child: const Text('open search'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<void> openSearch() async {
        await tester.tap(find.text('open search'));
        await tester.pumpAndSettle();
      }

      Future<void> typeName() async {
        for (final s in ['r', 'ro', 'roh']) {
          await tester.enterText(find.byType(TextField), s);
          await tester.pump();
        }
      }

      await openSearch();
      await typeName();

      if (leaveEarly) {
        // 5 seconds in - retries still pending.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        Navigator.of(tester.element(find.byType(SearchScreen))).pop();
        await tester.pumpAndSettle();
      } else {
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(seconds: 2));
        }
        debugPrint('  error shown while still on screen: '
            '${find.text('No connection. Check your network and try again.').evaluate().length}');
        Navigator.of(tester.element(find.byType(SearchScreen))).pop();
        await tester.pumpAndSettle();
      }

      // Let any remaining retry timers run out while off-screen, still offline.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 2));
      }

      offline = false;
      final before = calls;
      await openSearch();
      await typeName();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      debugPrint('  RESULT leaveEarly=$leaveEarly calls=$calls (before=$before) '
          'results=${find.text('Rohit Sharma').evaluate().length} '
          'error=${find.text('No connection. Check your network and try again.').evaluate().length}');
    });
  }
}
