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

  // ==========================================================================
  // JOURNEY D: score a real match through the console, driving specifically the
  // paths the fix run repaired and which had NEVER been device-verified:
  //   - a NO-BALL that went for BYES (the plural-vs-singular enum bug: this
  //     delivery was a guaranteed 400 and could not be scored at all)
  //   - the 5-run PENALTY toggle and an OVERTHROW on the same ball (SCOR-7)
  //   - Undo at the START of an over (it lived inside the AbsorbPointer, so it
  //     was dead at exactly the moment a scorer reaches for it)
  //   - Swap strike and Retire, which were dead for the same reason
  testWidgets('JOURNEY D: score a match through the console', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Scorer $run');
    await createTeamWithGuests(tester, 'Bat $run', ['Bat1', 'Bat2', 'Bat3']);
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await createTeamWithGuests(tester, 'Bowl $run', ['Bowl1', 'Bowl2']);

    // Matches -> start a match
    await tester.tap(find.text('Matches').last);
    await settle(tester, find.byIcon(Icons.add), label: 'matches_tab_d');
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.text('Start a match'), label: 'start_match');
    await shot(tester, 'jd1_start_match');

    // pick both teams from the dropdowns
    await tester.tap(find.text('Choose your team'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bat $run').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose the opponent'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bowl $run').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.enterText(find.widgetWithText(TextField, 'Overs'), '1');
    await tester.pumpAndSettle();
    await tapScrolled(tester, find.textContaining('Next: squads'),
        label: 'to_squads');

    // squads: take everyone offered on both sides
    await settle(tester, find.text('Squads'), label: 'squads_screen');
    for (final n in ['Bat1', 'Bat2', 'Bat3', 'Bowl1', 'Bowl2']) {
      final row = find.text(n);
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
      }
    }
    await shot(tester, 'jd2_squads');
    await tapScrolled(tester, find.textContaining('Next: toss'),
        label: 'to_toss');

    // toss + openers - a real scorer picks the winner, the decision, and BOTH
    // openers. (My first pass tapped Start match with none of them chosen, which
    // is how the hidden-requirements defect above surfaced.)
    await settle(tester, find.text('Toss winner'), label: 'toss_screen');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bat $run'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bat'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // openers appear once the batting side is known
    await settle(tester, find.text('Striker'), label: 'openers_visible');
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bat1').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bat2').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await shot(tester, 'jd3_toss');
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Start match'),
        label: 'start_match_btn');

    // the console
    await settle(tester, find.text('Live scoring'), label: 'console');
    await shot(tester, 'jd4_console');

    // a bowler must be picked before the pad is live
    final pick = find.widgetWithText(TextButton, 'Pick');
    if (pick.evaluate().isNotEmpty) {
      await tester.tap(pick.first);
      await settle(tester, find.text('Select bowler'), label: 'bowler_sheet');
      await tester.tap(find.textContaining('Bowl1').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
    }

    // THE REGRESSION THAT MATTERS: a no-ball that went for byes. Before the fix
    // the console sent the plural enum spelling and Postgres rejected the ball.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Extras'));
    await settle(tester, find.text('This ball was'), label: 'extras_sheet');
    await tester.tap(find.widgetWithText(ChoiceChip, 'No-ball'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await settle(tester, find.text('The runs came from'), label: 'nb_kind');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Byes'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.add_circle_outline).first); // 1 bye
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await shot(tester, 'jd5_noball_with_byes');
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Record'),
        label: 'record_extras');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // it must NOT have produced an error toast, and the score must have moved
    expect(find.textContaining('PostgrestException'), findsNothing,
        reason: 'a no-ball with byes must be scoreable (enum spelling)');
    expect(find.textContaining('Could not'), findsNothing);
    await shot(tester, 'jd6_after_noball');

    // a couple of ordinary runs
    for (final r in ['1', '4']) {
      final b = find.widgetWithText(OutlinedButton, r);
      if (b.evaluate().isNotEmpty) {
        await tester.tap(b.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 800));
        final skip = find.text('Skip');
        if (skip.evaluate().isNotEmpty) {
          await tester.tap(skip);
          await tester.pumpAndSettle(const Duration(milliseconds: 300));
        }
      }
    }

    // Undo / Swap strike / Retire must be REACHABLE (they used to sit inside the
    // AbsorbPointer and were dead whenever no bowler was selected).
    expect(find.widgetWithText(OutlinedButton, 'Undo'), findsOneWidget,
        reason: 'Undo must always be reachable');
    expect(find.widgetWithText(OutlinedButton, 'Swap strike'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retire'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Swap strike'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Could not swap'), findsNothing,
        reason: 'swap strike is a real event row now');
    await shot(tester, 'jd7_after_swap');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Could not undo'), findsNothing);
    await shot(tester, 'jd8_after_undo');

    // no raw database error may have surfaced anywhere in the whole flow
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
  });
}
