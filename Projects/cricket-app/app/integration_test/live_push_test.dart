import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// LIVE-PUSH E2E (Slice 3's headline claim): with the real viewer open, balls
/// recorded via DIRECT RPC (no UI action, no provider invalidation) must appear
/// on screen through the broadcast chain alone - DB trigger -> realtime ->
/// private channel -> re-fold. Then completing the match must surface the
/// result banner live (the RT-2 matches trigger), without reopening.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  /// Pump until [until] appears - the wait is the realtime round-trip budget.
  Future<bool> waitFor(WidgetTester tester, Finder until,
      {int tries = 40}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      if (until.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  testWidgets('recorded balls + the result push to an open viewer',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- Arrange: account through the UI (the AuthGate must see the profile
    // created through its own flow), then match setup via API - this gate
    // tests realtime, not forms.
    final c = Supabase.instance.client;
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;
    await waitFor(tester, find.text('Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in').first);
    await waitFor(tester, find.text('Create test account (dev)'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'live$run@pitch.local');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create test account (dev)'));
    await waitFor(tester, find.text('Display name'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'Live Scorer');
    await tester.enterText(
        find.widgetWithText(TextField, 'Handle'), 'live$run');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    expect(await waitFor(tester, find.text('Matches')), isTrue,
        reason: 'onboarding should land in the shell');

    final teamA = await c.rpc('create_team',
        params: {'_name': 'Push A $run', '_city': 'X'}) as String;
    final teamB = await c.rpc('create_team',
        params: {'_name': 'Push B $run', '_city': 'X'}) as String;
    final bat1 = await c.rpc('add_guest_member',
        params: {'_team_id': teamA, '_guest_name': 'Bat One'}) as String;
    final bat2 = await c.rpc('add_guest_member',
        params: {'_team_id': teamA, '_guest_name': 'Bat Two'}) as String;
    final bowl = await c.rpc('add_guest_member',
        params: {'_team_id': teamB, '_guest_name': 'Bowl One'}) as String;
    final bowl2 = await c.rpc('add_guest_member',
        params: {'_team_id': teamB, '_guest_name': 'Bowl Two'}) as String;
    final matchId = await c.rpc('create_match', params: {
      '_team_a': teamA,
      '_team_b': teamB,
      '_overs': 1,
    }) as String;
    for (final m in [bat1, bat2]) {
      await c.rpc('add_squad_member', params: {
        '_match_id': matchId,
        '_team_id': teamA,
        '_team_member_id': m
      });
    }
    // start_innings now validates BOTH squads carry >= 2 players (SCOR-10)
    for (final m in [bowl, bowl2]) {
      await c.rpc('add_squad_member', params: {
        '_match_id': matchId,
        '_team_id': teamB,
        '_team_member_id': m
      });
    }
    final inningsId = await c.rpc('start_innings', params: {
      '_match_id': matchId,
      '_innings_number': 1,
      '_batting_team': teamA,
      '_bowling_team': teamB,
      '_opening_striker': bat1,
      '_opening_non_striker': bat2,
    }) as String;

    // ---- Open the viewer via the UI (Matches -> Watch live -> our match) ----
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('Matches').first);
    await waitFor(tester, find.byIcon(Icons.sensors));
    await tester.tap(find.byIcon(Icons.sensors));
    final tile = find.textContaining('Push A $run');
    expect(await waitFor(tester, tile), isTrue,
        reason: 'the live match should be listed');
    await tester.tap(tile.first);
    expect(await waitFor(tester, find.text('0/0')), isTrue,
        reason: 'the viewer opens at 0/0');
    await shot(tester, 'lp1_viewer_open');

    // ---- Act 1: record a boundary via RPC ONLY - no UI, no invalidation ----
    await c.rpc('record_ball', params: {
      '_innings_id': inningsId,
      '_bowler_id': bowl,
      '_runs_off_bat': 4,
    });
    // the score must change via the broadcast alone
    final pushed = await waitFor(tester, find.text('4/0'));
    await shot(tester, 'lp2_ball_pushed');
    expect(pushed, isTrue,
        reason: 'RT-1/RT-3: the recorded ball must push to the open viewer');

    // ---- Act 2: complete the match via RPC - the result must appear live ----
    await c.rpc('set_match_result', params: {
      '_match_id': matchId,
      '_result_type': 'abandoned',
      '_note': 'Rained off',
    });
    final resultPushed =
        await waitFor(tester, find.textContaining('Rained off'));
    await shot(tester, 'lp3_result_pushed');
    expect(resultPushed, isTrue,
        reason: 'RT-2: completing the match must push the result banner live');
  });
}
