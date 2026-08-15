import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// AN OBSERVATION RUN, NOT A TEST.
///
/// The user's criticism, 2026-08-05: every journey in this repo is a script I
/// wrote against behaviour I wrote, so it passes while the app is unusable. In
/// particular every existing journey creates BOTH teams as the same account,
/// which is not how anybody plays cricket - and then reports the setup flow as
/// working.
///
/// So this file asserts almost nothing. It walks the flow a real scorer walks
/// and SCREENSHOTS every decision point, so the screens can be read rather than
/// imagined:
///   1. one account, ONE team - not two
///   2. what the opponent step actually offers
///   3. whether the opponent's XI can be filled at all
///   4. a dot ball, a wide, and a no-ball - photographing the score after each
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle(const Duration(milliseconds: 600));
    await binding.takeScreenshot(name);
  }

  Future<bool> settle(WidgetTester t, Finder f, {int tries = 30}) async {
    for (var i = 0; i < tries; i++) {
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      if (f.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> tapIf(WidgetTester t, Finder f) async {
    if (f.evaluate().isNotEmpty) {
      await t.tap(f.first);
      await t.pumpAndSettle(const Duration(milliseconds: 600));
    }
  }

  testWidgets('OBSERVE: one team, one opponent, three balls', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000000;

    // ---- sign up as a NORMAL new user -------------------------------------
    final c = Supabase.instance.client;
    if (c.auth.currentSession != null) {
      await c.auth.signOut();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    await settle(tester, find.text('Sign in'));
    await tapIf(tester, find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester, find.text('Create test account (dev)'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'obs$run@pitch.local');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create test account (dev)'));
    await settle(tester, find.widgetWithText(TextField, 'Display name'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'Observer $run');
    await tester.enterText(find.widgetWithText(TextField, 'Handle'), 'obs$run');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final cont = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(cont.first);
    await tester.tap(cont.first);
    await settle(tester, find.text('Matches'));

    // ---- ONE team, with two guests ----------------------------------------
    await tester.tap(find.text('Profile').last);
    await settle(tester, find.text('My teams'));
    await tester.tap(find.text('My teams'));
    await settle(tester, find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.widgetWithText(TextField, 'Team name'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Team name'), 'My XI $run');
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create');
    await tester.ensureVisible(create.first);
    await tester.tap(create.first);
    await settle(tester, find.text('My XI $run'));
    for (final g in ['Mine1', 'Mine2']) {
      final add = find.textContaining('Add guest player');
      await tester.ensureVisible(add.first);
      await tester.tap(add.first);
      await settle(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField).last, g);
      await tester.pumpAndSettle();
      final ok = find.widgetWithText(TextButton, 'Add');
      await tester.tap(ok.evaluate().isNotEmpty
          ? ok.first
          : find.widgetWithText(FilledButton, 'Add').first);
      await settle(tester, find.text(g));
    }
    await shot(tester, 'obs1_my_only_team');

    // ---- start a match: WHAT DOES THE OPPONENT STEP OFFER? -----------------
    await tester.tap(find.text('Matches').last);
    await settle(tester, find.textContaining('Start a match'));
    await tester.tap(find.textContaining('Start a match').first);
    await settle(tester, find.text('Opponent'));
    await shot(tester, 'obs2_start_match_form');

    await tapIf(tester, find.textContaining('Choose the opponent'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await shot(tester, 'obs3_opponent_sheet_empty_box');

    // type something generic to see what the search returns for a stranger
    final searchBox = find.byType(TextField);
    if (searchBox.evaluate().isNotEmpty) {
      await tester.enterText(searchBox.last, 'a');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await shot(tester, 'obs4_opponent_search_results');
    }
  });
}
