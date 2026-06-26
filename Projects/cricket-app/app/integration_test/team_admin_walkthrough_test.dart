import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Verifies the team-admin additions render on the real app: the "Invite a
/// player" link action (create_team_invite) and the "Home ground" row
/// (set/team_home_location). Also exercises the create_team_invite RPC live.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester tester, Finder until, {int tries = 25}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('team admin sees invite + home-ground controls (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
    }

    // Profile -> My teams -> first team.
    await settle(tester, find.text('Profile'));
    await tester.tap(find.text('Profile').last);
    await settle(tester, find.text('My teams'));
    await tester.tap(find.text('My teams'));
    await settle(tester, find.byType(ListTile));
    // open the first team
    await tester.tap(find.textContaining('United').first);
    await settle(tester, find.text('Home ground'));

    expect(find.text('Invite a player'), findsOneWidget);
    expect(find.text('Home ground'), findsOneWidget);
    expect(find.text('Add guest player'), findsOneWidget);
    await shot(tester, '50_team_admin');

    // the invite RPC the button calls actually works against live Supabase
    final teamId = (await c
        .from('team_members')
        .select('team_id, teams!inner(name)')
        .eq('profile_id', c.auth.currentUser!.id)
        .limit(1)
        .single())['team_id'] as String;
    final token = await c.rpc('create_team_invite', params: {'_team_id': teamId});
    expect(token, isA<String>());
    expect((token as String).length, greaterThan(20));
  });
}
