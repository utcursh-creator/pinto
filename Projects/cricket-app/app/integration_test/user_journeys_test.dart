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
  ///
  /// Searches DOWN first and then UP. It used to only scroll down, so anything
  /// above the current position was unreachable - journey B hunted for the flair
  /// chips (which sit near the top of the composer), scrolled all the way to the
  /// bottom, and failed with a screenshot of the end of the form.
  Future<void> tapScrolled(WidgetTester tester, Finder f,
      {String label = 'tap'}) async {
    Future<bool> tryTap() async {
      if (f.evaluate().isEmpty) return false;
      await tester.ensureVisible(f.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      await tester.tap(f.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      return true;
    }

    for (final dy in const [-220.0, 220.0]) {
      for (var i = 0; i < 14; i++) {
        if (await tryTap()) return;
        await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
      }
    }
    if (await tryTap()) return;
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
    // The auth listener re-anons and the router gate returns us to Discover.
    //
    // This used to give up SILENTLY after ~12s, so a sign-out that stranded the
    // app somewhere else (create-profile, or a splash that never resolves) was
    // invisible here and surfaced as a confusing failure several steps later in
    // whatever the journey did next - which is how run 23 reported six failures
    // in five different places. Fail HERE, with a frame, so the next reader sees
    // the actual state.
    for (var i = 0; i < 50; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (find.text('Sign in').evaluate().isNotEmpty) return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot('timeout_signed_out_state');
    fail('after signing out, the app never showed the anonymous "Sign in" call '
        'to action - it is stranded somewhere else');
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
    // NOT wrapped in `if (chip.isNotEmpty)`. That guard is what let the same
    // step in journey G skip silently for both teams while the run stayed
    // green (review #2, finding 18) - if the chip is gone, this journey should
    // fail loudly and say so.
    final bChip = find.widgetWithText(ChoiceChip, 'B');
    expect(bChip, findsWidgets,
        reason: 'the group chips are how a team is placed in a group; if they '
            'are not on screen the rest of this journey is meaningless');
    await tester.tap(bChip.last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
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

    // The composer had NO title input at all until this run - the field this
    // once looked for did not exist, the `if` silently skipped, and the later
    // assertion could never have passed (found by driving run 22).
    await tapScrolled(tester, find.widgetWithText(TextField, 'Headline (optional)'),
        label: 'headline_field');
    await tester.enterText(
        find.widgetWithText(TextField, 'Headline (optional)'),
        'Need an opponent $run');
    await tester.pumpAndSettle();
    // A flair is REQUIRED - without it _post() bails with "Pick a flair." and
    // the composer never closes. The journey never picked one, so it had never
    // actually created a post; the old wait on find.text('Discover') matched the
    // tab label and hid that completely (re-review 2026-07-07).
    // The flair options are FlairChip widgets inside a GestureDetector, NOT
    // ChoiceChips - a finder for ChoiceChip could never match them.
    await tapScrolled(tester, find.text('Practice match'), label: 'pick_flair');
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

    // The WICKET sheet gained a "The delivery was" row, because a stumping off
    // a wide and a run-out off a no-ball were previously unrecordable (review
    // #2). Widget tests only ever see this sheet in a 600pt viewport, where it
    // has to be scrolled - so LOOK at it on a real screen before believing it
    // fits. Nothing is recorded here; the sheet is dismissed and journey D
    // carries on with the no-ball below.
    await tester.tap(find.text('WICKET'));
    await settle(tester, find.text('The delivery was'), label: 'wicket_sheet');
    await shot(tester, 'jd4b_wicket_sheet');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Wide'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await shot(tester, 'jd4c_wicket_off_wide');
    Navigator.of(tester.element(find.text('The delivery was'))).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

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

    // Undo gets the same treatment, for the same reason. This step used to
    // assert ONLY that no "Could not undo" toast appeared - so making
    // undoLastBall a no-op, or re-wrapping the pad in the AbsorbPointer that
    // originally killed these controls, left it green: nothing happened, so no
    // error appeared either (review #2, finding 45).
    //
    // The observable has to match WHAT IS BEING UNDONE. The last thing written
    // above is the strike swap, and a swap is an EVENT row, not a ball - so
    // undoing it moves neither the over nor the score. (I asserted the over
    // first and the journey failed with 'Over 0.2 - CRR 21.0' unchanged on both
    // sides, which is correct behaviour, not a bug.)
    //
    // What it must do is put the striker back.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Could not undo'), findsNothing);
    expect(onStrike(), before,
        reason: 'Undo must actually remove the strike-swap event and put the '
            'original batter back on strike. The absence of a "Could not undo" '
            'toast is exactly what a DEAD button produces, so it proved '
            'nothing on its own.');
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

  // JOURNEY G: a tournament with a REAL bracket.
  //
  // Journey A only ever added TWO teams, so `Generate group fixtures` - the step
  // that turns a tournament from a list of names into something anyone can play -
  // had never once been exercised on a device. A tournament needs FOUR (two per
  // group), which is also the point where the organiser's own gating copy ("You
  // need 4 teams to start: 2 in group A and 2 in group B") either tells the truth
  // or lies.
  //
  // It also pins the gate on the NEXT step: with the group games unplayed,
  // `Generate playoffs` must be DISABLED and must say why. That button being
  // wrongly stuck disabled is exactly the failure the tournamentOverviewProvider
  // invalidation fix addressed, and it still has no other test.
  testWidgets('JOURNEY G: four teams, groups, and a real fixture list',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    await signUpFresh(tester, run, 'Organiser $run');

    // four teams, each with two guests so the fixtures are actually playable
    final teams = ['G1 $run', 'G2 $run', 'G3 $run', 'G4 $run'];
    for (var i = 0; i < teams.length; i++) {
      await createTeamWithGuests(tester, teams[i], ['p${i}a', 'p${i}b']);
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
    }

    await tester.tap(find.text('Matches').last);
    await settle(tester, find.byIcon(Icons.emoji_events_outlined),
        label: 'matches_tab_g');
    await tester.tap(find.byIcon(Icons.emoji_events_outlined).first);
    await settle(tester, find.textContaining('ournament'), label: 'tourneys_g');
    await tapScrolled(tester, find.byIcon(Icons.add), label: 'new_tournament_g');
    await settle(tester, find.widgetWithText(TextField, 'Tournament name'),
        label: 'create_tournament_g');
    await tester.enterText(
        find.widgetWithText(TextField, 'Tournament name'), 'Bracket $run');
    await tester.pumpAndSettle();
    await tapScrolled(
        tester, find.widgetWithText(FilledButton, 'Create tournament'),
        label: 'create_tournament_submit_g');
    await settle(tester, find.text('Manage tournament'), label: 'manage_g');

    // With no teams yet, the organiser must be TOLD what is missing and the
    // button must be disabled - not enabled-then-failing.
    expect(find.textContaining('You need 4 teams'), findsOneWidget,
        reason: 'the entry requirement is stated up front');
    final genFixtures =
        find.widgetWithText(FilledButton, 'Generate group fixtures');
    expect(tester.widget<FilledButton>(genFixtures).onPressed, isNull,
        reason: 'fixtures cannot be generated with no teams');

    for (final t in teams) {
      await tapScrolled(tester, find.textContaining('Add my team'),
          label: 'add_my_team_g');
      await settle(tester, find.text(t), label: 'pick_team_g_$t');
      await tester.tap(find.text(t).last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await shot(tester, 'jg1_four_teams');

    // Two of them into group B, so both groups have two.
    //
    // The chips live in each team's ListTile.trailing WRAP, not a Row - my first
    // attempt looked for a Row ancestor, found nothing, and an
    // `if (chip.isNotEmpty)` guard swallowed it. All four teams stayed in group A,
    // Generate group fixtures stayed correctly disabled, and the only assertion
    // afterwards was "no PostgrestException" - which passed because NOTHING
    // HAPPENED. No conditional taps here: if a chip is missing this must fail.
    for (final t in [teams[2], teams[3]]) {
      final tile = find.ancestor(of: find.text(t), matching: find.byType(ListTile));
      final bChip = find.descendant(
          of: tile, matching: find.widgetWithText(ChoiceChip, 'B'));
      await tester.ensureVisible(bChip.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(bChip.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await shot(tester, 'jg2_groups_split');

    // The split must have LANDED. Read the app's own verdict, not my taps -
    // but read the RIGHT one: the "You need 4 teams... A has N and B has N"
    // line only renders while the requirement is UNMET, so waiting for
    // "A has 2 and B has 2" waits for a string that by definition never
    // appears once the split is correct. The met-state signal is the warning
    // disappearing and the button coming alive.
    var enabled = false;
    for (var i = 0; i < 30; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (tester.widget<FilledButton>(genFixtures).onPressed != null) {
        enabled = true;
        break;
      }
    }
    if (!enabled) {
      await binding.takeScreenshot('timeout_groups_not_split');
      fail('after moving two teams to group B, Generate group fixtures never '
          'became enabled - the split did not take effect');
    }
    expect(find.textContaining('You need 4 teams'), findsNothing,
        reason: 'the entry requirement is met, so its warning must go away');
    await tapScrolled(tester, genFixtures, label: 'generate_fixtures');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot(tester, 'jg3_fixtures');

    expect(find.textContaining('PostgrestException'), findsNothing,
        reason: 'generating fixtures must not surface a raw Postgres error');
    expect(find.textContaining('row-level security'), findsNothing);

    // POSITIVE assertion: the fixtures actually exist now. Each group of two
    // produces one game, so the two group winners can meet in a semifinal.
    // (The section heading is "Group fixtures" - verified in
    // manage_tournament_screen._groupStage, not guessed.)
    await settle(tester, find.text('Group fixtures'), label: 'fixtures_shown');

    // The playoffs gate must be honest: the group games have not been played.
    await tapScrolled(tester, find.textContaining('Finish every group match'),
        label: 'playoffs_gate_copy');
    final genPlayoffs = find.widgetWithText(FilledButton, 'Generate playoffs');
    expect(tester.widget<FilledButton>(genPlayoffs).onPressed, isNull,
        reason: 'playoffs cannot be seeded before the group games are played');
  });

  // JOURNEY M: message a player you just found.
  //
  // Messaging is the whole point of a matchmaking app - a post you cannot
  // follow up on is a dead end - and until now NO device journey opened the
  // inbox or a thread at all. Both were rewritten in one unit (review #2
  // findings 15 and 41): the inbox is a single `dm_inbox()` RPC instead of a
  // download of every message body the user owns, and the thread gained a
  // re-sync so a socket gap no longer silently eats part of a conversation.
  // Neither the RPC's JSON reaching a ListTile nor the new pull-to-refresh had
  // ever been on a screen.
  testWidgets('JOURNEY M: find a player and message them', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final run = DateTime.now().millisecondsSinceEpoch % 1000000;

    // the person being messaged has to exist first
    await signUpFresh(tester, run, 'Rahul $run');
    // ...and the person doing the messaging is somebody else
    await signUpFresh(tester, run + 1, 'Priya ${run + 1}');

    await tester.tap(find.text('Discover').last);
    await settle(tester, find.byIcon(Icons.mail_outline), label: 'discover_m');
    await tester.tap(find.byIcon(Icons.mail_outline).first);
    await settle(tester, find.text('Messages'), label: 'inbox_m');
    await shot(tester, 'jm1_inbox_empty');

    // compose: search by handle, which is unique per run (a name search would
    // match every Rahul every previous run left behind)
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await settle(tester, find.text('New message'), label: 'compose_sheet');
    await tester.enterText(find.byType(TextField).last, 'j$run');
    await settle(tester, find.text('Rahul $run'), label: 'people_search');
    await tester.tap(find.text('Rahul $run').last);

    // the thread opens named after the person, not "Chat" (DM-1)
    await settle(tester, find.widgetWithText(TextField, 'Message...'),
        label: 'dm_thread');
    expect(find.text('Rahul $run'), findsWidgets,
        reason: 'the thread header names the person being messaged');

    const msg = 'Are we on for Sunday?';
    await tester.enterText(find.widgetWithText(TextField, 'Message...'), msg);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await settle(tester, find.text(msg), label: 'sent_bubble');
    await shot(tester, 'jm2_thread_sent');
    expect(find.textContaining('PostgrestException'), findsNothing,
        reason: 'sending a DM must not surface a raw Postgres error');

    // The receipt tick. Rahul is not on his phone, so this is ONE tick: the
    // server has it, his device does not. Two ticks here would mean the
    // delivered stamp is being written by the wrong side.
    expect(find.byIcon(Icons.done), findsOneWidget,
        reason: 'a sent message carries a tick');
    expect(find.byIcon(Icons.done_all), findsNothing,
        reason: 'nobody has received it yet - a tick that goes double on its '
            'own would be a lie the sender cannot check');

    // THE NEW RECOVERY PATH (finding 41): pull down to catch up. It must bring
    // back what the socket missed and must NOT double what is already there -
    // the whole risk of a re-sync is that it re-appends the thread.
    await tester.fling(find.byType(ListView).last, const Offset(0, 300), 1000);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text(msg), findsOneWidget,
        reason: 'a re-sync must not duplicate a message already on screen');
    await shot(tester, 'jm3_thread_after_refresh');

    // back to the inbox: this row is the dm_inbox() RPC rendered - the other
    // participant's name and the preview both come out of that one call
    await tester.pageBack();
    await settle(tester, find.text('Messages'), label: 'inbox_after');
    await settle(tester, find.text(msg), label: 'inbox_preview');
    expect(find.text('Rahul $run'), findsOneWidget,
        reason: 'the inbox row names the other participant');
    expect(find.textContaining('Could not load messages'), findsNothing);
    await shot(tester, 'jm4_inbox_row');
  });
}
