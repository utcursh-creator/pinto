import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/tournaments/presentation/create_tournament_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('create screen offers free overs + venue + dates on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CreateTournamentScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // TOUR-3: no more capped 10/15/20 segmented control - a free overs field.
      expect(find.widgetWithText(TextField, 'Overs per match'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Venue / ground (optional)'),
          findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('create rejects overs out of the 5-50 range on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CreateTournamentScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Tournament name'), 'Cup');
      await tester.enterText(
          find.widgetWithText(TextField, 'Overs per match'), '99');
      final createBtn = find.widgetWithText(FilledButton, 'Create tournament');
      // The form is a lazily-built ListView, so in the 600px test viewport the
      // submit button may not be INSTANTIATED yet - ensureVisible then throws
      // "No element". This test was passing by a one-line margin and broke the
      // moment a hint above it wrapped. Scroll it into existence first.
      await tester.scrollUntilVisible(createBtn, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Overs must be a number from 5 to 50'),
          findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
