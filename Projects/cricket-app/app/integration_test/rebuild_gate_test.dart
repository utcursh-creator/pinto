import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:pitch_app/main.dart' as app;

/// THE REBUILD ACCEPTANCE GATE (the user's standard after the friend cold-test):
/// from scratch, entirely through the UI - new account -> profile with handle ->
/// two named teams with guests -> an A-vs-B match -> full 2-innings scoring ->
/// innings break -> chase -> result -> match history shows "A v B - result".
/// Runs against live local Supabase on a simulator/emulator.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester tester, Finder until,
      {int tries = 30, String label = 'step'}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
    // Evidence on failure: capture where the UI actually is, then fail loudly.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot('timeout_$label');
    fail('settle timed out waiting for $until at "$label"');
  }

  /// Taps a run button and skips the wagon-wheel prompt if it appears.
  Future<void> tapRun(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(OutlinedButton, label).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 700));
    final skip = find.text('Skip');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    }
  }

  testWidgets('from-scratch playthrough: account -> teams -> 2-innings match -> result',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    // ---- 1. Fresh account via the UI (anon Discover -> Sign in -> dev shim) ----
    await settle(tester, find.text('Sign in'), label: 'anon_signin_cta');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in').first);
    await settle(tester, find.text('Create test account (dev)'), label: 'signin_screen');
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'gate$run@pitch.local');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create test account (dev)'));

    // ---- 2. Create profile (name + unique handle) ----
    await settle(tester, find.text('Display name'), label: 'create_profile');
    await shot(tester, 'g01_create_profile');
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'Gate Tester');
    await tester.enterText(
        find.widgetWithText(TextField, 'Handle'), 'gate$run');
    // let the live handle_available check resolve
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settle(tester, find.text('Matches'), label: 'shell');
    expect(find.text('Matches'), findsWidgets,
        reason: 'onboarding should land in the shell');

    // ---- 3. Two named teams, one guest each ----
    // Assumes we START on the My teams screen; ends back there.
    Future<void> createTeam(String name, String guest) async {
      await settle(tester, find.text('Create team'), label: 'my_teams');
      await tester.tap(find.widgetWithText(FilledButton, 'Create team').first);
      await settle(tester, find.text('Team name'), label: 'create_team_screen');
      await tester.enterText(
          find.widgetWithText(TextField, 'Team name'), name);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      // lands on the team page
      await settle(tester, find.text('Add guest player'), label: 'team_page');
      await tester.tap(find.text('Add guest player'));
      await settle(tester, find.text('Guest name'), label: 'guest_dialog');
      await tester.enterText(
          find.widgetWithText(TextField, 'Guest name'), guest);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester, find.text(guest), label: 'guest_on_roster');
      expect(find.text(guest), findsWidgets,
          reason: 'the guest should appear on the roster');
      // back to My teams for the next creation
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Navigate once: Profile tab -> My teams.
    await tester.tap(find.text('Profile').first);
    await settle(tester, find.text('My teams'), label: 'profile_screen');
    await tester.tap(find.text('My teams'));

    await createTeam('Lions $run', 'Ravi A');
    await shot(tester, 'g02_team_a');
    await createTeam('Kings $run', 'Ravi B');
    await shot(tester, 'g03_team_b');

    // ---- 4. Start an A-vs-B 1-over match ----
    await tester.tap(find.text('Matches').first);
    // Cupertino presentation: start-match is the app-bar + icon (no FAB).
    await settle(tester, find.byIcon(Icons.add), label: 'matches_tab');
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.text('Choose your team'), label: 'start_match');
    await tester.tap(find.text('Choose your team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lions $run').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose the opponent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kings $run').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Overs'), '1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: squads'));

    // ---- 5. Squads: 2 per side ----
    await settle(tester, find.textContaining('Next: toss'), label: 'squads');
    await shot(tester, 'g04_squads');
    // Gate Tester appears on both rosters; guests disambiguate the sides.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Gate Tester').first);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ravi A').first);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Gate Tester').last);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ravi B').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Next: toss'));

    // ---- 6. Toss + openers (Lions bat) ----
    await settle(tester, find.text('Toss winner'), label: 'toss');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Lions $run'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bat'));
    await tester.pumpAndSettle();
    final choose = find.text('Choose');
    await tester.tap(choose.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gate Tester').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi A').last);
    await tester.pumpAndSettle();
    await shot(tester, 'g05_toss');
    await tester.tap(find.text('Start match'));

    // ---- 7. Innings 1: pick bowler, six singles (1-over innings) ----
    await settle(tester, find.text('Pick'), label: 'console');
    await tester.tap(find.text('Pick'));
    await settle(tester, find.text('Select bowler'), label: 'bowler_sheet');
    await tester.tap(find.text('Ravi B').last);
    await tester.pumpAndSettle();
    // Keep tapping singles until the over ends the 1-over innings - a tap can
    // be absorbed while the previous ball is in flight, so verify, don't count.
    for (var i = 0;
        i < 14 && find.text('Innings break').evaluate().isEmpty;
        i++) {
      await tapRun(tester, '1');
    }
    await settle(tester, find.text('Innings break'), label: 'innings_break');
    expect(find.text('Innings break'), findsOneWidget);
    expect(find.textContaining('Target: 7'), findsOneWidget,
        reason: '6 singles -> chase target 7');
    await shot(tester, 'g06_innings_break');

    // ---- 8. 2nd innings: openers -> chase 7 ----
    await tester.tap(find.text('Start 2nd innings'));
    await settle(tester, find.text('Start chase'), label: 'chase_openers');
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gate Tester').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start chase'));
    await settle(tester, find.text('Pick'), label: 'console');
    await tester.tap(find.text('Pick'));
    await settle(tester, find.text('Select bowler'), label: 'bowler_sheet');
    await tester.tap(find.text('Ravi A').last);
    await tester.pumpAndSettle();
    // chase header shows the requirement
    expect(find.textContaining('Need 7 off'), findsOneWidget);
    await shot(tester, 'g07_chase');
    // Chase with boundaries until the fold declares the match over.
    for (var i = 0;
        i < 10 && find.text('Match over').evaluate().isEmpty;
        i++) {
      await tapRun(tester, '6');
    }

    // ---- 9. Match over: computed result -> finish -> viewer banner ----
    await settle(tester, find.text('Match over'), label: 'match_over');
    expect(find.textContaining('Kings $run won by'), findsOneWidget,
        reason: 'the fold computes the chase win');
    await shot(tester, 'g08_match_over');
    await tester.tap(find.text('Finish match & view scorecard'));
    await settle(tester, find.textContaining('won by'), label: 'viewer_result');
    expect(find.textContaining('Kings $run won by'), findsWidgets,
        reason: 'the viewer shows the result banner');
    await shot(tester, 'g09_viewer_result');

    // ---- 10. Match history: A v B + result in the Matches tab ----
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matches').first);
    await settle(tester, find.text('Completed'), label: 'history');
    expect(find.text('Lions $run  v  Kings $run'), findsOneWidget,
        reason: 'history shows real names, never Team A/Team B');
    expect(find.textContaining('won by'), findsWidgets);
    await shot(tester, 'g10_history');
  });
}
