import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Human walkthrough of the tournament UI on the real app: seed a fully-played
/// 2-group tournament via the RPCs, then drive Matches -> Tournaments -> the
/// public page and tab through Table / Fixtures / Bracket / Leaders, plus the
/// Create form. Verifies the screens render real backend data on the sim.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle(const Duration(milliseconds: 600));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester t, Finder until, {int tries = 25}) async {
    for (var i = 0; i < tries; i++) {
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('tournament create + public page (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
    }

    // ---- seed a fully-played tournament via the RPCs ----
    Future<String> team(String n) async {
      final id = await c.rpc('create_team', params: {'_name': n, '_city': 'Mumbai'}) as String;
      await c.rpc('add_guest_member', params: {'_team_id': id, '_guest_name': '$n-1'});
      await c.rpc('add_guest_member', params: {'_team_id': id, '_guest_name': '$n-2'});
      return id;
    }

    Future<void> score(String matchId) async {
      final m = await c.from('matches').select('team_a_id, team_b_id').eq('id', matchId).single();
      final am = await c.from('team_members').select('id').eq('team_id', m['team_a_id'] as String).limit(2);
      final bm = await c.from('team_members').select('id').eq('team_id', m['team_b_id'] as String).limit(2);
      final a = (am as List).map((e) => e['id'] as String).toList();
      final b = (bm as List).map((e) => e['id'] as String).toList();
      final i1 = await c.rpc('start_innings', params: {'_match_id': matchId, '_innings_number': 1,
        '_batting_team': m['team_a_id'], '_bowling_team': m['team_b_id'], '_opening_striker': a[0], '_opening_non_striker': a[1]}) as String;
      await c.from('deliveries').insert([
        for (var s = 1; s <= 6; s++)
          {'innings_id': i1, 'seq': s, 'bowler_id': b[0], 'striker_id': a[0], 'non_striker_id': a[1], 'runs_off_bat': 4},
      ]);
      final i2 = await c.rpc('start_innings', params: {'_match_id': matchId, '_innings_number': 2,
        '_batting_team': m['team_b_id'], '_bowling_team': m['team_a_id'], '_opening_striker': b[0], '_opening_non_striker': b[1]}) as String;
      await c.from('deliveries').insert([
        for (var s = 1; s <= 3; s++)
          {'innings_id': i2, 'seq': s, 'bowler_id': a[0], 'striker_id': b[0], 'non_striker_id': b[1], 'runs_off_bat': 1},
      ]);
      await c.rpc('set_match_result', params: {'_match_id': matchId, '_result_type': 'win_by_runs', '_winner_team_id': m['team_a_id']});
    }

    final ts = DateTime.now().microsecondsSinceEpoch;
    final a1 = await team('A1-$ts'), a2 = await team('A2-$ts'),
        b1 = await team('B1-$ts'), b2 = await team('B2-$ts');
    final tid = await c.rpc('create_tournament', params: {'_name': 'Sim Cup $ts',
      '_overs': 20, '_group_count': 2, '_qualifiers_per_group': 2, '_city': 'Mumbai'}) as String;
    await c.rpc('add_tournament_team', params: {'_tournament_id': tid, '_team_id': a1, '_group_label': 'A'});
    await c.rpc('add_tournament_team', params: {'_tournament_id': tid, '_team_id': a2, '_group_label': 'A'});
    await c.rpc('add_tournament_team', params: {'_tournament_id': tid, '_team_id': b1, '_group_label': 'B'});
    await c.rpc('add_tournament_team', params: {'_tournament_id': tid, '_team_id': b2, '_group_label': 'B'});
    await c.rpc('generate_group_fixtures', params: {'_tournament_id': tid});
    for (final f in await c.from('tournament_matches').select('match_id').eq('tournament_id', tid).eq('stage', 'group')) {
      await score(f['match_id'] as String);
    }
    await c.rpc('generate_playoffs', params: {'_tournament_id': tid});
    for (final f in await c.from('tournament_matches').select('match_id').eq('tournament_id', tid).eq('stage', 'semifinal')) {
      await score(f['match_id'] as String);
    }
    await c.rpc('advance_playoffs', params: {'_tournament_id': tid}); // build final
    for (final f in await c.from('tournament_matches').select('match_id').eq('tournament_id', tid).eq('stage', 'final')) {
      await score(f['match_id'] as String);
    }
    await c.rpc('advance_playoffs', params: {'_tournament_id': tid}); // crown champion

    // ---- drive the UI: Matches -> Tournaments ----
    await settle(tester, find.text('Matches'));
    await tester.tap(find.text('Matches').last);
    await settle(tester, find.byTooltip('Tournaments'));
    await tester.tap(find.byTooltip('Tournaments'));
    await settle(tester, find.textContaining('Sim Cup'));
    await shot(tester, '70_tournaments_list');

    // open the public page for our seeded tournament
    await tester.tap(find.textContaining('Sim Cup').first);
    await settle(tester, find.text('Table'));
    await shot(tester, '71_table');
    await tester.tap(find.text('Fixtures'));
    await settle(tester, find.text('Semifinals'));
    await shot(tester, '72_fixtures');
    await tester.tap(find.text('Bracket'));
    await tester.pumpAndSettle();
    await shot(tester, '73_bracket');
    await tester.tap(find.text('Leaders'));
    await settle(tester, find.widgetWithText(ChoiceChip, 'Runs'));
    await shot(tester, '74_leaders');

    // the page shows real data: a champion banner + NRR in the table
    expect(find.textContaining('Champions'), findsOneWidget);

    // ---- the create form renders ----
    await tester.pageBack();
    await settle(tester, find.byIcon(Icons.add));
    // (back on the list) open create - FAB on Android, app-bar add on iOS
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.widgetWithText(FilledButton, 'Create tournament'));
    await shot(tester, '75_create_form');
    expect(find.text('Ball type'), findsOneWidget);
  });
}
