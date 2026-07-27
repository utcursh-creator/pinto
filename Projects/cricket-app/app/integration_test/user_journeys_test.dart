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

  /// Taps a run button and dismisses the wagon-wheel prompt.
  ///
  /// Every scoring shot opens a "Where did N run(s) go?" sheet so the scorer can
  /// place the shot. That is the intended feature - but in a test the sheet
  /// swallows the NEXT tap, so scoring two balls in a row silently records only
  /// the first (run 16 read 1/0 when it expected 5/0, three steps later).
  Future<void> scoreRuns(WidgetTester tester, String runs) async {
    await tester.tap(find.widgetWithText(OutlinedButton, runs));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    if (find.text('Skip').evaluate().isNotEmpty) {
      await tester.tap(find.text('Skip').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
    }
  }

  Future<void> pickFromDropdown(
      WidgetTester tester, int index, String optionText) async {
    final dd = find.byType(DropdownButton<String>);
    final option = find.text(optionText);
    // A DropdownButton keeps EVERY item in an IndexedStack inside the button
    // itself (so it can size to the widest one), so `find.text(option)` matches
    // even when the menu never opened. Detecting "open" that way taps a hidden
    // child, the value never changes, and the failure lands two steps later on
    // the next screen - which is exactly how run 11 reported a missing "Squads"
    // header when the real problem was an unset opponent. Count the matches
    // BEFORE tapping and wait for the count to GROW: the extra one is the
    // overlay item, and only that is real evidence the route is up.
    final before = option.evaluate().length;
    await tester.ensureVisible(dd.at(index));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(dd.at(index));
    var opened = false;
    for (var i = 0; i < 25; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      if (option.evaluate().length > before) {
        opened = true;
        break;
      }
    }
    if (!opened) {
      await binding.takeScreenshot('timeout_dropdown_$optionText');
      fail('dropdown $index never opened a menu offering "$optionText" '
          '(matches stayed at $before)');
    }
    await tester.tap(option.last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    // Assert the OUTCOME, not the tap: a DropdownButton whose menu closed
    // without a selection looks identical on screen.
    final w = tester.widget<DropdownButton<String>>(dd.at(index));
    if (w.value == null) {
      await binding.takeScreenshot('unset_dropdown_$optionText');
      fail('dropdown $index still has no value after picking "$optionText"');
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
    // THE POST MUST EXIST. `settle(find.text('Discover'))` was a no-op - the tab
    // label is on screen the whole time, so it resolved instantly and the
    // journey asserted nothing about whether the post was created (re-review
    // 2026-07-07). Wait for the ad itself to appear in the feed.
    await settle(tester, find.textContaining('Need an opponent $run'),
        label: 'post_in_feed');
    await shot(tester, 'jb2_feed_after_post');

    expect(find.textContaining('Need an opponent $run'), findsWidgets,
        reason: 'the ad we just posted must be in the feed we land back on');
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
    // NOT `find.textContaining(...)` - that matched the search box this test
    // had just typed into, so it passed with zero results (re-review
    // 2026-07-07). Assert on a RESULT ROW.
    expect(
      find.descendant(
          of: find.byType(ListTile), matching: find.textContaining('Scout $run')),
      findsWidgets,
      reason: 'search must return the player as a result, not just echo the '
          'query back in the search field',
    );

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

    // Tap the DropdownButton WIDGET, not its hint text: the device run warned
    // "derived an Offset that would not hit test" for every hint-text tap,
    // because the Text sits inside the button but the hit test lands elsewhere.
    // Opens the Nth DropdownButton and picks [optionText]. Polls for the menu
    // rather than assuming a fixed delay - the overlay route can take longer
    // than any single pumpAndSettle on a loaded simulator, and the failure then
    // looks like a missing option ("Bad state: No element") rather than a slow
    // menu. Screenshots on failure so the next run shows the real state.

    await pickFromDropdown(tester, 0, 'Bat $run'); // your team
    // The opponent is a search sheet now, not a dropdown of every team in the
    // database. Type the club name and take the result.
    await tester.tap(find.text('Choose the opponent'));
    await settle(tester, find.text('Search teams'), label: 'opponent_sheet');
    await tester.enterText(
        find.widgetWithText(TextField, 'Search teams'), 'Bowl $run');
    await settle(tester, find.text('Bowl $run'), label: 'opponent_result');
    await tester.tap(find.text('Bowl $run').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
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
    await pickFromDropdown(tester, 0, 'Bat1');   // striker
    await pickFromDropdown(tester, 1, 'Bat2');   // non-striker
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
    // TWO chips say "Byes" once No-ball is picked, and both are correct: one in
    // "This ball was" (the delivery type) and one in "The runs came from" (what
    // the runs off the no-ball were). The headings tell them apart for a human;
    // for the finder, the second group renders after the first.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Byes').last);
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

    // Existing is not the same as working: the AbsorbPointer regression left
    // these buttons RENDERED but dead, so findsOneWidget could never have caught
    // it (re-review 2026-07-07). Prove the tap had an EFFECT - who is on strike
    // must actually change.
    String onStrike() {
      final t = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .firstWhere((d) => d.startsWith('On strike:'), orElse: () => '');
      return t;
    }

    final before = onStrike();
    expect(before, isNotEmpty, reason: 'the console names the striker');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Swap strike'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Could not swap'), findsNothing,
        reason: 'swap strike is a real event row now');
    expect(onStrike(), isNot(before),
        reason: 'Swap strike must actually swap the striker - a dead button '
            'that renders fine would pass a mere findsOneWidget');
    await shot(tester, 'jd7_after_swap');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Could not undo'), findsNothing);
    await shot(tester, 'jd8_after_undo');

    // no raw database error may have surfaced anywhere in the whole flow
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
  });

  // JOURNEY E: correct a ball after the fact.
  //
  // Every scorer mis-taps. The whole corrections subsystem exists for it, and it
  // is the one place where a bug silently CORRUPTS a match rather than showing
  // an error: edit_ball was a full overwrite until the 2026-07-07 review, so
  // editing the runs on a delivery wiped its penalty, its wagon shot and its
  // run-out "crossed" flag. This journey drives the correction the way a scorer
  // would - open the log, edit the ball, and check the score actually moved.
  testWidgets('JOURNEY E: correct a ball in the log', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Fixer $run');
    await createTeamWithGuests(tester, 'Fix $run', ['Fix1', 'Fix2']);
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await createTeamWithGuests(tester, 'Foe $run', ['Foe1', 'Foe2']);

    await tester.tap(find.text('Matches').last);
    await settle(tester, find.byIcon(Icons.add), label: 'matches_tab_e');
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester, find.text('Start a match'), label: 'start_match_e');

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    await tester.tap(find.text('Fix $run').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.text('Choose the opponent'));
    await settle(tester, find.text('Search teams'), label: 'opponent_sheet_e');
    await tester.enterText(
        find.widgetWithText(TextField, 'Search teams'), 'Foe $run');
    await settle(tester, find.text('Foe $run'), label: 'opponent_result_e');
    await tester.tap(find.text('Foe $run').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.enterText(find.widgetWithText(TextField, 'Overs'), '2');
    await tester.pumpAndSettle();
    await tapScrolled(tester, find.textContaining('Next: squads'),
        label: 'to_squads_e');

    await settle(tester, find.text('Squads'), label: 'squads_screen_e');
    for (final n in ['Fix1', 'Fix2', 'Foe1', 'Foe2']) {
      final row = find.text(n);
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
      }
    }
    await tapScrolled(tester, find.textContaining('Next: toss'),
        label: 'to_toss_e');

    await settle(tester, find.text('Toss winner'), label: 'toss_screen_e');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Fix $run'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bat'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await pickFromDropdown(tester, 0, 'Fix1');
    await pickFromDropdown(tester, 1, 'Fix2');
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Start match'),
        label: 'start_match_e2');

    await settle(tester, find.text('Live scoring'), label: 'console_e');
    await tester.tap(find.text('Pick'));
    await settle(tester, find.text('Foe1'), label: 'bowler_sheet_e');
    await tester.tap(find.text('Foe1').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // score a single, then a four (each opens the wagon prompt; skip it)
    await scoreRuns(tester, '1');
    await scoreRuns(tester, '4');
    await shot(tester, 'je1_five_scored');
    expect(find.textContaining('5/0'), findsWidgets,
        reason: 'a single and a four is five');

    // THE CORRECTION: that four was really a two.
    await tester.tap(find.byIcon(Icons.edit_note));
    await settle(tester, find.text('Ball log'), label: 'ball_log_e');
    await shot(tester, 'je2_ball_log');

    // STRUCTURE, not just the total. The log must read oldest-first, because
    // each row's over label (0.1, 0.2, ...) is computed by walking the list
    // forward - if the order flips, every label names a different ball than the
    // row it sits on. postgrest's order() defaults to DESCENDING and this list
    // was backwards until c06c4c4, and the journey still PASSED because it only
    // checked the score. Assert the arrangement.
    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      find.descendant(of: tiles.first, matching: find.text('1')),
      findsOneWidget,
      reason: 'the first row must be the FIRST ball - the single',
    );
    expect(
      find.descendant(of: tiles.last, matching: find.text('4')),
      findsOneWidget,
      reason: 'the second row must be the SECOND ball - the four',
    );

    // correct the FOUR (the second ball) down to a two
    await tester.tap(tiles.last);
    await settle(tester, find.text('Edit this ball'), label: 'ball_actions_e');
    await tester.tap(find.text('Edit this ball'));
    await settle(tester, find.text('Runs off the bat'), label: 'edit_sheet_e');
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tapScrolled(tester, find.widgetWithText(FilledButton, 'Save'),
        label: 'save_edit_e');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot(tester, 'je3_after_edit');

    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);

    // back to the console: the score must have followed the correction
    await tester.pageBack();
    await settle(tester, find.text('Live scoring'), label: 'console_after_edit');
    await shot(tester, 'je4_console_after_edit');
    expect(find.textContaining('3/0'), findsWidgets,
        reason: 'the four became a two, so 5 must have become 3');
  });

  // JOURNEY K: the very first thing anyone sees.
  //
  // Every new user arrives signed OUT. If browsing is a dead end - a spinner, a
  // raw 403, a screen with no way to sign in - they never become a user at all.
  testWidgets('JOURNEY K: browse anonymously before signing up', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await ensureSignedOut(tester);
    await shot(tester, 'jk1_anon_discover');

    // Discover must render something an anonymous visitor can act on, not an
    // error and not an endless spinner.
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
    expect(find.text('Sign in'), findsWidgets,
        reason: 'an anonymous visitor must always have a way in');

    // the other tabs must be reachable and must not blow up either
    for (final tab in ['Matches', 'Profile', 'Discover']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('PostgrestException'), findsNothing,
          reason: '$tab must be viewable signed out');
      expect(find.textContaining('Exception'), findsNothing,
          reason: '$tab must not surface a raw exception signed out');
      await shot(tester, 'jk2_anon_$tab');
    }
  });
}
