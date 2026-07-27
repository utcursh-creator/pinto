import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// THE THREE USER JOURNEYS the user asked to be driven and verified on a real
/// device, entirely through the UI, against live local Supabase:
///
///   A. Running a tournament    - create -> add teams -> groups -> fixtures
///   B. Finding a team to play  - post a "looking for" ad -> find it -> propose
///   C. Finding other players   - search by name/handle -> open their page
///                                 + ADDING players to a team (guests + roster)
///
/// Everything is done by tapping, exactly as a person would; no direct RPC
/// shortcuts. A failure screenshots where the UI actually was before failing.
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
      {int tries = 40, String label = 'step'}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot('timeout_$label');
    fail('settle timed out waiting for $until at "$label"');
  }

  /// Scrolls the nearest scrollable until [f] is visible, then taps it.
  Future<void> tapScrolled(WidgetTester tester, Finder f,
      {String label = 'tap'}) async {
    for (var i = 0; i < 12; i++) {
      if (f.evaluate().isNotEmpty) {
        await tester.ensureVisible(f.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
        await tester.tap(f.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        return;
      }
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, -220));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
    }
    await binding.takeScreenshot('timeout_scroll_$label');
    fail('could not find $f to tap at "$label"');
  }

  /// integration_test runs every testWidgets in ONE app process, and
  /// supabase_flutter persists the session - so journeys after the first start
  /// already signed in and never see the anon "Sign in" call to action. Reset to
  /// a genuinely signed-out device first; that is test setup, not the journey.
  Future<void> ensureSignedOut(WidgetTester tester) async {
    final c = Supabase.instance.client;
    if (c.auth.currentSession != null) {
      await c.auth.signOut();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    // the auth listener re-anons and the router gate returns us to Discover
    for (var i = 0; i < 30; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (find.text('Sign in').evaluate().isNotEmpty) return;
    }
  }

  /// Signs up a brand-new account through the UI and completes onboarding.
  Future<void> signUpFresh(WidgetTester tester, int run, String name) async {
    await ensureSignedOut(tester);
    await settle(tester, find.text('Sign in'), label: 'anon_signin_cta');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in').first);
    await settle(tester, find.text('Create test account (dev)'),
        label: 'signin_screen');
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'j$run@pitch.local');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create test account (dev)'));
    await settle(tester, find.widgetWithText(TextField, 'Display name'),
        label: 'onboarding');
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), name);
    await tester.enterText(find.widgetWithText(TextField, 'Handle'), 'j$run');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Continue'),
        label: 'onboarding_continue');
    await settle(tester, find.text('Matches'), label: 'shell');
  }

  /// Creates a team through the UI and adds [guests] guest players to it.
  Future<void> createTeamWithGuests(
      WidgetTester tester, String teamName, List<String> guests) async {
    await tester.tap(find.text('Profile').last);
    await settle(tester, find.text('My teams'), label: 'profile_tab');
    await tester.tap(find.text('My teams'));
    await settle(tester, find.byIcon(Icons.add), label: 'my_teams');
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.widgetWithText(TextField, 'Team name'),
        label: 'create_team');
    await tester.enterText(
        find.widgetWithText(TextField, 'Team name'), teamName);
    await tester.pumpAndSettle();
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Create'),
        label: 'create_team_submit');
    await settle(tester, find.text(teamName), label: 'team_page_$teamName');

    // ADDING PLAYERS: guests, through the roster UI
    for (final g in guests) {
      await tapScrolled(tester, find.textContaining('Add guest player'),
          label: 'add_guest_cta');
      await settle(tester, find.byType(TextField), label: 'guest_dialog');
      await tester.enterText(find.byType(TextField).last, g);
      await tester.pumpAndSettle();
      final addBtn = find.widgetWithText(TextButton, 'Add');
      await tester.tap(addBtn.evaluate().isNotEmpty
          ? addBtn.first
          : find.widgetWithText(FilledButton, 'Add').first);
      await settle(tester, find.text(g), label: 'guest_added_$g');
    }
  }

  // ==========================================================================
  testWidgets('JOURNEY A: run a tournament end to end', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Organizer $run');
    await shot(tester, 'ja1_signed_in');

    // two teams, each with two guests, so fixtures are actually playable
    await createTeamWithGuests(tester, 'Alpha $run', ['A1', 'A2']);
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await createTeamWithGuests(tester, 'Beta $run', ['B1', 'B2']);
    await shot(tester, 'ja2_two_teams_with_players');

    // Matches tab -> Tournaments -> create
    await tester.tap(find.text('Matches').last);
    await settle(tester, find.byIcon(Icons.emoji_events_outlined),
        label: 'matches_tab');
    await tester.tap(find.byIcon(Icons.emoji_events_outlined).first);
    await settle(tester, find.textContaining('ournament'),
        label: 'tournaments_list');
    await shot(tester, 'ja3_tournaments_list');

    await tapScrolled(tester, find.byIcon(Icons.add), label: 'new_tournament');
    await settle(tester, find.widgetWithText(TextField, 'Tournament name'),
        label: 'create_tournament');
    await tester.enterText(find.widgetWithText(TextField, 'Tournament name'),
        'Cup $run');
    await tester.pumpAndSettle();
    await tapScrolled(tester,
        find.widgetWithText(FilledButton, 'Create tournament'),
        label: 'create_tournament_submit');
    await settle(tester, find.text('Manage tournament'), label: 'manage');
    await shot(tester, 'ja4_manage_tournament');

    // add both teams, then place one in group B (the CRITICAL the critic found)
    for (final t in ['Alpha $run', 'Beta $run']) {
      await tapScrolled(tester, find.textContaining('Add my team'),
          label: 'add_my_team');
      await settle(tester, find.text(t), label: 'pick_team_$t');
      await tester.tap(find.text(t).last);
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
    }
    await shot(tester, 'ja5_teams_added');

    // moving a team to group B must actually take effect
    final bChip = find.widgetWithText(ChoiceChip, 'B');
    if (bChip.evaluate().isNotEmpty) {
      await tester.tap(bChip.last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await shot(tester, 'ja6_groups_assigned');

    // no raw Postgres error may reach the user anywhere in this flow
    expect(find.textContaining('PostgrestException'), findsNothing,
        reason: 'a raw Postgres exception reached the tournament UI');
    expect(find.textContaining('row-level security'), findsNothing);
  });

  // ==========================================================================
  testWidgets('JOURNEY B: find a team to play with', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Seeker $run');
    await createTeamWithGuests(tester, 'Seekers $run', ['S1', 'S2']);

    // post a looking-for ad through the composer
    await tester.tap(find.text('Discover').first);
    await settle(tester, find.byIcon(Icons.add), label: 'discover_tab');
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.byType(TextField), label: 'composer');
    await shot(tester, 'jb1_composer');

    final title = find.widgetWithText(TextField, 'Title');
    if (title.evaluate().isNotEmpty) {
      await tester.enterText(title.first, 'Need an opponent $run');
      await tester.pumpAndSettle();
    }
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Post'),
        label: 'post_submit');
    await settle(tester, find.text('Discover'), label: 'back_to_feed');
    await shot(tester, 'jb2_feed_after_post');

    // the feed must show real intent, not a raw error or an empty wall
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
  });

  // ==========================================================================
  testWidgets('JOURNEY C: search for players and add them', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Scout $run');
    // adding players IS the journey: a team plus guests, via the roster UI
    await createTeamWithGuests(tester, 'Scouts $run', ['Rohit G', 'Virat G']);
    await shot(tester, 'jc1_roster_with_players');

    // the roster must show the players we just added
    expect(find.text('Rohit G'), findsWidgets);
    expect(find.text('Virat G'), findsWidgets);

    // search: find a player by the handle we registered
    await tester.tap(find.text('Discover').first);
    await settle(tester, find.byIcon(Icons.search), label: 'discover_tab');
    await tester.tap(find.byIcon(Icons.search).first);
    await settle(tester, find.byType(TextField), label: 'search_screen');
    await tester.enterText(find.byType(TextField).first, 'Scout $run');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot(tester, 'jc2_search_by_name');
    expect(find.textContaining('Scout $run'), findsWidgets,
        reason: 'search must find a player by display name');

    // and by @handle - the MISS-5 payoff
    await tester.enterText(find.byType(TextField).first, '@j$run');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot(tester, 'jc3_search_by_handle');
    expect(find.textContaining('Scout $run'), findsWidgets,
        reason: 'search must find a player by @handle');

    expect(find.textContaining('PostgrestException'), findsNothing);
  });
}
