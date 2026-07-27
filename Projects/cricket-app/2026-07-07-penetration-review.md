---
type: audit
date: 2026-07-07
project: cricket-app
status: open
tags: [security, code-review, penetration-review, pitch]
---

# Pitch - whole-system penetration review

Adversarial review of the ENTIRE system after the 8-slice rebuild + 4-unit sweep.
Method: 12 attack fronts, each finding then handed to an independent SKEPTIC agent
told to REFUTE it against the real code; only survivors are listed. Run TWICE
(52 agents, 5.7M tokens, 1682 tool calls) and merged - 20 findings appeared in only
one run, so the second pass paid for itself. A completeness critic then hunted what
all 12 fronts missed, and found a CRITICAL none of them saw.

**100 confirmed findings**: 2 critical, 24 high, 39 medium, 35 low.

The synthesis estimates ~55 DISTINCT defects - fronts corroborated each other heavily
(the fold squad_size divergence was found 4x, edit_ball data loss 3x).

| front | confirmed |
|---|---|
| Error handling & dead ends | 19 |
| Flutter state & lifecycle | 12 |
| Realtime & concurrency | 8 |
| Stale Flutter tests | 8 |
| Client-side security | 7 |
| Build & release config | 7 |
| Completeness critic (missed by all fronts) | 6 |
| RLS & authorization | 6 |
| Scoring fold correctness | 6 |
| Migration safety | 6 |
| Dart<->SQL contract | 6 |
| Data exposure / PII | 5 |
| Stale pgTAP tests | 4 |

Empirically verified by Claude (test runs, not static review): `flutter analyze` clean;
`flutter test` 183 pass; **`supabase test db` FAILS** (8 files / 18 assertions) on any
non-pristine database - see the Empirical section.

---

## SYNTHESIS (release gate, themes, fix order, blast radius)

# 1. RELEASE GATE

First, the framing that matters: **nothing in this batch will make `supabase db push` fail, and no migration drops a column or a table.** The push is mechanically safe. The gate is not about the push surviving — it is about what the push *switches on* over a database that already holds a real person's data, and what the next APK hands to whoever holds it.

Also note before counting: the 78 findings contain heavy duplication across fronts. The fold squad_size divergence appears four times, the edit_ball data loss three times, delete_my_account FK abort twice, retire-hurt-no-incoming twice, the missing `event_kind` select twice, the duplicate GlobalKey three times, the DM `ref`-in-dispose twice. There are roughly 55 distinct defects, not 78.

## Blocks the hosted push (fix in the same migration batch)

These are all SQL. Every one of them is cheap, and every one of them becomes materially harder to fix after real rows exist under it.

- **`team_members_update_admin_or_self`** — one PATCH makes any signed-in user admin of the friend's team, then rename/delete it, evict members, read its home ground, absorb its guest history. This is the single worst item in the set and it is a policy split plus one trigger.
- **`tt_write_organizer` / `tm_write_organizer`** — revoke `insert, update, delete` on `tournament_teams` and `tournament_matches` from `authenticated`. Two lines. Without them, any account can enroll the friend's team in a fake tournament, generate real matches it scores, and permanently block the friend from deleting their own casual matches.
- **`matches_update_scorer`** — revoke blanket UPDATE, add `set_toss`. Otherwise every guard in `set_match_result` and `update_match_schedule` is decorative, and a scorer can swap in a stranger's team post-hoc and fabricate that team's public record.
- **`add_squad_member`** — validate `_team_id` against the match and `_team_member_id` against the team, and add `on conflict do update`. Unvalidated, it forges permanent, publicly-readable career records (a golden duck) for players who never played, with no user-facing way to remove them. The `on conflict` also un-bricks interrupted squad setup for free.
- **`posts_update_author`** — add the missing `is_team_admin(team_id)` to the WITH CHECK. One line.
- **Fold lockstep (`compute_innings_cards` / `restamp_innings_strike` squad_size)** — this is the only finding in the set that *permanently corrupts real data through a sanctioned path*. `matches.potm` is frozen at result time and career stats are baked from the truncated cards. Every day the friend scores a non-11 match is another unrecoverable record. Extract one `_innings_fold_params()` and have all three folds call it.
- **`delete_my_account()`** — always take the anonymize path, extended to `profile_locations`, storage objects, and the six other RESTRICTing FKs. Today Delete Account returns a raw FK error for anyone who ever created a team. This is also the Play Store rejection.
- **`discover_posts` location oracle** — sub-metre recovery of a poster's home coordinates via caller-controlled probe + unclamped radius. The hosted DB has real users with real saved GPS. Snap to a grid at write time and backfill.
- **`edit_ball` → COALESCE-patch shape** — this is the highest-leverage server fix in the batch, because it makes the client's incomplete `editBall` call harmless *without shipping an APK*. Every correction the friend makes today silently zeroes penalty runs, the wagon shot, and the run-out `crossed` flag (which then re-stamps strike for the rest of the innings).
- **Bowler-cap dead-end** — derive the cap from the actual bowling squad at `start_innings` and stamp `rules` in the fixture generators. Otherwise a 5-over game with 4 bowlers stops dead mid-innings with no in-app escape.
- **Reject `retired_out` / `timed_out` on `event_kind`-null rows in `record_ball`** — server-side backstop for the console bug below, so the corruption stops before the APK ships.

## Blocks the APK rebuild (Dart)

- **`'byes'` / `'leg_byes'` → `'bye'` / `'leg_bye'`.** A no-ball that went for byes cannot be scored at all today. Deterministic 400 with a raw toast. This will be the first bug report.
- **Remove `retired_out` / `timed_out` from `_allWicketTypes`.** Picking the non-striker dismisses the striker, silently.
- **Undo:** `_busy` guard, restore `_bowlerId` after an over-boundary undo, and move Undo/Swap/Retire out of the `AbsorbPointer`. Currently the scorer is funnelled into crediting a ball to a bowler who never bowled it.
- **Add `event_kind, extra_penalty, crossed, is_overthrow, overthrow_crossed, wagon_x/y/zone` to `inningsDeliveriesProvider`** and thread them through `editBall`. Fixes three findings at once.
- **DM realtime:** one channel per topic, and call `_syncSubscriptions` from the data branch, not only from `ref.listen`. Right now the DM feature is dead on the normal entry path and leaks a subscription per visit.
- **`humanError()` mapper + `ErrorRetry` rollout**, and the swallowed-write fixes (`_act`, `_setGroup`, `_addTeam`, `_respond`, the six `on PostgrestException`-only sites). This is what the friend will actually screenshot and send.
- **Gate "Request to join" / "This is me" on `!isAnonymous`.** Guests currently get a raw foreign-key violation.
- **Start-a-match empty-teams state** with a "Create a team first" button. The primary CTA is a dead end for every new user.
- **Release tripwire + build identity:** throw in `kReleaseMode` when `SUPABASE_URL` is the localhost default, fail the Gradle release when `key.properties` is missing, set `android:label="Pitch"`, bump `version:` off `1.0.0+1`, and move `dev@pitch.local`/`password123` inside `kDebugMode` behind dart-defines.

## Do right now, outside both (no code)

Delete or rotate `dev@pitch.local` and `other@pitch.local` on the hosted project and disable the email/password provider there. That credential is already in the APK the friend is running, against the production database. Every hour it stays valid is an hour anyone who has that file can log in as that identity.

## Can follow

All iOS items (missing Apple entitlement, iPad `sharePositionOrigin`, `NSPhotoLibraryAddUsageDescription`, URL scheme) — there is no iOS distribution path until the Developer Program is paid for; a dead button on an unbuildable platform is not a release gate. Deep-link registration, though add the "Have an invite code?" fallback and share the raw token soon, because team invites are currently 100% unusable. The `edit_ball`/`insert_ball` PUBLIC revoke (no exploit today). The tournament token row lock. `retire_batter`'s guard asymmetry and unvalidated incoming batter (scorer-only, self-inflicted). `did_not_bat` including a dismissed batter (display only). `inningsWagonProvider` staleness, duplicate GlobalKey, leaked controllers, storage bucket enumeration. And every test finding — none of them is a shipping defect, but see Unit 10.

# 2. THEMES

**The RPC holds the rule; the table is still granted.** Six findings, one mistake. Every authorization boundary in this schema lives inside a `SECURITY DEFINER` function, and then `grant select, insert, update, delete ... to authenticated` leaves the raw PostgREST path wide open next to it with a row-only policy. Worse, RLS was repeatedly used to express rules it structurally cannot: `profile_id = auth.uid()` cannot say "but not the role column", and `is_match_scorer(id)` cannot say "but not `result`, `status`, `team_b_id`". The migrations even contain comments asserting the invariant ("the `is_team_admin` check IS the entire consent boundary") directly above the grant that voids it. The rule: if an RPC is the boundary, revoke the table.

**Fixed in one copy of three.** `compute_innings_state`, `compute_innings_cards` and `restamp_innings_strike` are hand-duplicated 150-line folds held in sync by a comment that says `LOCKSTEP RULE`. SCOR-10 was applied to one of them four revisions ago, and v12, v13 and v14 each faithfully copied the drift forward while re-asserting the comment. The same shape produced `posts_insert_author` vs `posts_update_author` (rule written twice, fixed once) and `create_match` vs the three fixture generators (rules stamped in one of four match-creation paths). Comments do not enforce invariants; shared functions and cross-checking tests do.

**Authorization is mistaken for coherence.** `is_match_scorer`, `is_team_admin` and `is_tournament_organizer` answer "may this caller act here?" The code treats that as also answering "are these the right ids?" So `add_squad_member` takes any team and any member, `tournament_matches` takes any match, `retire_batter` takes an opposition player, `update_match_schedule` derives authority from a link the attacker inserted. Passing the gate is not the same as the arguments being consistent with the row.

**No layer owns the invariant.** Sometimes the disabled button *is* the guard (`retire_batter`'s null-incoming shortcut, incoming-batter squad membership, the wicket-type list) — so the server accepts corruption the client happens not to send. Sometimes the server contract is the only definition, with nothing on the client mirroring it (the `noball_secondary_kind` enum, `rules.max_overs_per_bowler`). Both directions are the same absence: no single place where the rule is written down and checked.

**Full-overwrite writers with partial-knowledge callers.** `edit_ball` writes every scoring column. `inningsDeliveriesProvider` selects 15 of ~25. `editBall` sends a subset of parameters. That one stale SELECT list produces three separate defects — silent penalty/wagon/`crossed` destruction, event rows rendering as phantom balls, and a `+5 penalty` switch that can never be on. A hand-maintained projection list is a schema contract, and nothing tests it.

**Errors are caught to continue, not to inform.** `catch (_) {/* the list refresh reflects reality */}` with the refresh inside the try. `on PostgrestException` with no generic catch, so every offline tap re-enables the button and says nothing. Forty-plus `Text('$e')` sites dumping `PostgrestException(... code: 42501 ...)` and hostnames at users. `ErrorRetry` exists, self-documents as "the one error state for async screens", and is used twice. The habit is silencing the analyzer, not handling failure.

**`ref` treated as ambient.** `ref.read` inside `dispose()`, `ref.invalidate` after an `await` with no `mounted` guard, `ref.listen` used as if it fired immediately. `match_viewer_screen.dart:48` even carries the comment `// captured for safe teardown (ref is unsafe in dispose)` — the DM screens were written next to it and did not read it. Same for the busy-guard: `_record` and `_retire` do it correctly; Undo, Swap-strike and the tournament bracket actions do not.

**The suite is green in the one configuration where it passes.** 800x600 only, Android only, textScale 1.0 only, no recording fake anywhere. Fourteen simultaneous mutations to client-side RPC names, parameter names and extras composition all survived. Assertions match hardcoded labels (`find.textContaining('Toss')` matches the tile's own label), a cap test is vacuous by fixture arithmetic, and a "login-free path" smoke test asserts on the authenticated client's response. Test greenness is currently uncorrelated with the Dart↔Postgres contract.

**Built for infrastructure that does not exist.** `https://pitch.app/...` links with no domain and no registered scheme; a localhost default with no release tripwire; a debug-signing fallback; an iOS Apple button with no entitlement; production credentials hardcoded because the hosted project was treated as a dev fixture. Each is individually understandable as a TODO; together they mean the shipped artifact assumes a deployment nobody built.

# 3. FIX ORDER

Ten units. Each is independently verifiable; backend lands and is proven by pgTAP before the paired Dart change in the same unit.

**Unit 0 — Credential containment (no code).** Delete/rotate `dev@pitch.local` and `other@pitch.local` on hosted; disable the email provider there. Verify: `POST /auth/v1/token?grant_type=password` with the old pair returns 400. Blocks nothing else; do it first because it is live now.

**Unit 1 — Lock the table surface.** One migration: split `team_members_update_admin_or_self` (+ a BEFORE UPDATE trigger on `role`/`team_id`/`profile_id`) and add an admin-gated `set_member_role`; revoke DML on `tournament_teams` and `tournament_matches`; revoke UPDATE on `matches` and add `set_toss`; fix `posts_update_author`; add participant/coherence checks to `add_squad_member` (+ `on conflict do update`), `start_innings`, `retire_batter` and `record_ball`; revoke `edit_ball`/`insert_ball` from PUBLIC. Verify: one pgTAP negative test per exploit transcript already captured in the findings, each as `throws_ok`. Dart coupling is exactly two calls — `setMemberRole` and `setToss` — change them in this unit.

**Unit 2 — Fold lockstep.** `_innings_fold_params(uuid)` returning bpo/squad_size/all_out/max_legal/target, called by all three folds; force a `_batters` entry for the dismissed/retired batter in `compute_innings_state`; reject retirement wicket types on `event_kind`-null rows in `record_ball`. Verify: a pgTAP test that, for squad sizes 3, 6, 11, 12 and 13 with rows past the all-out point, asserts `state.wickets == count(dismissed in cards)` and `cards.bowling.legal_balls == state.legal_balls`. Depends on Unit 1 only for `add_squad_member`'s cap-free insert being validated.

**Unit 3 — Non-destructive corrections.** `edit_ball` becomes COALESCE-patch-shaped for `extra_penalty`, `crossed`, `prevented_catch`, `is_overthrow`, `overthrow_crossed`, `wagon_*`, `commentary_text`; add a monotonic `innings.revision` bumped by a trigger on `deliveries`, return it as the fold's fence token, and fence `record_ball`/`edit_ball`/`insert_ball`/`delete_ball`/`undo_last_ball`/`retire_batter`/`swap_strike` on it. Then Dart: extend the `inningsDeliveriesProvider` select and thread the columns through `_BallEdit`/`editBall`. Verify: pgTAP records a ball with penalty + wagon + crossed, edits only the runs, asserts every other column unchanged; and a stale-token append after an `edit_ball` is rejected. Must follow Unit 2 (the fence returns fold output).

**Unit 4 — Deletion and PII retention.** Always anonymize; extend to `profile_locations`, `post_replies`, `blocked_users`, `team_join_requests`, `guest_claim_requests`, and `storage.objects` under the caller's uid folder; reassign/null `teams.created_by`, `tournaments.organizer_id`, `dm_threads.created_by`, `team_invites.created_by`; convert the caller's `team_members` rows to guests instead of cascading. Verify: new pgTAP cases for user-created-a-team, user-in-someone-else's-squad, user-created-a-tournament/DM-thread/invite; assert `profile_locations` and `storage.objects` are empty and the function never raises. Independent of 1–3.

**Unit 5 — Geolocation and stored-URI validation.** Add `geog_coarse` on `looking_for_posts` quantised to a ~500m grid, populated in `create_looking_for_post`, backfilled; `discover_posts` filters, orders and measures on `geog_coarse` only, with `_radius_m` clamped to a coarse ladder and the probe point quantised. While in the file: CHECK `link_url ~* '^https?://'` and constrain `image_urls` elements to the project storage origin with a length cap. Verify: pgTAP binary-searches `_radius_m` over 40 values and asserts the flip cannot localise better than the grid; a `upi://` link_url insert is rejected.

**Unit 6 — Rules consistency.** Derive `max_overs_per_bowler` server-side in `create_match` when absent and in `generate_group_fixtures` / `generate_playoffs` / `advance_playoffs`; at `start_innings` set the effective cap to `max(ceil(overs/5), ceil(overs / bowling_squad_size))`; add `update_match_rules`. Verify: pgTAP plays a full 5-over innings to completion with a 2-player bowling squad. Depends on Unit 1 (`create_match` gate) and Unit 2 (fold params).

**Unit 7 — Console and client contract (Dart).** `'bye'`/`'leg_bye'`; remove `retired_out`/`timed_out` from `_allWicketTypes`; Undo/Swap-strike `_busy` guard plus over-boundary `_bowlerId` restore and moving those three buttons outside the `AbsorbPointer`; `if (!mounted) return;` after every await before `ref`; capture `SupabaseClient` in `initState` for both DM screens' `dispose`; single per-thread realtime channel plus `_syncSubscriptions` from the data branch; distinct GlobalKeys for the two share sheets; dispose the two leaked controllers; invalidate `inningsWagonProvider` in `_refold`. Verify: a `_SpyMatchRepository` asserting exact named args for wide+2, no-ball+byes, +5 penalty, non-striker run-out, retire, swap-strike and `expectedLastSeq`; plus a test that taps "Share the full scorecard instead" and asserts `takeException()` is null. Depends on Units 1–3 for the server contracts it now pins.

**Unit 8 — Error and dead-end UX (Dart).** One `humanError(Object)`; every snackbar through it; the 38 bare async error branches replaced with `ErrorRetry`; try/catch with invalidate-in-`finally` for `_act`, `_setGroup`, `_addTeam`, `_respond`; trailing generic catch on the six `on PostgrestException` sites; anonymous gating on team-page affordances; `MatchSquadsScreen` seeds from `matchSquadProvider` and diffs; start-match empty-teams state; `dm_thread._init` error+retry; `?from=` carried through the sign-in hop; "Have an invite code?" plus the raw token in the share text; sign-out escape on `CreateProfileScreen`; notification taps for `join_request`/`claim_request`; `launchUrl` scheme gate; `Image.network` `cacheWidth` + `errorBuilder`; `InitialsAvatar` keeps its initials fallback.

**Unit 9 — Build and release identity.** `kReleaseMode` tripwire on the localhost URL (better: drop the default entirely); fail the Gradle release when `key.properties` is absent; `android:label="Pitch"`, `CFBundleName`/`CFBundleDisplayName` aligned, `version: 1.0.1+2`, delete the applicationId TODO; dev credentials behind `String.fromEnvironment` inside `kDebugMode`, and integration tests read the same defines. Verify: `flutter build apk --release` with no defines *fails*; with defines it succeeds and `strings` on the APK finds no `password123`. Must be the last thing before the rebuild.

**Unit 10 — Test harness (run alongside 7–9).** `app/test/flutter_test_config.dart` at 390x844 plus a textScaler-1.5 pass; fix the two unbounded `Row`s it exposes; loop the 11 Android-only tests over both platforms and assert the platform-appropriate tab bar; `try/finally` the seven files missing it; a contract test comparing each Dart param-name set against the migration's `CREATE FUNCTION` signature; rewrite the vacuous mid-over cap assertion; give `hosted_smoke_test` a real anon client plus a `tearDown`, or point it at a scratch project.

# 4. BLAST RADIUS

What the friend actually experiences, ranked by how soon they hit it.

**Scoring a normal gully match breaks the scorecard.** Six- or eight-a-side is the app's entire use case. The live pad says "0/5 all out"; the Scorecard tab, the shared image, the POTM and every player's career page say something different — and the POTM is frozen and the career numbers are permanent. No error, no indication, no way to correct it from the app.

**A no-ball that went for byes cannot be scored at all.** Extras → No-ball → "Byes" → 2 → Record produces a red toast reading `PostgrestException(message: invalid input value for enum noball_secondary_kind: "byes", code: 22P02, ...)` and the ball is simply never written. Their only option is to record something untrue. This is the most likely first message they send.

**Small-squad matches stop dead mid-innings.** A 5-over game with 4 bowlers: after 4 overs every bowler tile is greyed out — "At over limit" on three, "Bowled last over" on the fourth — and the 5th over cannot be bowled by anyone. There is no in-app way to change the rule. The match is unfinishable on the field.

**Correcting a ball quietly destroys runs.** They open the ball log to change a 4 to a 3. On save the team total drops 5 (the penalty is gone), the wagon-wheel shot vanishes, and if that ball was a run-out with "batters crossed", every subsequent delivery is re-stamped to the wrong batter and the rest of the innings is credited to the wrong player. No warning, not reversible.

**"Retired out" dismisses the wrong batter.** They tap Wicket → Retired out → pick the non-striker. The striker is marked out, the wrong player walks off, fall-of-wickets names the wrong player, and the retirement burns a legal ball off the bowler's over.

**Undo doesn't work exactly when it's needed.** Last ball of the over was wrong. Tapping Undo does nothing except toast "Pick a bowler to start the over"; the picker greys out the bowler who actually bowled it; so they pick someone else — and the re-recorded ball is credited to a bowler who never bowled. Double-tapping Undo (an entirely natural impatient gesture) deletes two real deliveries.

**Interrupted setup bricks a match.** They pick squads, tap "Next: toss", something interrupts, they come back via "Resume setup", re-pick the same XI, and get `duplicate key value violates unique constraint "match_squad_match_id_team_member_id_key"`. For a tournament fixture the match cannot even be deleted, which also blocks "Generate playoffs" and strands the whole bracket.

**Delete account is broken for essentially everyone.** Anyone who has ever created a team taps it and gets `Could not delete: PostgrestException(... violates foreign key constraint "teams_created_by_fkey" ...)`. It fails loudly and permanently. It is also a hard Play Store rejection.

**DMs feel broken because they are.** They open Messages, open a conversation, and the other person's replies never arrive live — the inbox and thread screens fight over the same realtime channel and one kills the other. The inbox never reorders and the unread badge never moves unless they pull to refresh. Every visited thread leaks a subscription for the life of the process.

**Team invites never work, once.** They share "Join my cricket team on Pitch: https://pitch.app/invite/9f2a…". The recipient taps it, a browser opens a domain that serves nothing, and there is no code to type instead. Meanwhile "Manage invites" cheerfully lists the invite as active. 100% failure rate on the feature they'd use to grow their team.

**Every hiccup looks like a crash.** `PostgrestException(message: new row violates row-level security policy for table "teams", code: 42501, ...)` and `ClientException with SocketException: Failed host lookup: 'ocejkqihgiinonpyafhl.supabase.co'` appear verbatim in snackbars on 38 screens with no Retry. And the silent half is worse: "Mark filled", assigning a team to a group, and approving a join request all do absolutely nothing on failure — no message, no state change — so they tap repeatedly and conclude the app is broken. A teammate who taps "Mark filled" believes their post is closed while it stays live in every nearby player's feed.

**A new teammate can't start a match.** Signs up, lands on Matches ("No matches yet. Start one."), taps the FAB, and finds an empty "Your team" dropdown with an enabled "Next: squads" that only ever repeats "Pick both teams and overs." Nothing anywhere points to Create a team.

**And the things they will never see but should care most about:** anyone holding the APK has `dev@pitch.local` / `password123` against the production database. Anyone signed in can rewrite one row and become admin of the friend's team — rename it, evict members, read its exact home ground. Anyone can recover, to sub-metre precision, the home coordinates of anyone who has posted in Discover, in about ninety HTTP requests, with no rate limit and no trace. The launcher icon, meanwhile, says `pitch_app`.

---

## CRITICAL

### [critical] Every invite-joined team is hard-coded into group 'A' and the organizer is forbidden from moving it, so any tournament assembled the sanctioned (SEC-8 consent) way can never generate fixtures

- **id**: `tour-invite-joined-teams-locked-in-group-a` | **front**: Completeness critic (missed by all fronts) | **category**: product-loop-deadlock | **runs**: critic
- **where**: `app/lib/src/features/tournaments/presentation/join_tournament_screen.dart:42`

**Evidence**

```
join_tournament_screen.dart:42 hard-codes the group: `.joinTournamentWithToken(widget.token, _teamId!, 'A');` — there is no group picker anywhere in the join UI, and tournament_repository.dart:56-63 passes it straight through to `_group_label`.

The organizer's only way to re-group a team is the A/B chips at manage_tournament_screen.dart:75 `onSelected: (_) => _setGroup(ref, t.teamId, g)`, and `_setGroup` (manage_tournament_screen.dart:307-310) calls `add_tournament_team`, which is is_team_admin-gated:
  20260702160400_add_tournament_team_provenance.sql:14-16
    `if not public.is_team_admin(_team_id) then raise exception 'you must be an admin of this team to enter it'`
By construction an invite-joined team is one the organizer does NOT admin (that is the entire point of the token — see the header comment of 20260702160300_rpc_join_tournament_with_token.sql), so the chip always raises. `_setGroup` has no try/catch, so the tap is a silent no-op.

The gate the organizer then cannot pass, manage_tournament_screen.dart:60:
  `final canGenerate = (byGroup['A'] ?? 0) >= 2 && (byGroup['B'] ?? 0) >= 2;`
And the server would not help even if forced: generate_group_fixtures pairs only within a group (20260625150500_rpc_generate_group_fixtures.sql:25 `and a.group_label = b.group_label`), and generate_playoffs requires exactly 2 groups (20260625150700_rpc_generate_playoffs.sql:12-13 `if _t.group_count <> 2 or _t.qualifiers_per_group <> 2 then raise 'v1 supports 2 groups x 2 qualifiers only'`) and reads `_st->'groups'->1` for group B. tournament_repository.dart:25-26 always creates `'_group_count': 2, '_qualifiers_per_group': 2`.
```

**Failure scenario**  
Organizer creates a tournament, taps "Invite a team", shares the link; four club captains each redeem it and enter their own team. All four rows land in tournament_teams with group_label='A'. The organizer opens Manage tournament, taps the "B" chip on two of them — nothing happens (add_tournament_team raises 'you must be an admin of this team to enter it', swallowed by the un-caught _setGroup). "Generate group fixtures" stays permanently disabled with the hint "Add at least 2 teams to each group." The tournament can never start. The only tournaments that work at all are ones where the organizer personally admins >=2 of the entered teams — i.e. the invite/consent path added by SEC-8 produces a tournament that is structurally impossible to run.

**Root fix**  
Give the organizer group placement authority independent of team admin rights: split group assignment out of add_tournament_team into a new organizer-gated RPC, e.g. `set_tournament_team_group(_tournament_id, _team_id, _group_label)` guarded by `is_tournament_organizer(_tournament_id)` and `tournaments.status = 'setup'` only (no is_team_admin check — placement is not enrolment, so it does not weaken SEC-8 consent). Point manage_tournament_screen._setGroup at that RPC, wrap it in try/catch with a SnackBar, and additionally let the joiner pick a group in join_tournament_screen (or have join_tournament_with_token auto-balance instead of defaulting to 'A').

---

### [critical] team_members UPDATE policy's self-branch lets any authenticated user promote themselves to admin of ANY team (total team takeover)

- **id**: `rls-team-members-self-update-takeover` | **front**: RLS & authorization | **category**: privilege-escalation | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260615140901_team_members_rls.sql:14`

**Evidence**

```
create policy "team_members_update_admin_or_self"
  on public.team_members for update to authenticated
  using (public.is_team_admin(team_id) or profile_id = auth.uid())
  with check (public.is_team_admin(team_id) or profile_id = auth.uid());

Paired with `grant select, insert, update, delete on public.team_members to authenticated;` (20260615140901_team_members_rls.sql:2). The WITH CHECK is evaluated against the NEW row, and `profile_id = auth.uid()` is still true after the attacker rewrites BOTH `role` and `team_id`, so the admin branch is never consulted. `is_team_admin` (20260615140601_authz_helpers.sql:16-29) reads exactly this table, so the forged row instantly makes the attacker an admin.
```

**Failure scenario**  
Any authenticated user who owns at least one membership row (everyone — create_team makes you captain of your own team) issues one PostgREST call:
  PATCH /rest/v1/team_members?id=eq.<my own membership id>
  {"team_id":"<any victim team uuid>", "role":"admin"}
Verified live against the local DB (set role authenticated + request.jwt.claims for the attacker):
  is_team_admin(victim_team) BEFORE = f
  UPDATE 1
  is_team_admin(victim_team) AFTER  = t
  update public.teams set name='PWNED' where id=<victim team>  -> UPDATE 1 (teams_update_admin now passes)
  delete from public.team_members where id=<victim captain row> -> DELETE 1 (victim captain evicted from their own team)
From there every is_team_admin-gated surface falls: teams rename/delete, add/remove members, add_guest_member, create_team_invite, create_match on that team, team_locations (exact home ground geog), team_invites reads, approve_guest_claim (absorb another team's guest history), respond_join_request, add_tournament_team/join_tournament_with_token. Team ids are enumerable — teams_select_authenticated is `using (true)`. This ships to a hosted DB with real user data.

**Root fix**  
Split the policy. Keep an admin policy `using (is_team_admin(team_id)) with check (is_team_admin(team_id))`, and make the self-branch column- and value-restricted: a member may only touch their own non-privileged columns. Since Postgres RLS is row-level, enforce it either with a BEFORE UPDATE trigger that raises when `new.role is distinct from old.role or new.team_id is distinct from old.team_id or new.profile_id is distinct from old.profile_id` and the caller is not `is_team_admin(old.team_id)`, or drop the self-UPDATE branch entirely and route the only legitimate self-edit (team_members.bats) through a SECURITY DEFINER RPC. Note the Flutter app's `setMemberRole` (app/lib/src/features/identity/data/identity_repository.dart:81) writes `role` directly and relies on this policy, so it must move to an admin-gated RPC as part of the fix.

**Skeptic's note**  
Airtight. Confirmed at backend/supabase/migrations/20260615140901_team_members_rls.sql:2 (grant select,insert,update,delete to authenticated) and :13-16 (using/with check `is_team_admin(team_id) or profile_id = auth.uid()`). No later migration alters these policies (grep over all 145 files: only 20260617122000_anon_read_viewer.sql:33 adds an anon SELECT policy), and there is no BEFORE UPDATE trigger on team_members anywhere. is_team_admin is SECURITY DEFINER over the same table (20260615140601_authz_helpers.sql:16-29), so the forged row is instantly authoritative. Reproduced live inside a rolled-back transaction as role authenticated with request.jwt.claims for a non-member: is_team_admin(victim_team)=f -> `update team_members set team_id=<victim>, role='admin' where id=<my own row>` -> UPDATE 1 -> is_team_admin(victim_team)=t -> `update teams set name='PWNED' where id=<victim>` -> UPDATE 1. The unique index team_members_unique_profile (20260615140501:19-21) does not block it because the attacker is not already in the victim team. One correction to the write-up's scope: the follow-on `delete from team_members where id=<victim captain row>` is not universally available - it failed here with match_squad_team_member_id_fkey (match_squad references team_members(id) with no cascade), so evicting a captain only works for members with no squad history. Everything else in the failure path stands. The app's own setMemberRole (app/lib/src/features/identity/data/identity_repository.dart:83-84) does write role directly and depends on this policy, so the fix note is accurate.

---

## HIGH

### [high] Hardcoded dev@pitch.local/password123 is a live account on the HOSTED production project and ships in the release binary

- **id**: `hardcoded-prod-credentials-signin` | **front**: Client-side security | **category**: secrets/auth | **runs**: 1+2
- **where**: `app/lib/src/features/auth/presentation/sign_in_screen.dart:22`

**Evidence**

```
app/lib/src/features/auth/presentation/sign_in_screen.dart:22-23 (OUTSIDE the kDebugMode block that starts at line 59):
  final _email = TextEditingController(text: 'dev@pitch.local');
  final _password = TextEditingController(text: 'password123');

That account is real on the hosted project, and the repo proves it:
app/integration_test/hosted_smoke_test.dart:20-24
  expect(SupabaseEnv.url, contains('supabase.co'), reason: 'should target hosted, not 127.0.0.1');
  final c = Supabase.instance.client;
  await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
  expect(c.auth.currentUser, isNotNull, reason: 'dev signs in against hosted');

Projects/cricket-app/CLAUDE.md:39 -- "HOSTED ... ref ocejkqihgiinonpyafhl ... Anonymous sign-ins ON; dev@pitch.local + other@pitch.local seeded."
Projects/cricket-app/CLAUDE.md:77 -- "Demo login (dev-auth shim, prefilled): dev@pitch.local / password123."

And every grant in the schema is to the `authenticated` role, e.g. backend/supabase/migrations/20260615140301_profiles_rls.sql:3
  grant select, insert, update on public.profiles to authenticated;
  create policy "profiles_select_authenticated" on public.profiles for select to authenticated using (true);
```

**Failure scenario**  
Anyone who reads this repo (or runs `strings` on the release APK the friend was given -- the two literals are field initializers on _SignInScreenState, which is constructed on every visit to /sign-in, so they are NOT tree-shaken by the kDebugMode guard at line 59) posts `POST https://ocejkqihgiinonpyafhl.supabase.co/auth/v1/token?grant_type=password` with {"email":"dev@pitch.local","password":"password123"} and the publishable key. They get a real `authenticated` JWT against the production database that holds the friend's real data. With that role they can read every row of public.profiles (policy is `using (true)`), run search_players_and_teams, read discover_posts, open DM threads, create posts/teams/tournaments, and act as whatever teams dev@pitch.local captains. No brute force, no interaction with the victim.

**Root fix**  
Three separate changes, all required. (1) Delete the dev@pitch.local and other@pitch.local users from the hosted project, or at minimum rotate their passwords to a random value held only in `app/hosted_defines.json`/CI secrets, and disable the email/password provider on the hosted project (only Google/Apple/anonymous are used in production). (2) Move the two literals INSIDE the `if (kDebugMode)` guard -- make them `late final` and initialize from `const String.fromEnvironment('DEV_EMAIL')`/`DEV_PASSWORD` (empty default) so no credential string exists in a release build. (3) Make the integration tests read the same dart-defines instead of literals so the credential is never re-committed.

**Skeptic's note**  
Code claims verified exactly. app/lib/src/features/auth/presentation/sign_in_screen.dart:22-23 are field initializers on _SignInScreenState, outside the `if (kDebugMode)` at line 59; dispose() at :29-30 keeps both fields live, so the literals survive AOT tree-shaking and are in the release binary. app/integration_test/hosted_smoke_test.dart:23 confirms the account is real on hosted; CLAUDE.md:39 and :77 confirm seeding + the password. profiles_rls.sql:3-9 confirms the table-wide grant and `using (true)` select.

SEVERITY CORRECTED critical -> high, because the finding overstates the INCREMENTAL capability. CLAUDE.md:39 says anonymous sign-ins are ON, app/lib/src/core/auth/auth_providers.dart:45,61 call signInAnonymously(), and Supabase anonymous sessions carry role=authenticated. `grep -rn is_anonymous backend/supabase/migrations` returns no policy that distinguishes them. So 'read every row of profiles, run search_players_and_teams, read discover_posts, create posts/teams/tournaments' is ALREADY reachable by anyone holding the publishable key with no credential at all. The credential's true incremental value is impersonation of the specific dev@pitch.local identity (its teams, DM threads, matches, captain rights) on a DB with real data - real account takeover, but not a new class of read access.

---

### [high] restamp_innings_strike rewrites every delivery row unconditionally while a per-row broadcast trigger fires on each one, so one ball correction emits hundreds of realtime messages and triggers a full re-fold per message on every connected viewer

- **id**: `corrections-broadcast-storm` | **front**: Completeness critic (missed by all fronts) | **category**: realtime-write-amplification | **runs**: critic
- **where**: `backend/supabase/migrations/20260706110300_restamp_v14_events.sql:25`

**Evidence**

```
restamp writes every row in the innings, changed or not:
  20260706110300_restamp_v14_events.sql:24-25
    `for d in select * from public.deliveries where innings_id = _innings_id order by seq loop`
    `  update public.deliveries set striker_id = _facing, non_striker_id = _facing_ns where id = d.id;`
Every one of those UPDATEs fires an unfiltered per-row broadcast:
  20260616202201_broadcast.sql:23-25
    `create trigger deliveries_broadcast after insert or update or delete on public.deliveries for each row execute function public.broadcast_delivery_change();`
  and broadcast_delivery_change calls `realtime.broadcast_changes('match:' || _match_id, tg_op, ...)` -> one row into realtime.messages per delivery. (Contrast the matches trigger, which IS filtered: `when (old.status is distinct from new.status or old.result is distinct from new.result)`.)
Both correction writers call restamp: 20260705120100_corrections_apply_guard.sql:32 (edit_ball) and :58 (insert_ball); delete_ball also does (20260623130000_restamp_strike.sql:81).
insert_ball additionally rewrites the tail twice for the seq shuffle (20260705120100_corrections_apply_guard.sql:53-54: `update ... set seq = -(seq + 1) where seq > _after_seq;` then `update ... set seq = -seq where seq < 0;`) — each pass is another per-row broadcast.
The client fans every message out into a full re-fold with no debounce:
  match_viewer_screen.dart:86-88 `for (final op in const ['INSERT','UPDATE','DELETE']) channel.onBroadcast(event: op, callback: (_) => _refold());`
  match_viewer_screen.dart:94-100 `_refold()` invalidates matchProvider + matchInningsListProvider + inningsStateProvider for every known innings (each an O(deliveries) PL/pgSQL walk).
```

**Failure scenario**  
A scorer fixes a wide on ball 3 of a 120-ball innings via the ball log. edit_ball issues 1 real UPDATE plus 120 no-op restamp UPDATEs -> 121 rows written into realtime.messages on topic match:<id>. insert_ball at the same point is worse: 117 + 117 renumber UPDATEs + 1 INSERT + 121 restamp UPDATEs = 356 broadcasts. Each connected watcher's _refold() runs per message: 2 REST reads + one compute_innings_state RPC per innings, i.e. ~350-1400 requests per viewer per single correction, each RPC re-walking the whole delivery stream. On the hosted project (real users on a release APK) a handful of corrections during one match burns the realtime message quota and pins the DB; watchers see the score flicker/stall for seconds.

**Root fix**  
Two independent fixes, either of which caps the blast radius; do both. (1) Make restamp a no-op write: change the loop body to `update public.deliveries set striker_id = _facing, non_striker_id = _facing_ns where id = d.id and (striker_id, non_striker_id) is distinct from (_facing, _facing_ns);` so only genuinely re-stamped rows are touched. (2) Filter the trigger to material changes, mirroring the matches trigger: recreate deliveries_broadcast with `when (tg_op <> 'UPDATE' or old.* is distinct from new.*)` — or better, drop the per-row broadcast for restamp entirely by having edit_ball/insert_ball/delete_ball emit ONE explicit statement-level `realtime.broadcast_changes('match:'||_m, 'UPDATE', ...)` after the restamp completes. Also debounce _refold in match_viewer_screen.dart (coalesce bursts on a ~250ms timer).

---

### [high] A tied (or no-result) semifinal/final permanently bricks the tournament bracket: advance_playoffs demands a non-null winner and nothing in the app can reset, re-score, or delete the fixture

- **id**: `tour-tied-knockout-bricks-bracket` | **front**: Completeness critic (missed by all fronts) | **category**: product-loop-deadlock | **runs**: critic
- **where**: `backend/supabase/migrations/20260625150800_rpc_advance_playoffs.sql:20`

**Evidence**

```
advance_playoffs reads only the winner id:
  20260625150800_rpc_advance_playoffs.sql:14-21
    `select (m.result->>'winner_team_id')::uuid into _sf1w ... where tm.bracket_slot = 'SF1' and m.status = 'complete';`
    `if _sf1w is null or _sf2w is null then raise exception 'semifinals are not complete';`
  and :30-32 for the final: `if _fw is null then raise exception 'final is not complete';`
A tie is a normal outcome that stores winner=null: compute_innings_state emits `result_type='tie','winner_team_id',null` when the chase ends level (20260706110100_fold_v14_events.sql, `if _runs = _target - 1 then _result := jsonb_build_object('result_type','tie','winner_team_id',null)`), scoring_console_screen.dart:645-651 forwards it verbatim to set_match_result, and set_match_result forces winner->null for 'tie' (20260706111600_potm_persist.sql) and sets status='complete'.

There is no recovery path in the app:
  * set_match_result refuses a second call — 20260706111600_potm_persist.sql:20 `if _st in ('complete','abandoned') then raise 'this match already has a final result'`
  * delete_match refuses tournament fixtures — 20260702130000_rpc_delete_match.sql:16 `raise exception 'a tournament match cannot be deleted here'`
  * no RPC writes 'tie_superover' or resets matches.status
  * the organizer UI actively invites the failing tap: manage_tournament_screen.dart:143-153 computes `semisDone = semis.every((f) => f.isComplete)` where Fixture.isComplete is `status == 'complete' || status == 'abandoned'` (tournament_models.dart:166), so "Advance to final" is ENABLED and then throws 'semifinals are not complete'.
```

**Failure scenario**  
SF1 finishes level (chase ends on target-1). Console shows "Match tied", scorer taps "Finish match & view scorecard" -> matches.status='complete', result.winner_team_id=null. Organizer opens Manage tournament: both semis show "Done", "Advance to final" is enabled; tapping it SnackBars 'semifinals are not complete' every single time. The organizer cannot re-set the result, cannot delete or replay the fixture, and cannot crown a champion — the tournament is frozen in 'playoffs' forever. Same dead end if the final ties (tournaments.status never reaches 'complete', champion_team_id stays null).

**Root fix**  
Two parts. (1) In advance_playoffs, treat a no-winner knockout explicitly instead of reporting it as incomplete: when a semi/final row has `status='complete'` but a null winner_team_id, raise a distinct actionable error (e.g. 'SF1 was tied - record the super-over/eliminator result to break it') and add an organizer-gated way to break it, e.g. an `_override_winner` argument or a `resolve_tied_fixture(_match_id, _winner_team_id)` RPC that validates the winner is one of the two teams and writes result_type='tie_superover'. (2) Give the organizer a re-score escape hatch: allow set_match_result to be re-applied on a tournament fixture by the tournament organizer (or add `reopen_match(_match_id)` that clears result/potm and sets status back to 'live'), and change manage_tournament_screen's semisDone/allDone to require a real winner rather than just isComplete so the UI cannot enable an action the server always rejects.

---

### [high] Editing any ball in the ball log silently destroys its penalty runs, wagon-wheel shot and overthrow/crossed flags

- **id**: `balllog-edit-wipes-penalty-and-wagon` | **front**: Error handling & dead ends | **category**: data-loss | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/data/match_providers.dart:113`

**Evidence**

```
inningsDeliveriesProvider selects `'id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat, extra_wides, extra_no_ball_penalty, extra_byes, extra_leg_byes, is_legal, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id'` - `extra_penalty` is NOT in the list. `_BallEdit.fromDelivery` (ball_log_screen.dart:337-352) then reads `penalty: n('extra_penalty')` which resolves to 0, so `_penalty = widget.initial.penalty > 0` (line 416) is always false. MatchRepository.editBall (app/lib/src/features/scoring/data/match_repository.dart:201-232) never passes wagon_x/wagon_y/wagon_zone/crossed/is_overthrow/overthrow_crossed/commentary_text, and edit_ball is a FULL overwrite: `update public.deliveries set ... crossed=_crossed, is_overthrow=_is_overthrow, wagon_x=_wagon_x, wagon_y=_wagon_y, wagon_zone=_wagon_zone, commentary_text=_commentary_text` with all of those defaulting to null/false (backend/supabase/migrations/20260616202001_rpc_corrections.sql).
```

**Failure scenario**  
A scorer records a 4 with +5 penalty runs and taps the wagon-wheel to place the shot. Later they open Ball log, tap that ball, change the runs from 4 to 3, and Save. edit_ball writes extra_penalty=0, wagon_x=NULL, wagon_y=NULL, wagon_zone=NULL, is_overthrow=false. The team's total silently drops by 5, the shot vanishes from the viewer's wagon wheel, and nothing tells the scorer. The ball log's own `_outcome()` (line 110) also reads the missing `extra_penalty`, so the row never displayed 'Pen+5' in the first place - the scorer cannot even see what they are about to lose.

**Root fix**  
Add `extra_penalty, extra_overthrow-related columns, wagon_x, wagon_y, wagon_zone, crossed, is_overthrow, event_kind` to the inningsDeliveriesProvider select; surface penalty in _BallEdit/_outcome; and have MatchRepository.editBall pass through the existing wagon/crossed/overthrow values so a full-overwrite RPC does not zero them. Alternatively make edit_ball patch-style (COALESCE against the current row) for the fields the UI does not own.

**Skeptic's note**  
Verified end to end. inningsDeliveriesProvider (match_providers.dart:118-121) does not select extra_penalty, wagon_x/y/zone, crossed, is_overthrow, prevented_catch or overthrow_crossed; _BallEdit.fromDelivery reads n('extra_penalty') -> 0 (ball_log_screen.dart:346) so `_penalty` starts false (line 416) and _outcome's 'Pen+$pen' branch (line 116) is dead. MatchRepository.editBall (match_repository.dart:201-232) passes none of the wagon/crossed/overthrow params, and the live edit_ball body is the FULL overwrite in 20260705120100_corrections_apply_guard.sql (supersedes 20260616202001 / 20260623130000) which sets crossed=_crossed, is_overthrow=_is_overthrow, wagon_x/y/zone and commentary_text from params defaulting to null/false. Both lost states are reachable from the console: penalty via the extras sheet '+5 penalty runs', wagon via _promptWagon -> setDeliveryWagon, is_overthrow/crossed via the extras + run-out flows. Severity lowered from critical only because it requires the scorer to edit a ball that carried one of those attributes; when it fires it is silent, unannounced data loss (total drops by 5, shot vanishes, run-out crossed flag lost -> restamp_innings_strike changes strike).

---

### [high] Resuming match setup always dies on a raw duplicate-key error - the match is permanently stuck in 'setup'

- **id**: `squads-resume-duplicate-key-deadend` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/match_squads_screen.dart:29`

**Evidence**

```
MatchSquadsScreen keeps `final Set<String> _selected = {};` (line 22) and never reads the match's EXISTING squad. `_next()` (line 29) blindly loops `await repo.addSquadMember(...)` for every picked member (lines 46-57). The table enforces `unique(match_id, team_member_id)` (backend/supabase/migrations/20260616200601_match_squad.sql:11) and `add_squad_member` is a plain `insert ... returning id` with no ON CONFLICT (20260616200602_rpc_add_squad_member.sql). The catch at line 59 renders the raw exception: `setState(() => _error = 'Could not save the squads: $e');`
```

**Failure scenario**  
Scorer creates a match, picks squads, taps 'Next: toss' (rows commit), then backs out / kills the app / the toss step fails. Match status is still 'setup'. From Matches they tap the tile or 'Resume setup' -> MatchSquadsScreen with an EMPTY selection -> they re-pick the same XI -> 'Next: toss' -> the very first addSquadMember hits 23505 and the screen shows `Could not save the squads: PostgrestException(message: duplicate key value violates unique constraint "match_squad_match_id_team_member_id_key", code: 23505, ...)`. There is no way past this screen ever again for that match - the only escape is deleting the match. The same trap hits every tournament fixture, because ManageTournamentScreen routes an upcoming fixture to Routes.matchSquads (manage_tournament_screen.dart:301-305). A partial failure mid-loop (member 7 of 11 fails) bricks the match identically on the retry.

**Root fix**  
Load the existing match_squad rows into `_selected`/`_teamOf`/`_captainOf`/`_keeperOf` on mount (matchSquadProvider already exists), and make the save a diff: delete removed rows, insert new ones. Root-fix `add_squad_member` to `on conflict (match_id, team_member_id) do update set batting_order=..., is_captain=..., is_wicket_keeper=...` so the whole flow is idempotent.

**Skeptic's note**  
Mechanism verified. match_squads_screen.dart:22 `_selected = {}` is never seeded from matchSquadProvider (which exists, match_providers.dart:42); `_next` loops addSquadMember (49-57); 20260616200601_match_squad.sql:11 has `unique(match_id, team_member_id)`; 20260616200602_rpc_add_squad_member.sql is a bare insert with no ON CONFLICT and no later migration redefines it (grep over all 145 migrations: add_squad_member appears in that one file only). Resume paths confirmed: matches_screen.dart:162 (tile tap) and :176 ('Resume setup'), plus manage_tournament_screen.dart:304 for upcoming fixtures. Two corrections that lower it from critical: (a) the match is not 'permanently stuck' for casual matches - the same popup menu offers 'Delete match' (matches_screen.dart:154) and the user can also pick a disjoint set of never-saved members; (b) it needs an interrupted/failed first save, not the normal happy path. It IS worse than stated for tournament fixtures, where deleteMatch is blocked for tournament matches (match_repository.dart:303) so a bricked fixture also blocks 'Generate playoffs'.

---

### [high] Ball-log edit silently destroys penalty runs, the run-out `crossed` flag, overthrow flag and wagon shot, because edit_ball is a full overwrite and the caller never round-trips those columns

- **id**: `balllog-edit-drops-penalty-crossed-wagon` | **front**: Flutter state & lifecycle | **category**: data-loss | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/data/match_providers.dart:118`

**Evidence**

```
`inningsDeliveriesProvider` select list (L117-123) is:
`'id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat, extra_wides, extra_no_ball_penalty, extra_byes, extra_leg_byes, is_legal, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id'` — **`extra_penalty` and `event_kind` are absent**.
`ball_log_screen.dart:346` `penalty: n('extra_penalty')` → always 0; L416 `late bool _penalty = widget.initial.penalty > 0;` → always false; L612 `penalty: _penalty ? 5 : 0` → 0.
`match_repository.dart:201-232` `editBall` never sends `_crossed`, `_prevented_catch`, `_is_overthrow`, `_overthrow_crossed`, `_wagon_x/_y/_zone`, `_commentary_text`, yet `20260705120100_corrections_apply_guard.sql` `edit_ball` unconditionally writes `crossed=_crossed, prevented_catch=_prevented_catch, is_overthrow=_is_overthrow, overthrow_crossed=_overthrow_crossed, wagon_x=_wagon_x, wagon_y=_wagon_y, wagon_zone=_wagon_zone, commentary_text=_commentary_text` from their null/false defaults. The repository comment at L198-200 claims "callers pass the complete intended state of the ball" — they do not.
```

**Failure scenario**  
Score a ball via Extras with "+5 penalty runs on this ball" (scoring_console L267-274 → `_record(..., penalty: 5)`). Open the ball log, tap that ball → "Edit this ball" → change nothing → Save. `edit_ball` writes `extra_penalty=0`: 5 runs vanish from the innings total permanently, with no visible cause (the log never rendered "Pen+5" either, since `_outcome` L110 also reads the unselected column). Same tap sequence on a run-out where "Batters had crossed" was recorded: `crossed` is reset to null, and `restamp_v14_events.sql:57` (`if _is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed,false)`) then re-stamps the striker for every subsequent delivery on the wrong end — the rest of the innings is credited to the wrong batter. Editing any ball that had a wagon-wheel shot deletes the shot.

**Root fix**  
Add `extra_penalty, event_kind, crossed, prevented_catch, is_overthrow, overthrow_crossed, wagon_x, wagon_y, wagon_zone, commentary_text` to the `inningsDeliveriesProvider` select, thread them through `_BallEdit`/`_BallEditorSheet`, and pass them all in `MatchRepository.editBall` so the "full overwrite" contract is actually satisfied (or change `edit_ball` to a COALESCE patch).

**Skeptic's note**  
Confirmed with a small correction. match_providers.dart:117-123 select list verified verbatim — `extra_penalty`, `event_kind`, `crossed`, `prevented_catch`, `is_overthrow`, `overthrow_crossed`, `wagon_x/y/zone`, `commentary_text` are all absent. ball_log_screen.dart:346 `penalty: n('extra_penalty')` → 0; :416 `late bool _penalty = widget.initial.penalty > 0` → false; :612 `penalty: _penalty ? 5 : 0` → 0; :110 `pen` in `_outcome` → 0 so 'Pen+5' never renders either. match_repository.dart:199-231 `editBall` sends none of the missing columns. 20260705120100_corrections_apply_guard.sql:24-31 confirmed as an unconditional full overwrite writing `crossed=_crossed, prevented_catch=_prevented_catch, is_overthrow=_is_overthrow, overthrow_crossed=_overthrow_crossed, wagon_x/y/zone, commentary_text` from their null/false defaults; no later migration redefines edit_ball (only 20260616202001, 20260623130000, 20260705120100 define it). The capture side is real: scoring_console_screen.dart:267-274/291 records penalty=5, :1248 `crossed: _needsCrossedRuns(type) ? crossed : null`, :152 `setDeliveryWagon`. restamp_v14_events.sql:57 `if _is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed,false)` confirmed — nulling `crossed` re-stamps the wrong end for every later delivery. CORRECTIONS: `commentary_text` is never written by the app (grep: zero call sites), so that column is inert; `prevented_catch` likewise. Severity high rather than critical: it needs a deliberate correction action on a specific ball, and the wagon/penalty loss is recoverable by re-entering.

---

### [high] Undo of an over-completing ball permanently blocks re-selecting the bowler who must finish that over, and the server cannot catch the wrong pick

- **id**: `console-undo-blocks-correct-bowler` | **front**: Flutter state & lifecycle | **category**: state-machine | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:829`

**Evidence**

```
`_afterBall` L41-49: `if (legal > 0 && legal % bpo == 0) { setState(() { _lastOverBowlerId = _bowlerId; _bowlerId = null; }); }`.
The Undo button L828-838 never touches either field:
```dart
_Btn(label: 'Undo', onTap: () async {
  try { await _repo.undoLastBall(inningsId); } catch (e) { _toast('Could not undo: $e'); }
  ref.invalidate(inningsStateProvider(inningsId));
}),
```
`_pickBowler` L1021-1036 hard-blocks that id: `final lastOver = id == _lastOverBowlerId; ... enabled: !blocked, ... onTap: blocked ? null : ...` with no override. `_lastOverBowlerId` is only cleared in `_startSecondInnings` (L686).
Server side, `20260706110600_record_ball_cap_stale.sql` only runs the consecutive-over/cap guards inside `if _legal_count > 0 and (_legal_count % _bpo) = 0` — after the undo the count is 5, so a mid-over bowler switch is accepted silently.
```

**Failure scenario**  
6-ball over. Tap 1,1,0,4,0 then 2 (6th legal ball) → `_afterBall` clears `_bowlerId` and sets `_lastOverBowlerId = Bowler A`. The scorer realises the last ball was wrong and taps Undo. The innings is now 5 legal balls with A mid-over, but the pad is disabled (`_bowlerId == null`) and the picker shows A greyed out with "Bowled last over". The only tappable option is Bowler B; picking B and recording the 6th ball passes every server guard (`5 % 6 != 0`), so B is credited with a ball and any runs/wicket from A's over. Bowler figures and the maiden/economy columns are corrupted for the rest of the match, with no error shown.

**Root fix**  
On successful `undoLastBall`, re-read the fold and recompute the over boundary the same way `_afterBall` does: if `legal % bpo != 0`, restore `_bowlerId = _lastOverBowlerId` and clear `_lastOverBowlerId`. Route Undo through the same post-write recompute as `_record` instead of a bare invalidate.

**Skeptic's note**  
Core defect confirmed, but the tap sequence as written is not reachable and 'permanently' is wrong. Confirmed: scoring_console_screen.dart:41-49 sets `_lastOverBowlerId = _bowlerId; _bowlerId = null` at the over boundary; the Undo `_Btn` (~:829-838) only calls `undoLastBall` + `ref.invalidate` and never touches either field; :1021-1036 `final lastOver = id == _lastOverBowlerId; final blocked = atCap || lastOver; enabled: !blocked, onTap: blocked ? null : ...` with no override; `_lastOverBowlerId` is written only at :45 and cleared only at :686 (`_startSecondInnings`). Server side 20260706110600_record_ball_cap_stale.sql:73 confirmed — the consecutive-over and cap guards are both inside `if _legal_count > 0 and (_legal_count % _bpo) = 0`, so a mid-over bowler swap at 5 legal balls is accepted silently. CORRECTION 1: the scorer cannot 'tap Undo' immediately after the over completes — the Undo button lives inside `_pad`, which is wrapped in `AbsorbPointer(absorbing: _bowlerId == null || _busy)` (:512-513) with a GestureDetector above it that instead toasts 'Pick a bowler to start the over' and opens the picker (:505-511). They must first pick a bowler, and A is greyed out, so they are funnelled into picking the WRONG bowler B before Undo becomes tappable — which makes the corruption more likely, not less, but the reproduction steps in the finding are wrong. CORRECTION 2: the block is not permanent — :45 reassigns `_lastOverBowlerId` at the next over boundary, so A becomes selectable again after the following over completes. Keeping high: silent, unflagged bowler-figure corruption on a funnelled path.

---

### [high] compute_innings_cards and restamp_innings_strike hardcode squad_size=11 while compute_innings_state derives it from match_squad - the three folds disagree on all-out

- **id**: `fold-squad-size-divergence` | **front**: Scoring fold correctness | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110200_cards_v14_events.sql:23`

**Evidence**

```
cards_v14 line 23:  `coalesce((m.rules->>'squad_size')::int, 11), coalesce((m.rules->>'last_man_stands')::boolean, false)`
restamp_v14 (20260706110300_restamp_v14_events.sql:15): identical hardcoded 11.
fold_v14 (20260706110100_fold_v14_events.sql:34): `coalesce((m.rules->>'squad_size')::int, nullif((select count(*)::int from public.match_squad ms where ms.match_id = i.match_id and ms.team_id = i.batting_team_id), 0), 11)`
All three then do `_all_out := case when _lms then _squad_size else _squad_size - 1 end;` and gate their loop on `if _wickets >= _all_out then _ended := true` (fold:160, cards:140, restamp:77).
SCOR-10 (20260701140000_fold_v12_squad_size.sql) fixed ONLY compute_innings_state; the lockstep partners were never updated, and v14 copied the divergence forward. Test 82-fold-real-squad-allout.test.sql asserts the state fold only - no test compares cards/restamp.
The app never writes rules.squad_size (only `{'max_overs_per_bowler': ...}` at app/lib/src/features/scoring/data/match_repository.dart:25) and the squad picker accepts any size >= 2 per team (app/lib/src/features/scoring/presentation/match_squads_screen.dart:33-36), so squad_size != 11 is the normal case for this app.
PROVEN against the live local DB (13-player batting squad, 10 wickets, then 2 more deliveries):
  STATE  runs=7 wickets=10 legal=13 status=in_progress ; bowler legal_balls=13
  CARDS  batting-runs-sum=0 ; bowler legal_balls=10
  RESTAMP stamped deliveries 11 and 12 with the SAME striker even though delivery 11 was a single (fold rotates strike, restamp froze at _ended).
```

**Failure scenario**  
A team registers 12 or 13 players in the match squad (the wizard allows it; no cap exists). compute_innings_state uses all_out = 12 and keeps folding; compute_innings_cards uses all_out = 10 and stops at the 10th wicket. Every delivery after the 10th wicket is silently dropped from the scorecard, from player_career_stats / player_recent_form (20260623142000:45, 20260623143000:29), from compute_match_potm (20260706111600_potm_persist.sql:53) and from tournament_leaderboard (20260702150300:12) - while the live scoreboard, the result and the NRR keep counting them. Measured: scoreboard 7 runs off 13 balls vs scorecard 0 runs off 10 balls, same innings. Mirror case: an 8-a-side squad gives state all_out = 7 but cards all_out = 10, so any delivery that ends up after the 7th wicket (via insert_ball shifting an earlier wicket in, or via record_ball, which has no innings-over guard) is counted by the scorecard and discarded by the scoreboard. restamp additionally writes wrong striker_id/non_striker_id stamps onto every delivery past its own (wrong) end point, corrupting the ball-log display after any correction.

**Root fix**  
Give compute_innings_cards and restamp_innings_strike the exact same squad_size expression as compute_innings_state (the `nullif((select count(*) from match_squad where match_id = i.match_id and team_id = i.batting_team_id), 0)` fallback). Better: extract the header SELECT (bpo / squad_size / all_out / max_legal / target) into one shared `_innings_fold_params(uuid)` function that all three call, so a future change cannot desynchronise them again, and add a pgTAP test that asserts sum(cards.batting.runs) + extras == state.runs and cards.bowling.legal_balls == state.legal_balls for a non-11 squad.

**Skeptic's note**  
CONFIRMED as a real lockstep divergence, and it is the ONLY end-of-innings divergence between the three folds. Verified line by line: backend/supabase/migrations/20260706110100_fold_v14_events.sql:34 derives squad_size as coalesce(rules.squad_size, nullif(count(match_squad for batting team),0), 11); 20260706110200_cards_v14_events.sql:23 and 20260706110300_restamp_v14_events.sql:15 both read coalesce((m.rules->>'squad_size')::int, 11) with no match_squad fallback. All three then compute _all_out identically (fold:39, cards:26, restamp:20) and gate on it (fold:160, cards:140, restamp:77). No later migration re-creates any of the three (greps for 'function public.compute_innings_state|_cards|restamp_innings_strike' return 20260706110100/110200/110300 as the last definitions). Reachability verified independently of the review's claims: app/lib/src/features/scoring/data/match_repository.dart:19-26 sends only _rules {'max_overs_per_bowler': ...} - never squad_size; app/lib/src/features/scoring/presentation/match_squads_screen.dart:29-37 enforces only >=2 per team, and add_squad_member (20260616200602_rpc_add_squad_member.sql:1-12) has no cap, so both squad<11 and squad>11 are reachable. Airtight failure path: a 12- or 13-player batting squad -> state all_out=11/12 keeps the pad live, cards all_out=10 stops at the 10th wicket, so every later delivery is dropped from compute_innings_cards and therefore from player_career_stats (20260623142000:45), player_recent_form (20260623143000:29), tournament_leaderboard (20260702150300:12) and persisted POTM (20260706111600:53) while the scoreboard/result/NRR count them. restamp additionally freezes the pair at its own (wrong) end point (20260706110300:24-26 stamps before the _ended check), corrupting the ball-log striker column after any correction. Severity corrected critical -> high: nothing is destroyed and every cards consumer is a function that re-folds on read, so the corruption self-heals once the expression is aligned (only matches.potm is persisted). One correction to the evidence: the small-squad mirror case is NOT independent - cards line 30 skips post-end rows exactly like the state fold, so with squad<11 the divergence only manifests once orphan rows exist (which requires the state fold to have ended earlier, i.e. this same bug, or insert_ball moving the end backwards).

---

### [high] The scoring console still offers retired_out / timed_out as record_ball wicket types, bypassing the v14 event-row model, and timed_out dismisses the striker

- **id**: `console-still-records-retirements-as-balls` | **front**: Migration safety | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:1048`

**Evidence**

```
`static const _allWicketTypes = ['bowled','caught','lbw','run_out','stumped','hit_wicket','retired_out','obstructing','timed_out','hit_ball_twice'];` (line 1046-1049), rendered as the wicket sheet's type list at line 1105 (`final types = freeHit ? _freeHitWicketTypes : _allWicketTypes;`) and submitted through `_record(... wicketType: type ...)` i.e. `record_ball`. Nothing in 20260706110000_deliveries_event_rows.sql prevents a non-event delivery from carrying wicket_type='retired_out'/'timed_out' — `deliveries_retirement_shape` only constrains rows where `event_kind = 'retirement'`. Separately `_needsWhoOut` (line 1053-1054) excludes 'timed_out', so `dismissedId = strikerId` (line 1237-1239), and fold v14 line 139 does `if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing;` — the striker again.
```

**Failure scenario**  
A scorer taps Wicket -> 'Retired out'. It goes through record_ball as a real delivery: is_legal is true, the over advances a ball, the bowler is charged a legal ball, and the batter is charged a ball faced — precisely the corruption 20260706110000 was written to eliminate, still reachable one tap away from the new Retire action. For 'Timed out' it is worse: the batter who actually failed to arrive is never named, the current striker is marked out in both the fold and the cards, and the incoming batter replaces the wrong player, so the batting card and fall-of-wickets both attribute the dismissal to an innocent batter.

**Root fix**  
Remove 'retired_out' and 'timed_out' from `_allWicketTypes` and route both through `retire_batter` (extend it with a `timed_out` kind that names the absent batter). Back it with a DB constraint so the ball path cannot express them at all: add `check (event_kind is not null or wicket_type is null or wicket_type not in ('retired_out','retired_not_out','timed_out'))` to deliveries (new rows only — see the legacy-row finding), or reject those types in record_ball.

**Skeptic's note**  
Fully confirmed. scoring_console_screen.dart:1046-1049 still lists 'retired_out' and 'timed_out' in `_allWicketTypes`; line 1105 feeds that list straight into the wicket sheet, and line 1240-1247 submits via `_record(... wicketType: type ...)` i.e. record_ball. The current record_ball (20260706110600_record_ball_cap_stale.sql:53-70) rejects only free-hit/wide-illegal types and the missing-incoming-batter case — nothing rejects retired_out/timed_out, and the only relevant CHECK, deliveries_retirement_shape (20260706110000:30-34), constrains rows where event_kind='retirement', so a plain ball row may carry these types with is_legal true (20260706110000:39-41). Result: a legal ball is consumed, the bowler is charged a ball, and the striker is charged a ball faced — exactly what 20260706110000 was written to eliminate, one tap from the new Retire action. The timed_out half is confirmed too: `_needsWhoOut` (line 1053-1054) excludes it, so dismissedId = strikerId (line 1236-1238) and fold 20260706110100:139 attributes it to `_facing` anyway. One addition the finding missed: for 'retired_out' the sheet DOES let the scorer name the non-striker, but both the fold (:139) and cards (20260706110200:116) ignore dismissed_player_id for that type and mark `_facing`, so a non-striker retired-out is attributed to the striker as well. Severity high confirmed.

---

### [high] delete_my_account() aborts with a FK violation for any user who played in someone else's match or created a team

- **id**: `delete-account-fk-violation` | **front**: Migration safety | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:46`

**Evidence**

```
`else delete from auth.users where id = _me;  -- cascades profiles + children`. The branch is chosen by `select exists (select 1 from public.matches where owner_id = _me or scorer_id = _me)` (lines 20-22), so it fires for every user who never owned/scored a match. But `profiles.id -> auth.users` is ON DELETE CASCADE and `team_members.profile_id -> profiles` is ON DELETE CASCADE, while the children of `team_members` are NO ACTION. Introspected on the live schema: `match_squad_team_member_id_fkey`, `deliveries_striker_id_fkey`, `deliveries_non_striker_id_fkey`, `innings_opening_striker_id_fkey` all have confdeltype='a'; `teams_created_by_fkey`, `team_invites_created_by_fkey`, `matches_owner_id_fkey` also 'a'. Reproduced in a rolled-back transaction on the local DB: `ERROR: update or delete on table "team_members" violates foreign key constraint "match_squad_team_member_id_fkey" on table "match_squad"`.
```

**Failure scenario**  
Alice creates a team and a match, adds Bob to the squad, and scores it. Bob owns/scores nothing, so `_has_matches` is false and the hard-delete branch runs. `delete from auth.users` cascades to profiles -> team_members, and the NO ACTION FK from match_squad blocks it. The RPC raises, the transaction rolls back, and the user's Delete Account button fails permanently with a 500. Same failure for a user who merely created a team (teams_created_by_fkey). This is one of the 63 migrations about to be pushed to the hosted DB that already has real match data, so the very first real user to try account deletion hits it.

**Root fix**  
Take the anonymize path whenever ANY dependent row exists, not just matches the caller owns/scored. Replace the `_has_matches` predicate with a check that also covers `team_members` (or, better, always anonymize and never hard-delete auth.users). If hard delete must stay, it has to first null/reassign the referencing rows or the FKs on match_squad/deliveries/innings/teams/team_invites need an explicit policy.

**Skeptic's note**  
Mechanism confirmed by reading and by reproduction. backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:20-22 picks the branch solely on `matches.owner_id = _me or scorer_id = _me`, and line 46 hard-deletes auth.users. FK actions introspected on the live schema: profiles_id_fkey -> auth.users is 'c' (cascade), team_members_profile_id_fkey -> profiles is 'c', but teams_created_by_fkey, team_invites_created_by_fkey, match_squad_team_member_id_fkey, innings_opening_striker_id/non_striker_id_fkey and all six deliveries_*_fkey -> team_members are 'a' (NO ACTION). Reproduced in a rolled-back transaction on the local DB with the *simplest* trigger, which the finding lists only as a secondary case: inserting an auth.users row + profile + `teams(created_by = me)` and then `delete from auth.users` yields `ERROR: update or delete on table "profiles" violates foreign key constraint "teams_created_by_fkey" on table "teams"`. So the cheapest real-world trigger is 'user created a team' (teams_created_by_fkey blocks the profiles cascade one level earlier than match_squad does), not 'user was in someone's squad' — both reach it. UI path exists: app/lib/src/features/profile/presentation/settings_screen.dart:105 calls the RPC. Severity corrected critical -> high: it is a hard, permanent feature failure (Delete Account returns 500 for most active users, and it is a store-compliance requirement), but the transaction rolls back atomically — no data loss, no corruption, no security exposure, and users who own/score any match correctly take the anonymize path.

---

### [high] fold v14 lockstep is broken: compute_innings_state derives squad_size from match_squad, compute_innings_cards and restamp_innings_strike still hardcode 11

- **id**: `fold-cards-restamp-squad-size-divergence` | **front**: Migration safety | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110200_cards_v14_events.sql:23`

**Evidence**

```
compute_innings_cards line 23: `coalesce((m.rules->>'squad_size')::int, 11)` and restamp_innings_strike (20260706110300_restamp_v14_events.sql:15): `coalesce((m.rules->>'squad_size')::int, 11)` — versus compute_innings_state (20260706110100_fold_v14_events.sql:34): `coalesce((m.rules->>'squad_size')::int, nullif((select count(*)::int from public.match_squad ms where ms.match_id = i.match_id and ms.team_id = i.batting_team_id), 0), 11)`. All three then do `_all_out := case when _lms then _squad_size else _squad_size - 1 end` and end the fold on `_wickets >= _all_out`. The app never writes `rules.squad_size` — the only rule it sets is `{'max_overs_per_bowler': (overs + 4) ~/ 5}` (app/lib/src/features/scoring/data/match_repository.dart:25) — so the fallback is always the one that runs, and the squad picker enforces no upper bound (app/lib/src/features/scoring/presentation/match_squads_screen.dart:34, only `a < 2 || b < 2`). The v14 header at 20260706110100_fold_v14_events.sql:9 claims 'LOCKSTEP RULE: compute_innings_cards + restamp_innings_strike updated with it'.
```

**Failure scenario**  
Verified on the live DB (rolled back): a match with a 12-player batting squad and no rules.squad_size. After 10 wickets, a six, and an 11th wicket, compute_innings_state returns runs=6, wickets=11, innings_status='completed', while compute_innings_cards returns batting runs=0, bowling wickets=10, legal_balls=10 — the scorecard silently drops everything after the 10th wicket because it thinks all_out=10 while the fold thinks all_out=11. compute_match_potm is built on the cards, so POTM is computed from the truncated innings too. restamp_innings_strike has the same 11 and therefore stops advancing strike at the wrong wicket, writing wrong striker_id/non_striker_id stamps onto the ball log after any correction.

**Root fix**  
Copy the fold's squad_size expression verbatim into compute_innings_cards and restamp_innings_strike (both need `i.match_id` / `i.batting_team_id` in the source select, which restamp does not currently pull). Better: extract the squad_size/all_out derivation into a single SQL helper (e.g. `public._innings_all_out(_innings_id)`) that all three call, so the three cannot drift again.

**Skeptic's note**  
Divergence confirmed verbatim: 20260706110200_cards_v14_events.sql:23 and 20260706110300_restamp_v14_events.sql:15 both read `coalesce((m.rules->>'squad_size')::int, 11)`, while 20260706110100_fold_v14_events.sql:34 reads `coalesce((m.rules->>'squad_size')::int, nullif((select count(*)::int from public.match_squad ...), 0), 11)`; all three then compute `_all_out` and end on `_wickets >= _all_out` (fold:39/167, cards:26/140, restamp:20/77). The app never writes rules.squad_size — match_repository.dart:22-26 sets only max_overs_per_bowler — and match_squads_screen.dart:34 only enforces >=2 per side, so the fallback always runs and any squad size != 11 diverges (a short 7-a-side squad diverges the other way: fold all_out=6, cards all_out=10). Two corrections to the finding: (1) the divergence was NOT introduced by v14 — it dates from fold v12 (20260701140000:29) which changed only compute_innings_state while 20260623140000_compute_innings_cards.sql:32, 20260701170100_cards_runout_crossed.sql:20 and 20260701170200_restamp_runout_crossed.sql:14 kept the 11; v14 merely preserved the pre-existing drift while its own header at 20260706110100:9 claims lockstep. (2) The blast radius is misstated: the app's scorecard/viewer reads compute_innings_state (match_providers.dart:106, match_viewer_screen.dart:28), so the on-screen scorecard is NOT the truncated one. compute_innings_cards feeds match_potm (20260706111600_potm_persist.sql:53), player_career_stats (20260623142000:45), player_recent_form (20260623143000:29) and tournament_leaderboard (20260625150900:13) — so POTM, career stats and leaderboards silently disagree with the displayed scorecard, and restamp_innings_strike WRITES striker_id/non_striker_id stamps derived from the wrong all_out onto the ball log after any correction. Severity high stands on the strength of the persisted wrong stamps plus permanently wrong career/POTM numbers.

---

### [high] delete_my_account() aborts with an FK violation for any user who created a team or played in a squad — the account, and all its PII, can never be erased

- **id**: `delete-account-fk-abort` | **front**: Data exposure / PII | **category**: pii-retention | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:46`

**Evidence**

```
Line 20-22 decides the path on match ownership only:
```sql
  select exists (
    select 1 from public.matches where owner_id = _me or scorer_id = _me
  ) into _has_matches;
```
Line 46, the "clean account" path:
```sql
    delete from auth.users where id = _me;  -- cascades profiles + children
```
But the cascade hits two RESTRICTing FKs:
- backend/supabase/migrations/20260615140401_teams.sql:6 `created_by uuid not null references public.profiles (id)` (no ON DELETE)
- backend/supabase/migrations/20260616200601_match_squad.sql:5 `team_member_id uuid not null references public.team_members(id)` (no ON DELETE), reached because backend/supabase/migrations/20260615140501_team_members.sql:4 is `profile_id ... on delete cascade`. Same for backend/supabase/migrations/20260616200801_deliveries.sql:5,15,16,17,26,27 and 20260616200701_innings.sql:7,8.

Reproduced twice against the running local DB (both inside BEGIN/ROLLBACK):

(a) user creates a team, never a match:
```
ERROR:  update or delete on table "profiles" violates foreign key constraint "teams_created_by_fkey" on table "teams"
DETAIL:  Key (id)=(eb63f68d-...) is still referenced from table "teams".
CONTEXT:  SQL statement "delete from auth.users where id = _me"
PL/pgSQL function delete_my_account() line 32 at SQL statement
```

(b) user joins a team by invite and is put in a match squad by someone else:
```
ERROR:  update or delete on table "team_members" violates foreign key constraint "match_squad_team_member_id_fkey" on table "match_squad"
DETAIL:  Key (id)=(ce7b033b-...) is still referenced from table "match_squad".
CONTEXT:  SQL statement "delete from auth.users where id = _me"
```

The pgTAP test that claims to cover this, backend/supabase/tests/97-delete-account.test.sql:10-18, only exercises a user who created a post and nothing else — it never creates a team or joins a squad, so it passes while the real-world case is broken.
```

**Failure scenario**  
A player installs the app, signs up, creates a team "Sunday XI" (or is simply added to a match squad by a friend who scores), then later taps Delete account. delete_my_account() raises foreign_key_violation and the whole transaction rolls back. Nothing is deleted: auth.users still holds their email/phone, profiles still holds display_name/city/handle/photo, profile_private still holds their phone number, profile_locations still holds their exact home GPS. There is no other deletion path in the codebase, so erasure is permanently impossible from the client. This is the App Store / Play Store account-deletion requirement and the GDPR erasure path, and it will fail for essentially every real user once the 63 pending migrations reach the hosted project that already has live users.

**Root fix**  
Stop relying on the auth.users cascade. Make the "clean" path do the same explicit teardown the anonymize path does, in dependency order, and re-point the RESTRICTing references first: (1) reassign or delete public.teams rows where created_by = _me (or make teams.created_by nullable with ON DELETE SET NULL); (2) for team_members rows belonging to _me that are referenced by match_squad/deliveries/innings, convert them to guests in place (`update public.team_members set profile_id = null, guest_name = 'Deleted user' where profile_id = _me`) rather than letting them cascade-delete; (3) only then delete auth.users. Simplest correct alternative: drop the two-path branch entirely and always take the anonymize path, extended to cover the rows listed in the profile-locations finding. Add pgTAP coverage for both reproductions above.

**Skeptic's note**  
Mechanism verified and reproduced. backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:19-21 branches on match ownership only; line 46 takes the `delete from auth.users` path. pg_catalog introspection of the live local DB confirms confdeltype='a' (NO ACTION) on teams_created_by_fkey, match_squad_team_member_id_fkey, innings_opening_striker/non_striker_id_fkey and all six deliveries_*_fkey, while team_members_profile_id_fkey is 'c' (CASCADE) — so the cited chain is exactly right, and no later migration alters any of them (no `drop constraint` / `on delete set null` anywhere in the 145 files). Reproduced inside BEGIN/ROLLBACK: user creates a profile + one team via create_team, then delete_my_account() raises `update or delete on table "profiles" violates foreign key constraint "teams_created_by_fkey" on table "teams"` from `PL/pgSQL function delete_my_account() line 32`. Also confirmed there is no alternative deletion path (backend/supabase has no functions/ dir; the only caller is app/lib/src/features/profile/presentation/settings_screen.dart:105). The test-coverage claim is accurate: backend/supabase/tests/97-delete-account.test.sql:10-18 creates only a profile + a post for the clean-path user.

Two corrections, neither fatal: (1) the failure is NOT silent — settings_screen.dart:108-110 catches it and shows `Could not delete: <FK error>`, so the user sees a hard error rather than a false deletion receipt (the finding's failure_scenario overstates this). (2) The RESTRICTing set is wider than cited and worth including in the fix: tournaments_organizer_id_fkey, dm_threads_created_by_fkey, team_invites_created_by_fkey and both tournament_invites FKs are also 'a', so a user who created a tournament, opened a DM thread, or minted a team invite hits the same abort.

Severity lowered from critical to high: 100% reproducible and it makes erasure impossible from the client (a store-review and GDPR blocker), but it fails loudly, corrupts nothing, and leaks nothing new.

---

### [high] discover_posts() is a sub-metre location oracle: caller-chosen probe origin plus an unclamped _radius_m defeats the 100 m coarsening and recovers a post author's exact coordinates

- **id**: `discover-posts-location-oracle` | **front**: Data exposure / PII | **category**: pii-leak-geolocation | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706111200_discover_reads_ball_type.sql:32`

**Evidence**

```
The RPC takes the probe point AND the radius from the caller, and filters with an exact PostGIS predicate:
```sql
  _lat float, _lng float, _radius_m float default 25000,          -- line 7
...
         round(extensions.st_distance(p.geog, ...st_makepoint(_lng,_lat)...) / 100.0) * 100 as approx_m,   -- line 20
...
    and extensions.st_dwithin(p.geog, ...st_makepoint(_lng,_lat)..., _radius_m)                            -- line 32
  order by p.geog operator(extensions.<->) ...                                                             -- line 33
```
approx_m rounds the distance from a point the ATTACKER supplies, so it coarsens nothing about the stored location; and _radius_m has no lower bound, making st_dwithin a boolean distance oracle of unlimited precision.

Proven against the running local DB (BEGIN/ROLLBACK). Post created at 19.076123, 72.877456; probe at 19.0700, 72.8700 (true distance 1036.89540826 m):
```
 approx_m 
----------
     1000          <- the "coarsened" value the API is supposed to expose

 radius_m  | visible 
-----------+---------
    1036.0 |       0
   1036.89 |       0
  1036.895 |       0
 1036.8955 |       1          <- flips here: distance recovered to sub-millimetre
    1037.0 |       1
```
Three such binary searches from three probe points trilaterate the stored geog exactly. This is precisely the attack backend/supabase/migrations/20260702170000_looking_for_posts_hide_geog.sql:1-6 claims to have closed ("defeat discover_posts' 100m coarsening (trilateration -> a person's home)"); dropping the table read closed only the trivial half. Posts are created from the device GPS (app/lib/src/features/discover/data/discover_repository.dart:34-66) and the discover anchor defaults to the user's saved home base (app/lib/src/features/discover/presentation/discover_screen.dart:44-49), so the leaked point is typically a home address.
```

**Failure scenario**  
Any account (see the anonymous-session finding — no signup required) calls POST /rest/v1/rpc/discover_posts in a loop: ~30 calls binary-searching _radius_m from probe A, 30 from probe B, 30 from probe C, all completing in a few seconds. The result is the exact latitude/longitude the victim's phone reported when they posted "looking for a team" — normally their home. No rate limit, no audit trail, and the victim has no signal it happened.

**Root fix**  
Never let the caller control both the probe origin and an exact-distance predicate over the raw geog. Snap the stored point server-side at write time (add a geog_coarse column quantised to a fixed ~500 m grid, populated in create_looking_for_post) and have discover_posts filter, sort and measure against geog_coarse only. At minimum, clamp _radius_m server-side to a coarse ladder (e.g. greatest(least(_radius_m, 50000), 2000), rounded to the nearest 1000), quantise the probe point (round(_lat*200)/200), drop the <-> ordering on raw geog, and rate-limit the RPC — but the write-time grid snap is the only fix that removes the oracle rather than narrowing it.

**Skeptic's note**  
Confirmed line-for-line and reproduced. backend/supabase/migrations/20260706111200_discover_reads_ball_type.sql:7 takes _lat/_lng/_radius_m from the caller with no clamp; :20 rounds st_distance from the ATTACKER's origin (so approx_m coarsens nothing about the stored point); :32 is an exact st_dwithin against the raw p.geog; :33 orders by <-> on raw geog; :36 grants execute to authenticated. Reproduced in BEGIN/ROLLBACK — post at 19.076123/72.877456, probe at 19.0700/72.8700, true distance 1036.89540826 m: approx_m returned 1000, and the st_dwithin visibility flipped 0→1 between _radius_m 1036.895 and 1036.8955, i.e. sub-millimetre recovery of the stored distance. Three probes trilaterate. The privacy claim it defeats is real: 20260702170000_looking_for_posts_hide_geog.sql:1-6 names trilateration-to-a-home as the threat it closes, and create_looking_for_post (20260706111100_posts_ball_type.sql:18-22) stores the unquantised client-supplied point.

One correction to the exploit framing: the 'no signup required' aggravation should not be attributed to anonymous sign-in. Anonymous sign-ins are actually DISABLED on the running instance (GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED=false; POST /auth/v1/signup with {} returns 422 anonymous_provider_disabled). The reason it needs no real identity is simpler and unconditional: config.toml [auth.email] has enable_signup=true with enable_confirmations=false, so a POST with a throwaway unconfirmed address returns an aud=authenticated JWT immediately — verified against the local API. The attack stands regardless of the anon-sign-in setting. Severity high confirmed.

---

### [high] DM inbox and DM thread both join the same realtime topic; the client's leaveOpenTopic silently unsubscribes one of them, killing live delivery in the open thread

- **id**: `rt-duplicate-dm-topic-kills-live-thread` | **front**: Realtime & concurrency | **category**: realtime | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_inbox_screen.dart:60`

**Evidence**

```
dm_inbox_screen.dart:57-69 keeps one channel per listed thread:
```dart
for (final id in wanted) {
  if (_subs.containsKey(id)) continue;
  c.realtime.setAuth(c.auth.currentSession?.accessToken);
  final ch = c.channel('dm:$id', opts: const RealtimeChannelConfig(private: true));
  ch.onBroadcast(event: 'INSERT', callback: (_) => ref.invalidate(dmInboxProvider)).subscribe();
  _subs[id] = ch;
}
```
dm_thread_screen.dart:72-92 opens a SECOND channel with the identical name for the thread being read:
```dart
final channel = _c.channel('dm:${widget.threadId}', opts: const RealtimeChannelConfig(private: true));
```
Both go to the same singleton RealtimeClient (app/lib/src/core/supabase/supabase_providers.dart:5 -> Supabase.instance.client; supabase-2.13.0/lib/src/supabase_client.dart:222 delegates to realtime.channel). realtime_client-2.8.0 RealtimeChannel.subscribe() calls rejoin() (realtime_channel.dart:172), and rejoin() calls socket.leaveOpenTopic(topic) (realtime_channel.dart:781). leaveOpenTopic (realtime_client.dart:510-518) is:
```dart
final dupChannel = channels.firstWhereOrNull((c) => c.topic == topic && (c.isJoined || c.isJoining));
if (dupChannel != null) { dupChannel.unsubscribe(); }
```
The route tree makes both screens live at once: app_router.dart:198-204 nests ':threadId' under 'messages', so DmInboxScreen stays mounted beneath the pushed thread.
```

**Failure scenario**  
User opens Messages, taps a conversation. DmThreadScreen._init -> _subscribe() joins 'dm:X' (channel B), then _markRead() (dm_thread_screen.dart:61-66) invalidates dmInboxProvider. The still-mounted inbox's ref.listen fires, _syncSubscriptions runs and calls c.channel('dm:X').subscribe() (channel C). subscribe -> rejoin -> leaveOpenTopic('realtime:dm:X') finds channel B (joined) and unsubscribes it. The thread the user is actively reading now has a dead channel: the other person's replies never appear until the user leaves and re-enters. Symmetrically, if the inbox subscribes first, opening the thread unsubscribes the inbox's channel for that thread, and because it stays in _subs (line 58 `if (_subs.containsKey(id)) continue;`) it is never recreated, so the inbox's unread badge/reordering for that thread is dead for the life of the screen.

**Root fix**  
Do not open two channels on one topic. Either (a) have DmThreadScreen reuse/adopt the inbox's channel (keep a single per-thread channel in a provider owning subscribe/teardown), or (b) have the inbox skip the thread currently open (and re-subscribe on pop), or (c) give the inbox a single fan-out channel per user rather than one per thread. Also drop `if (_subs.containsKey(id)) continue;` in favour of checking the channel is still joined, so a killed channel is rebuilt.

**Skeptic's note**  
Mechanism verified end to end. supabase-2.13.0/lib/src/supabase_client.dart:222 -> realtime_client-2.8.0/lib/src/realtime_client.dart:394-401 `channel()` ALWAYS constructs a new RealtimeChannel and appends it to `channels` (no topic dedupe); realtime_channel.dart:172 subscribe -> :778-785 rejoin -> realtime_client.dart:510-518 leaveOpenTopic unsubscribes the pre-existing joined/joining channel on the same topic. Route nesting confirmed at app_router.dart:198-208 (':threadId' nested under 'messages' in the discover branch), so DmInboxScreen stays mounted (maintainState) under the pushed thread. Ordering confirmed in dm_thread_screen.dart:43-57: history fetch -> _subscribe() (channel B) -> _markRead() which awaits the RPC then invalidates dmInboxProvider (line 64), which fires the inbox's ref.listen (dm_inbox_screen.dart:86-89) and creates a second 'dm:X' channel (line 60) that kills B. One nuance I checked and it does NOT save the finding: Overlay wraps routes below an opaque route in TickerMode(enabled:false) and ConsumerStatefulElement._updateTickerMode pauses only `_dependencies` (watch) subscriptions, not `_listeners`, so the inbox's ref.listen still fires while it sits under the thread route. Alternation also verified: on the second open the thread's new channel kills the inbox's cached one, and `if (_subs.containsKey(id)) continue;` (line 58) never rebuilds it.

---

### [high] A release build without --dart-define-from-file silently ships pointed at http://127.0.0.1:54321 (and Android additionally blocks it as cleartext)

- **id**: `release-defaults-to-localhost` | **front**: Build & release config | **category**: release-configuration | **runs**: 1+2
- **where**: `app/lib/src/core/config/env.dart:12`

**Evidence**

```
env.dart:9-20 — `static const String url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');` and `publishableKey ... defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'` (the local-stack key). app/lib/main.dart:8-15 consumes them with zero validation:
```dart
await Supabase.initialize(url: SupabaseEnv.url, publishableKey: SupabaseEnv.publishableKey);
```
There is no assert, no kReleaseMode guard, no host check anywhere in lib/. Reinforcing: app/android/app/src/main/AndroidManifest.xml (whole file, 47 lines) declares neither `android:usesCleartextTraffic` nor `android:networkSecurityConfig`, and targetSdk resolves to 36 (`targetSdk = flutter.targetSdkVersion`, app/android/app/build.gradle.kts:37; Flutter 3.44.2 FlutterExtension.kt sets targetSdkVersion = 36), so Android's default policy blocks all cleartext HTTP regardless.
```

**Failure scenario**  
Someone runs `flutter build apk --release` (or `--release --split-per-abi`, or an appbundle for Play) and omits `--dart-define-from-file=hosted_defines.json`. The build succeeds with no warning and produces an APK that is byte-for-byte plausible. On launch, `Supabase.initialize` points at 127.0.0.1:54321 on the handset itself; every request fails — on Android it fails at the cleartext policy layer before a socket is even attempted. The user sees generic network/loading errors on every screen with no hint that the build is misconfigured. This is the exact path used to produce the APK already handed to a friend (task #63), so the failure mode is one forgotten flag away in practice.

**Root fix**  
Make the misconfiguration impossible to ship rather than merely documented. In `SupabaseEnv`, add a `static const bool _isLocal = url.contains('127.0.0.1') || url.contains('localhost');` and in `main()` throw (or `assert` plus a hard `StateError` under `kReleaseMode`) when `_isLocal` is true in a release build: `if (kReleaseMode && SupabaseEnv.isLocalDefault) throw StateError('Release build has no SUPABASE_URL define');`. Better still, drop the `defaultValue` for `SUPABASE_URL` entirely so an unset define yields an empty string and fails loudly at init. Separately, if local-http dev on Android is ever wanted, add a debug-only `network_security_config.xml` with a `<domain-config cleartextTrafficPermitted="true">` for 10.0.2.2/127.0.0.1 referenced from `android/app/src/debug/AndroidManifest.xml`.

**Skeptic's note**  
Mechanism verified exactly as stated. app/lib/src/core/config/env.dart:10-13 has `defaultValue: 'http://127.0.0.1:54321'` and :18-21 the local `sb_publishable_...` key; app/lib/main.dart:8-15 passes both to `Supabase.initialize` with no validation. I grepped all of app/lib for `kReleaseMode`, `127.0.0.1` and `localhost`: the ONLY hit is env.dart:12 — there is genuinely no guard, assert, or host check anywhere in lib/. The Android cleartext reinforcement also holds: app/android/app/src/main/AndroidManifest.xml (47 lines) has neither `usesCleartextTraffic` nor `networkSecurityConfig`, and app/android/app/build.gradle.kts:37 is `targetSdk = flutter.targetSdkVersion`, which resolves to 36 (verified in the installed toolchain: /Users/utkarsh/development/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:34 `val targetSdkVersion: Int = 36`) — so cleartext is blocked by default (true for any targetSdk >= 28). No build script, Makefile, or CI workflow exists that would supply the flag (only app/ios/Flutter/flutter_export_environment.sh, which is generated and unrelated). SEVERITY CORRECTED critical -> high: this is a build-invocation footgun, not a defect in the shipped code path. A correctly invoked build is fully functional, nothing is corrupted, no data is at risk, and the failure is total and immediate (every screen errors) rather than silent-and-subtly-wrong. It also cannot escape to users without a human deliberately distributing an artifact they never launched once. The `defaultValue` is a deliberate dev-ergonomics choice documented at env.dart:2-6; the defect is the absence of a release-mode tripwire, not the default itself.

---

### [high] add_squad_member / match_squad_write_scorer accept an arbitrary team_id + team_member_id, letting a scorer forge permanent public career stats for players who never played

- **id**: `idor-add-squad-member-career-forgery` | **front**: RLS & authorization | **category**: idor | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260616200602_rpc_add_squad_member.sql:7`

**Evidence**

```
if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
insert into public.match_squad(match_id,team_id,team_member_id,batting_order,is_captain,is_wicket_keeper)
values (_match_id,_team_id,_team_member_id,_batting_order,_is_captain,_is_keeper)

Neither `_team_id` (is it one of matches.team_a_id/team_b_id?) nor `_team_member_id` (does it belong to `_team_id`?) is verified. The RLS policy is no better — backend/supabase/migrations/20260616200601_match_squad.sql:18-20 gates on `is_match_scorer(match_id)` only, so a direct POST /rest/v1/match_squad is equally open. The half-gate that was supposed to stop this only requires admin of ONE side: backend/supabase/migrations/20260701160000_create_match_admin_gate.sql:13-15 `if not (public.is_team_admin(_team_a) or public.is_team_admin(_team_b))`. Stats read straight off these rows: v_player_matches (20260623141000_player_views.sql:22-29) and player_career_stats (20260623142000:34,41-42).
```

**Failure scenario**  
Verified end-to-end live. Attacker with no relationship to the victim:
 1. rpc/create_team 'Attacker XI' (attacker is captain).
 2. rpc/create_match(_team_a=Attacker XI, _team_b=<victim's team>) — passes the SEC-5 gate on the attacker's own side; the victim's team is never consulted.
 3. rpc/add_squad_member(mid, <victim team>, <victim's real membership id>, 1) -> returns a uuid. (Also proven with a team that is not in the match at all: add_squad_member(mid, <unrelated team>, <unrelated member>) succeeded, producing a match_squad row whose team_id matches neither team_a_id nor team_b_id.)
 4. rpc/start_innings with the victim as opening striker — the SCOR-10/14 squad validation (20260706111400:27-32) now passes because step 3 planted the squad row.
 5. rpc/record_ball(... 'bowled', dismissed=<victim>) then rpc/set_match_result(...,'win_by_runs',...).
Result read back from the anon-granted RPC player_career_stats('<victim profile uuid>'):
  {"batting":{"runs":0,"balls":1,"ducks":1,"innings":1,"average":0.00,"strike_rate":0.00,...},"matches":1}
Before the attack it was all zeros. The victim's permanent, publicly readable career record now contains a fabricated golden duck, and there is no user-facing way to remove it.

**Root fix**  
In add_squad_member, after the scorer check, require `_team_id in (select unnest(array[team_a_id, team_b_id]) from public.matches where id = _match_id)` and `exists (select 1 from public.team_members where id = _team_member_id and team_id = _team_id)` — the same shape add_match_guest already uses (20260703180100_match_guest_validation.sql:12-17). Tighten match_squad_write_scorer's WITH CHECK the same way so the direct-table path cannot skip it. Apply the equivalent participant check to innings.batting_team_id/bowling_team_id in start_innings, and to record_ball/retire_batter's _incoming_batter_id / _dismissed_player_id / _bowler_id / _fielder_id. Separately, create_match should require consent from (or at minimum admin of) both named teams, or matches against a team you do not admin should not count toward that team's players' career stats.

**Skeptic's note**  
Confirmed. add_squad_member (20260616200602_rpc_add_squad_member.sql:7-10) checks only is_match_scorer and then inserts _team_id/_team_member_id verbatim; nothing anywhere validates that _team_id is one of matches.team_a_id/team_b_id or that _team_member_id belongs to _team_id. The direct-table path is equally open (20260616200601_match_squad.sql:16, :20-23 gate on is_match_scorer(match_id) only). No later migration recreates add_squad_member (grep across all migrations: only fold/stats files reference match_squad). Reproduced live in a rolled-back transaction: as scorer of my own match between teams A and B, add_squad_member(mid, <entirely unrelated team>, <that team's captain membership>) returned a uuid and the match_squad row persisted with a team_id matching neither team_a_id nor team_b_id. The stats path is as described: v_player_matches (20260623141000:22-29) and player_career_stats (20260623142000:33-40) key off match_squad joined to team_members.profile_id, and player_career_stats is SECURITY DEFINER granted to anon, so the fabricated line is publicly readable. start_innings' SCOR-10/14 validation (20260706111400:24-32) checks squad membership only, so the planted row satisfies it. Note the entry point is create_match's one-sided gate (20260701160000:13-15), which the attacker satisfies with their own team - correctly stated in the finding.

---

### [high] tm_write_organizer lets any user attach ANY match to a tournament they own, and update_match_schedule then trusts that link — IDOR over every non-tournament match

- **id**: `idor-tournament-matches-hijack` | **front**: RLS & authorization | **category**: idor | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260625150200_tournament_teams_matches.sql:31`

**Evidence**

```
create policy "tm_write_organizer" on public.tournament_matches
  for all to authenticated
  using (public.is_tournament_organizer(tournament_id))
  with check (public.is_tournament_organizer(tournament_id));

The WITH CHECK validates only the tournament side of the link; `match_id` is completely unvalidated (no check that the attacker owns/scores the match, nor that its teams are in the tournament). The newest RPC then derives authority from that attacker-controlled row:

backend/supabase/migrations/20260706111700_rpc_update_match_schedule.sql:9-16
  if not (
    public.is_match_scorer(_match_id)
    or exists (
      select 1 from public.tournament_matches tm
      where tm.match_id = _match_id and public.is_tournament_organizer(tm.tournament_id))
  ) then raise exception 'not authorized' ...
```

**Failure scenario**  
Attacker (no relationship to the victim at all):
 1. rpc/create_tournament — ungated, organizer_id = self.
 2. POST /rest/v1/tournament_matches {"match_id":"<victim's match>","tournament_id":"<mine>","stage":"group"} — passes tm_write_organizer.
 3. rpc/update_match_schedule {"_match_id":"<victim's match>","_scheduled_at":"2030-01-01T00:00Z","_venue":"Nowhere"}
Verified live: is_match_scorer(victim_match) = f, yet update_match_schedule returned success and the row became venue='Nowhere', scheduled_at='2030-01-01 00:00+00' (was 'Real Ground', now()+3 days). Any authenticated user can therefore rewrite the date/ground of every match in the system that is not already linked to a tournament (tournament_matches.match_id is the PK, so unlinked matches are exactly the vulnerable set — i.e. all casual matches). Secondary effect: delete_match (20260702130000_rpc_delete_match.sql:15-17) refuses to delete any match with a tournament_matches row, so the attacker also permanently blocks the victim from deleting their own match via the app.

**Root fix**  
Add the missing side of the check to the policy: `with check (public.is_tournament_organizer(tournament_id) and exists (select 1 from public.matches m where m.id = match_id and m.owner_id = (select auth.uid())))` — or, better, revoke insert/update/delete on public.tournament_matches from authenticated entirely (every legitimate write already goes through the SECURITY DEFINER generate_group_fixtures / generate_playoffs / advance_playoffs, which create the matches themselves). Independently, update_match_schedule should require the organizer path to also confirm the match was generated by that tournament (e.g. matches.owner_id = tournaments.organizer_id).

**Skeptic's note**  
Confirmed. backend/supabase/migrations/20260625150200_tournament_teams_matches.sql:27 grants full DML on tournament_matches to authenticated and :31-34 checks only is_tournament_organizer(tournament_id) - match_id is entirely unvalidated. update_match_schedule (20260706111700_rpc_update_match_schedule.sql:11-16) derives authority from that attacker-controlled link. create_tournament (20260625150300:1-16) has no gate beyond being signed in. No later migration touches these policies or grants. Reproduced live in a rolled-back transaction: as a user with is_match_scorer(victim_match)=f, create_tournament -> insert into tournament_matches(match_id=<victim live match>, tournament_id=<mine>, 'group') -> INSERT 0 1 -> update_match_schedule(...) succeeded and the row became venue='Nowhere', scheduled_at='2030-01-01 00:00+00'. The secondary claim also checks out: delete_match (20260702130000_rpc_delete_match.sql:15-17) raises for any match with a tournament_matches row, and only the attacker can delete their own tournament to clear the link, so the victim is permanently blocked from deleting their own match through the app. Severity high is justified only because match ids are enumerable (matches_select_authenticated `using (true)`, 20260616200501:3-4) so this is mass, cross-tenant and not self-repairable; the mutated fields themselves are low-value (venue/scheduled_at).

---

### [high] matches_update_scorer grants blanket column UPDATE, so a direct PATCH bypasses every guard in set_match_result (SEC-6/MTCH-3) and update_match_schedule

- **id**: `rls-matches-update-scorer-bypasses-set-result-guards` | **front**: RLS & authorization | **category**: authorization-bypass | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260616200501_matches_rls.sql:9`

**Evidence**

```
create policy "matches_update_scorer" on public.matches
  for update to authenticated
  using (public.is_match_scorer(id)) with check (public.is_match_scorer(id));

with `grant select, insert, update, delete on public.matches to authenticated;` (line 1). The policy constrains only WHICH row, never WHICH columns, so `result`, `status`, `potm`, `team_a_id`, `team_b_id`, `scorer_id`, `owner_id` and `scheduled_at` are all client-writable. Every guard the codebase claims to have added lives only inside the RPC: backend/supabase/migrations/20260706111600_potm_persist.sql:19-21 ("refuse to overwrite a match that already has a final result"), :29-31 ("the winner must be one of the two teams in this match"), :43 (freeze POTM at result time), and 20260706111700_rpc_update_match_schedule.sql:20-22 (terminal-status guard).
```

**Failure scenario**  
Verified live. Scorer finalizes their match via the RPC, then re-calling set_match_result correctly fails with 'this match already has a final result'. The equivalent direct write succeeds:
  PATCH /rest/v1/matches?id=eq.<my match>
  {"result":{"result_type":"win_by_runs","winner_team_id":"<a team NOT in this match>","note":"forged"},"potm":{"name":"Attacker","impact":9999},"status":"complete"}
  -> UPDATE 1; match_potm() (granted to anon) then returns the forged {"name":"Attacker","impact":9999} because it prefers the persisted column (20260706111600:82).
Second proof, post-hoc opponent swap on an already-completed match: `update public.matches set team_b_id='<victim team>' where id=<my completed match>` -> UPDATE 1, after which the anon-granted team_career_stats('<victim team>') returns {"played":1,"lost":1,...} for a team that never played. The same mechanism reopens a completed match's schedule and flips status back to 'live' without any of the RPC's status checks.

**Root fix**  
Revoke the blanket grant and route mutations through the already-hardened RPCs: `revoke update on public.matches from authenticated;` then add SECURITY DEFINER RPCs for the two remaining direct writers (set_toss in app/lib/src/features/scoring/data/match_repository.dart:70-74 and the schedule edit, which update_match_schedule already covers). If the grant must stay, restrict it with a column list (`grant update (toss_winner_id, toss_decision, pitch_type) on public.matches to authenticated`) plus a BEFORE UPDATE trigger rejecting changes to result/status/potm/team_a_id/team_b_id/owner_id/scorer_id from a non-definer context. The same reasoning applies to deliveries_write_scorer / innings_write_scorer, which likewise let a client skip record_ball's _expected_last_seq fence and the v14 event-row invariants.

**Skeptic's note**  
Confirmed as a real column-level write escape, with one framing correction: the actor must be the match's scorer (or owner via matches_insert_own/create_match), not 'any authenticated user' - is_match_scorer does gate the row. 20260616200501_matches_rls.sql:1 grants full DML on matches to authenticated and :9-11 restricts only the row, never the columns; no later migration revokes it (only 20260617122000 adds an anon SELECT). Reproduced live in a rolled-back transaction as the scorer of an already-complete match: set_match_result correctly raised 'this match already has a final result' (guard at 20260706111600_potm_persist.sql:19-21), while the equivalent direct UPDATE writing result, potm, status and team_b_id returned UPDATE 1, and match_potm() (definer, granted to anon, 20260706111600:80-83 prefers the persisted column) then returned the forged {"name":"Attacker","impact":9999}. The team_b_id swap does reach third parties: team_career_stats (20260703190000:6-8) counts any completed match where the team appears in (team_a_id, team_b_id), so an unrelated team gets a fabricated played/lost. High is defensible because the damage is public, permanent and cross-tenant, but note the incremental severity over findings 3 and 4 is smaller than the write-up implies - forged team-level records are already reachable through the sanctioned RPCs once tournament_teams is forged. The closing sentence about deliveries_write_scorer / innings_write_scorer is an unverified extrapolation, not part of what I confirmed.

---

### [high] tt_write_organizer allows a direct INSERT into tournament_teams, bypassing the entire SEC-8 team-consent model

- **id**: `rls-tournament-teams-consent-bypass` | **front**: RLS & authorization | **category**: authorization-bypass | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260625150200_tournament_teams_matches.sql:12`

**Evidence**

```
create policy "tt_write_organizer" on public.tournament_teams
  for all to authenticated
  using (public.is_tournament_organizer(tournament_id))
  with check (public.is_tournament_organizer(tournament_id));

plus `grant select, insert, update, delete on public.tournament_teams to authenticated;` (line 8). The consent check exists only inside the RPCs, which the table grant makes optional:
  20260702160300_rpc_join_tournament_with_token.sql:16-18  -- "the is_team_admin(_team_id) check IS the entire consent boundary"
  20260702160400_add_tournament_team_provenance.sql:14-16  -- "do NOT loosen it to an unconditional insert"
```

**Failure scenario**  
Attacker calls rpc/create_tournament (ungated), then:
  POST /rest/v1/tournament_teams {"tournament_id":"<mine>","team_id":"<any stranger's team>","group_label":"A"}
Verified live: INSERT 0 1, row present, with no is_team_admin check ever running (add_tournament_team would have raised 'you must be an admin of this team to enter it'). The attacker can enroll every team in the app into a fake tournament. Downstream, generate_group_fixtures (20260625150500:29-35) then inserts real `matches` rows for those teams with scorer_id = the attacker, which feeds the scoring engine, tournament_standings, tournament_leaderboard and — once set_match_result is called — team_career_stats and every squad member's public career record. The migration comment explicitly names this as the thing being prevented.

**Root fix**  
Mirror the RPC's consent rule in the policy: `with check (public.is_tournament_organizer(tournament_id) and public.is_team_admin(team_id))`, or (cleaner, matching the stated design) `revoke insert, update, delete on public.tournament_teams from authenticated;` so add_tournament_team / join_tournament_with_token are the only write paths. Also drop the unused delete grant on tournament_invites while there.

**Skeptic's note**  
Confirmed. 20260625150200_tournament_teams_matches.sql:8 grants insert/update/delete on tournament_teams to authenticated and :12-15 checks only is_tournament_organizer(tournament_id); the team-consent rule lives solely in the RPCs (add_tournament_team, 20260702160400:14-16 `is_team_admin(_team_id)`; join_tournament_with_token, 20260702160300:16-18), which the table grant makes optional. Reproduced live in a rolled-back transaction: create_tournament, then `insert into tournament_teams(tournament_id, team_id, group_label) values (<mine>, <stranger team>, 'A')` -> INSERT 0 1 with is_team_admin(<stranger team>)=f. The downstream escalation is real and I verified the code path: generate_group_fixtures (20260625150500:29-35) is SECURITY DEFINER and inserts matches rows directly with owner_id=scorer_id=organizer, so it entirely bypasses create_match's SEC-5 admin gate (20260701160000_create_match_admin_gate.sql:13-15) and yields attacker-scored matches between strangers' teams that feed team_career_stats (20260703190000:5-9) and player_career_stats. The 'drop the unused delete grant on tournament_invites' part of the fix is a style aside, not part of the defect.

---

### [high] The app-stamped max_overs_per_bowler can make an innings unfinishable, and test 102's own fixture is an infeasible configuration that stops one over before the dead end

- **id**: `bowler-cap-deadlocks-innings` | **front**: Stale pgTAP tests | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:92`

**Evidence**

```
record_ball_cap_stale.sql:89-94 raises `bowler has reached the % over limit` with no override. app/lib/src/features/scoring/data/match_repository.dart:25 stamps `max_overs_per_bowler = (overs + 4) ~/ 5` on every match, and app/lib/src/features/scoring/presentation/scoring_console_screen.dart:1020-1023 computes `blocked = atCap || lastOver` and sets `enabled: !blocked` on every bowler tile. `rules` is write-once: no migration and no Dart code ever updates matches.rules (grep for 'set rules' across migrations returns nothing; the only Dart read is scoring_console_screen.dart:998). tests/102-record-ball-cap-stale.test.sql:16-17 creates a 6-over match with cap 1 and only three bowlers (b1,b2,b3) - a configuration in which only 3 of the 6 overs can legally be bowled - and the test stops after over 3, so it never reaches the state it has constructed.
```

**Failure scenario**  
Reproduced: 5-over match, rules {"max_overs_per_bowler": 1} (exactly (5+4)~/5, what the app stamps), 4-player bowling squad. After 4 overs compute_innings_state reports `over=4.0, innings_status=in_progress`, then record_ball for b1/b2/b3 all raise 'bowler has reached the 1 over limit' and b4 raises 'bowler cannot bowl consecutive overs'. The innings can never be completed, the console shows every bowler tile disabled, and there is no in-app way to change the rule. Any match where (bowling squad size x ceil(overs/5)) < overs dead-ends - which for gully squads of 4-5 covers 4-over, 5-over and 10-over matches, the app's core use case.

**Root fix**  
Either derive the cap from the actual bowling-squad size at start_innings (cap = max(ceil(overs/5), ceil(overs / bowling_squad_size))), or add an update_match_rules RPC plus a console escape hatch, and add a pgTAP test that plays a full innings to the last over under the cap the app itself stamps.

**Skeptic's note**  
Confirmed and reproduced. backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:89-95 raises unconditionally at an over boundary with no override; app/lib/src/features/scoring/data/match_repository.dart:25 stamps max_overs_per_bowler=(overs+4)~/5 into every app-created match; app/lib/src/features/scoring/presentation/scoring_console_screen.dart:1020-1023,1035 sets enabled:!blocked / onTap:null for at-cap and last-over bowlers. rules is write-once in the app: grep found no migration and no Dart write to matches.rules (only the read at scoring_console_screen.dart:997-998), and there is no update_match_rules RPC. Reproduction: 5-over match, rules {"max_overs_per_bowler":1}, 2-player bowling squad -> after 2 overs compute_innings_state reports over 2.0 / in_progress and record_ball for b1 raises 'bowler has reached the 1 over limit' (b2 additionally hits the consecutive-over guard). Since match_squads_screen.dart:33 and start_innings (20260706111400:24-26) only require >= 2 players per side, a squad small enough to dead-end is creatable through the normal wizard whenever bowling_squad_size * ceil(overs/5) < overs.

Two corrections to the finding as written: (a) recovery is not literally impossible — matches_update_scorer (20260616200501_matches_rls.sql:9-11) lets a scorer PATCH matches.rules over PostgREST, and mark_innings_break/set_match_result can close the match — but there is no in-app path for any of that, so a live gully match still hard-stops mid-innings; (b) the claim that this 'covers 4-over, 5-over and 10-over matches, the app's core use case' overstates it — it needs a bowling squad small enough (e.g. 4 players at 10 overs, 3 at 4 overs), not every short match. Severity high stands on the unrecoverable-mid-match consequence.

---

### [high] edit_ball is a full-column overwrite but the corrections UI cannot read or resend extra_penalty, crossed or the wagon columns - editing any ball silently erases them

- **id**: `edit-ball-wipes-penalty-crossed-wagon` | **front**: Dart<->SQL contract | **category**: data-loss | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/data/match_providers.dart:121`

**Evidence**

```
edit_ball overwrites the whole scoring row: `update public.deliveries set runs_off_bat=_runs_off_bat, ..., extra_penalty=_extra_penalty, ..., crossed=_crossed, prevented_catch=_prevented_catch, is_overthrow=_is_overthrow, overthrow_crossed=_overthrow_crossed, wagon_x=_wagon_x, wagon_y=_wagon_y, wagon_zone=_wagon_zone, commentary_text=_commentary_text` (20260705120100_corrections_apply_guard.sql:22-30), then `perform public.restamp_innings_strike(_in);` (:33). (1) extra_penalty: the editor exposes a '+5 penalty runs' switch (ball_log_screen.dart:527-532, emitted at :612) and initialises it from `_BallEdit.fromDelivery`'s `penalty: n('extra_penalty')` (:345) - but inningsDeliveriesProvider never selects extra_penalty (match_providers.dart:119-121), so n('extra_penalty') is always 0 and the switch is always off. Confirmed the column exists on public.deliveries. (2) crossed / wagon_x / wagon_y / wagon_zone / is_overthrow / commentary_text: MatchRepository.editBall has no parameters for them at all (match_repository.dart:201-232), so the SQL defaults null/false apply. The fold reads crossed at 20260706110100_fold_v14_events.sql:117 and restamp reads it at 20260706110300_restamp_v14_events.sql:57.
```

**Failure scenario**  
A ball was recorded with +5 penalty runs (Extras sheet, scoring_console_screen.dart:267-274). Later the scorer opens the ball log to fix the off-bat runs on that same ball and saves. edit_ball writes extra_penalty=0 and the team total silently drops 5 runs with no warning. Likewise, editing a run-out that had crossed=true writes crossed=null; restamp_innings_strike then re-derives the striker/non-striker for every subsequent delivery without that crossing, flipping the strike for the rest of the innings and mis-attributing all later runs and balls faced. And any ball whose wagon-wheel shot was captured via set_delivery_wagon loses wagon_x/y/zone on the first edit, silently emptying the wagon wheel.

**Root fix**  
Add `extra_penalty, crossed, is_overthrow, wagon_x, wagon_y, wagon_zone` to the select in match_providers.dart:119-121; add `crossed`, `isOverthrow` and the wagon triple as parameters on MatchRepository.editBall and pass the loaded values back through _BallEdit so the overwrite round-trips. Alternatively make edit_ball patch-shaped (COALESCE unspecified params to the existing column value) so a partial caller cannot destroy data - but then the 'full overwrite' contract comment at match_repository.dart:198-200 must change too.

**Skeptic's note**  
Verified in full. edit_ball is unambiguously a whole-row overwrite of the scoring columns including extra_penalty, crossed, prevented_catch, is_overthrow, overthrow_crossed, wagon_x/y/zone and commentary_text (20260705120100_corrections_apply_guard.sql:22-30), followed by restamp_innings_strike (:33). (1) extra_penalty: the editor does expose a '+5 penalty runs' switch (ball_log_screen.dart:527-532) initialised as `_penalty = widget.initial.penalty > 0` (:415) from `penalty: n('extra_penalty')` (:345) - and since extra_penalty is not in the provider's select list (match_providers.dart:119-121) n() returns 0, so the switch is always off and Save writes _extra_penalty=0, silently dropping 5 runs from the team total. (2) MatchRepository.editBall (match_repository.dart:201-232) has NO crossed / isOverthrow / wagon / commentary parameters at all, so those SQL params take their defaults (crossed null, is_overthrow false, wagon_* null) on every edit. crossed is read by the strike derivation in both compute_innings_state (20260706110100:121-123) and restamp_innings_strike (20260706110300:57-59), so editing a run-out that had crossed=true inverts the strike for the remainder of the innings and mis-attributes every later run and ball faced - and it happens with no warning. wagon_x/y/zone written by set_delivery_wagon (20260623120000) are likewise nulled on the first edit. Note the doc comment at match_repository.dart:198-200 explicitly describes the full-overwrite contract, which makes this a caller that violates its own stated contract, not an unknown. Severity high is correct: silent, irreversible data loss plus downstream scorecard corruption.

---

### [high] fold v14 is NOT in lockstep: compute_innings_state derives squad_size from match_squad, compute_innings_cards and restamp_innings_strike still hardcode 11 - short-squad scorecards are corrupt

- **id**: `fold-lockstep-squad-size-divergence` | **front**: Dart<->SQL contract | **category**: fold-divergence | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110200_cards_v14_events.sql:23`

**Evidence**

```
compute_innings_state (20260706110100_fold_v14_events.sql:34): `coalesce((m.rules->>'squad_size')::int, nullif((select count(*)::int from public.match_squad ms where ms.match_id = i.match_id and ms.team_id = i.batting_team_id), 0), 11)`. compute_innings_cards (20260706110200_cards_v14_events.sql:23): `coalesce((m.rules->>'squad_size')::int, 11)`. restamp_innings_strike (20260706110300_restamp_v14_events.sql:15): `coalesce((m.rules->>'squad_size')::int, 11)`. The SCOR-10 fix (fold v12, 20260701140000) was applied only to compute_innings_state and never propagated, despite the 'LOCKSTEP RULE' comment at 20260706110100_fold_v14_events.sql:9. The app never sets rules.squad_size - createMatch writes only `{'max_overs_per_bowler': ...}` (app/lib/src/features/scoring/data/match_repository.dart:25) - and the squad wizard accepts any size >= 2 per side (app/lib/src/features/scoring/presentation/match_squads_screen.dart:34). Executed against the local DB (6-a-side squad, no rules.squad_size, 6 wickets then 6 boundary balls, all in a rolled-back txn): compute_innings_state -> runs=0 wickets=5 innings_status=completed orphaned_deliveries=7; compute_innings_cards -> a batting line of {"runs":24,"balls":6,"fours":6} plus 6 dismissed batters, i.e. it folded all 7 deliveries the state fold declared orphaned.
```

**Failure scenario**  
A 6-a-side or 8-a-side gully match (the app's target use case) is scored. compute_innings_state ends the innings at squad_size-1 wickets and marks later deliveries orphaned; the live console/viewer shows 0/5 all out. compute_innings_cards keeps folding those same deliveries, so the scorecard, player_career_stats, player_recent_form, tournament_leaderboard and compute_match_potm (which is now PERSISTED onto matches.potm by set_match_result, 20260706111600:47) all credit runs/wickets the live score never showed. restamp_innings_strike, run after every edit_ball/insert_ball/delete_ball, re-stamps striker_id/non_striker_id on those 'orphaned' rows using the wrong all-out threshold, permanently writing a different pair than the state fold derives.

**Root fix**  
Copy the compute_innings_state squad_size expression verbatim into compute_innings_cards (20260706110200:23) and restamp_innings_strike (20260706110300:15) - or better, extract it into one `public._innings_all_out(_innings_id)` helper all three call, so the lockstep is structural rather than a comment. Add a pgTAP divergence test that asserts compute_innings_state.wickets == count of dismissed lines in compute_innings_cards for a short-squad innings.

**Skeptic's note**  
The divergence is exactly as stated and I confirmed all three expressions: compute_innings_state uses `coalesce((m.rules->>'squad_size')::int, nullif((select count(*) from public.match_squad ...), 0), 11)` (20260706110100_fold_v14_events.sql:34) while compute_innings_cards (20260706110200_cards_v14_events.sql:23) and restamp_innings_strike (20260706110300_restamp_v14_events.sql:15) use `coalesce((m.rules->>'squad_size')::int, 11)`. All three then derive _all_out identically from _squad_size (:39 / :26 / :20), so a short squad gives state _all_out = n-1 and cards/restamp _all_out = 10. rules.squad_size is genuinely never written: the only writer of rules is MatchRepository.createMatch, which sets only max_overs_per_bowler (match_repository.dart:25); a repo-wide grep for squad_size in app/lib returns nothing, and the squad wizard only requires >=2 per side (match_squads_screen.dart:34-37). SCOPE CORRECTION the finding overstates: the divergence only materialises when the innings contains deliveries BEYOND the state fold's end. In the plain happy path there are none - the console hard-blocks the pad once innings_status=='completed' (scoring_console_screen.dart:389, :458) - and with no trailing rows cards folds the identical set and produces identical figures despite the wrong threshold. The reachable trigger is a correction: e.g. a 6-a-side innings played out to its overs with 4 wickets, then the scorer uses the ball log to add a forgotten mid-innings run-out (allowed - correction_wicket_guard only demands an incoming batter, 20260705120000:9-22). That makes wicket 5 land mid-innings, state ends the innings there and lists every later ball in orphaned_deliveries (the console even shows an 'N balls recorded after the innings ended' banner at :437-444), while compute_innings_cards keeps folding all of them into the scorecard, player_career_stats/recent_form/leaderboard and the now-persisted matches.potm (20260706111600). So: real defect, real path, but not the always-on corruption the write-up implies, hence high rather than critical. The restamp half is the least harmful of the three - its _all_out only decides when it stops re-deriving, and nothing consumes deliveries.striker_id authoritatively (all three folds re-derive the pair from opening_striker_id).

---

### [high] Dart sends 'byes'/'leg_byes' for _noball_secondary_kind; the Postgres enum values are 'bye'/'leg_bye' - every no-ball-with-byes is a 400

- **id**: `noball-secondary-kind-enum-mismatch` | **front**: Dart<->SQL contract | **category**: dart-postgres-contract | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:305`

**Evidence**

```
Console Extras sheet builds `nbKind` from the literal list at scoring_console_screen.dart:237-239 -> `('off_bat','The bat'), ('byes','Byes'), ('leg_byes','Leg-byes')` and sends it at :305 `noballSecondaryKind: runs > 0 ? nbKind : null`. It reaches PostgREST as `_noball_secondary_kind` (match_repository.dart:130). The SQL parameter is typed `public.noball_secondary_kind` (20260706110600_record_ball_cap_stale.sql:22) and that enum is `create type public.noball_secondary_kind as enum ('off_bat','bye','leg_bye');` (20260616200101_scoring_enums.sql:6) - SINGULAR. Verified against the running DB: `select 'byes'::public.noball_secondary_kind;` -> `ERROR: invalid input value for enum noball_secondary_kind: "byes"`. The corrections editor has the identical bug: ball_log_screen.dart:327-335 returns 'byes'/'leg_byes' and feeds edit_ball (:222) and insert_ball (:251), whose params are the same enum type (20260705120100_corrections_apply_guard.sql:8 and :43).
```

**Failure scenario**  
Scorer taps Extras -> No-ball -> "The runs came from: Byes" -> runs=2 -> Record. record_ball is called with _noball_secondary_kind='byes'. Postgres rejects the enum cast (22P02), PostgREST returns 400, and the console shows a raw error toast. The ball is never recorded. Same for Leg-byes, and for the same choices in the ball-log edit/insert sheets. Only 'off_bat' ever works, so a no-ball that went for byes/leg-byes cannot be scored at all. (A no-ball with runs==0 passes null and works, which is why smoke tests miss it.)

**Root fix**  
Map the UI keys to the enum labels before the RPC: send 'bye' and 'leg_bye'. Change the chip values in scoring_console_screen.dart:237-239 and the getter in ball_log_screen.dart:331/333 (or add a translation in MatchRepository.recordBall/editBall/insertBall). Add a pgTAP/widget test that records a no-ball+bye end to end so the enum name is pinned.

**Skeptic's note**  
Mechanism verified end to end. backend/supabase/migrations/20260616200101_scoring_enums.sql:6 defines `create type public.noball_secondary_kind as enum ('off_bat','bye','leg_bye')` (singular) and no later migration ALTERs it (grep for 'alter type public.noball' / 'add value' returns nothing). The console chip list at app/lib/src/features/scoring/presentation/scoring_console_screen.dart:237-239 uses 'byes'/'leg_byes' and passes nbKind straight through _record (:305 -> :62/:83) into MatchRepository.recordBall, which assigns it verbatim to '_noball_secondary_kind' (match_repository.dart:129-130) with no translation anywhere. The param is typed public.noball_secondary_kind in the current record_ball (20260706110600_record_ball_cap_stale.sql:22), so the enum cast fails before the body runs -> 22P02 -> 400. Same for the corrections path: ball_log_screen.dart:327-335 returns 'byes'/'leg_byes' and feeds editBall/insertBall (:222, :251) whose SQL params are the same enum type (20260705120100_corrections_apply_guard.sql:8, :43). I could not run psql locally (not installed), but the enum literal in the migration is authoritative. Severity lowered from critical to high: it is a hard, deterministic functional block with a raw error toast, not data corruption or a security issue, and the ball is simply never written (no partial/corrupt state); the scorer also has ugly workarounds (record as no-ball off_bat, or byes separately). Note the finding's own parenthetical is right that runs==0 sends null and works, which is why nothing caught it.

---

### [high] The WICKET pad offers retired_out/timed_out and sends dismissed_player_id, but all three folds ignore it and dismiss the striker instead

- **id**: `retired-out-dismisses-wrong-batter` | **front**: Dart<->SQL contract | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:1054`

**Evidence**

```
The console's wicket sheet lists `retired_out` and `timed_out` among `_allWicketTypes` (scoring_console_screen.dart:1046-1049) and treats retired_out as needing a who-is-out choice: `static bool _needsWhoOut(String t) => t == 'run_out' || t == 'obstructing' || t == 'retired_out';` (:1053-1054). On submit it sends `dismissedId = _needsWhoOut(type) && whoOut == 'non_striker' ? nonStrikerId : strikerId` to record_ball (:1237-1250). But every fold resolves the dismissed batter as `if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing;` - compute_innings_state 20260706110100_fold_v14_events.sql:139, compute_innings_cards 20260706110200_cards_v14_events.sql:116, restamp_innings_strike 20260706110300_restamp_v14_events.sql:70. retired_out/timed_out are not in that list, so dismissed_player_id is discarded. Verified on the local DB (rolled back): striker=A1, non-striker=A2, delivery with wicket_type='retired_out', dismissed_player_id=A2, incoming=A3 -> compute_innings_state fall_of_wickets = [{"dismissed_player_id":"A1"}], striker becomes A3, non_striker stays A2; compute_innings_cards marks A1 {"how_out":"retired_out","dismissed":true,"balls":1}. A2 (the batter the scorer retired) is untouched.
```

**Failure scenario**  
Scorer taps WICKET -> 'Retired out' -> picks the NON-STRIKER -> Record. The server dismisses the STRIKER: the wrong player leaves the crease, the wrong player's card shows 'retired out', fall-of-wickets names the wrong player, and the batter who actually retired keeps batting for the rest of the innings. Additionally, because this path writes a normal ball row (event_kind null, bowler_id set, is_legal true), the retirement consumes a legal delivery and a ball faced - the exact corruption SCOR-16's retire_batter event rows (20260706110400) were introduced to eliminate. The same match can therefore have two retirements recorded with contradictory ball accounting.

**Root fix**  
Remove 'retired_out' and 'timed_out' from `_allWicketTypes` in scoring_console_screen.dart:1046-1049 and route retirements exclusively through the existing 'Retire' button -> retire_batter (which writes an event row and honours _retiring_batter_id). Belt and braces: make record_ball reject wicket_type in ('retired_out','retired_not_out','timed_out') for event_kind-null rows, and/or add 'retired_out','timed_out' to the dismissed_player_id branch in all three folds.

**Skeptic's note**  
Verified. _allWicketTypes includes 'retired_out' and 'timed_out' (scoring_console_screen.dart:1046-1049), _needsWhoOut includes 'retired_out' (:1053-1054), the sheet renders the striker/non-striker choice for it (:1150-1160), and submit sends `dismissedId = _needsWhoOut(type) && whoOut == 'non_striker' ? nonStrikerId : strikerId` to record_ball (:1235-1250). All three folds honour dismissed_player_id only for run_out/obstructing - I grepped and confirmed the identical line in each: 20260706110100_fold_v14_events.sql:139, 20260706110200_cards_v14_events.sql:116, 20260706110300_restamp_v14_events.sql:70 (`else _out := _facing`). record_ball has no guard against retired_out/timed_out on a normal (event_kind null) row; its only wicket guards are the free-hit/wide legality checks and the SCOR-2 incoming-batter check (20260706110600:53-70), all of which retired_out passes. So picking the non-striker silently dismisses the striker. The finding is also right that this path writes a normal ball row, so the retirement burns a legal delivery and a ball faced - and the console simultaneously offers the correct event-row path via the 'Retire' button (:856, :964 -> retire_batter), so the same match can hold two contradictory retirement representations. Severity high is fair (silent wrong-player corruption, no error shown); not critical only because it needs the scorer to choose an unusual wicket type.

---

## MEDIUM

### [medium] Image.network renders attacker-supplied post image_urls with no host allowlist, no decode cap and no errorBuilder -- viewer IP disclosure and a decompression-bomb OOM

- **id**: `image-network-attacker-url-no-bounds` | **front**: Client-side security | **category**: untrusted-input/dos | **runs**: 1+2
- **where**: `app/lib/src/features/discover/presentation/post_detail_screen.dart:157`

**Evidence**

```
app/lib/src/features/discover/presentation/post_detail_screen.dart:151-159
  for (final url in ((p['image_urls'] as List?) ?? const []).cast<String>()) ...[
    ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(url),      // no cacheWidth, no width/height, no errorBuilder
    ),
  ],

The URLs are pure client input: backend/supabase/migrations/20260706111100_posts_ball_type.sql:12,18-22 accepts `_image_urls text[] default null` and stores `coalesce(_image_urls, '{}')` with no check that the entries are storage URLs. The app's own uploader (app/lib/src/features/discover/data/discover_repository.dart:18-31) returns a Supabase getPublicUrl, but nothing on the server requires the array to contain those.
Grep confirms zero errorBuilder anywhere in the app: `grep -rn "errorBuilder" app/lib` returns nothing; the only three network-image sites are post_detail_screen.dart:157, new_post_composer.dart:333 and initials_avatar.dart:26.
```

**Failure scenario**  
(a) IP/UA disclosure: an attacker posts image_urls = ['https://attacker.example/beacon.png'] near a target's home anchor. Every user who opens that post detail issues a direct GET from their device, handing the attacker their IP, coarse geolocation and User-Agent -- with no proxying and no consent, on a screen the discover feed encourages tapping (the feed at discover_screen.dart:14 advertises the image count, driving the tap). (b) Crash: the same field can point at a 20000x20000 solid-colour PNG that is a few hundred KB on the wire. Image.network has no cacheWidth/cacheHeight, so the engine decodes at native resolution -- 20000*20000*4 = 1.6 GB of ARGB -- and the Android process is OOM-killed the moment the post opens. Every viewer of that post crashes on open. (c) Any plain 404/timeout has no errorBuilder, so the failure is reported to FlutterError.onError and the user gets a silent grey box.

**Root fix**  
Server: constrain image_urls to the project's own storage origin inside create_looking_for_post -- reject any element not matching `^https://<project-ref>\.supabase\.co/storage/v1/object/public/post-images/` and cap array length. Client: replace `Image.network(url)` with a bounded, guarded call -- `Image.network(url, cacheWidth: (MediaQuery.of(context).size.width * MediaQuery.devicePixelRatioOf(context)).round(), fit: BoxFit.cover, loadingBuilder: ..., errorBuilder: (_, _, _) => const _BrokenImagePlaceholder())` -- and wrap it in a fixed-aspect SizedBox/AspectRatio so a hostile image cannot dictate layout.

**Skeptic's note**  
Verified. post_detail_screen.dart:151-159 is exactly `Image.network(url)` with no cacheWidth/cacheHeight, no width/height and no errorBuilder, iterating a raw server list. `grep -rn 'errorBuilder|cacheWidth|onForegroundImageError' app/lib` returns NOTHING, and the only three network-image sites are the three named (post_detail_screen.dart:157, new_post_composer.dart:333, initials_avatar.dart:26) - the grep claim is exact. Write side unvalidated: 20260706111100_posts_ball_type.sql:12,18-22 stores coalesce(_image_urls,'{}') with no element check and no length cap, and there is no CHECK on the column (20260617130000_post_attachments_columns.sql:3). Read path returns it (20260706111200_discover_reads_ball_type.sql:45).

SEVERITY CORRECTED high -> medium: both sub-failures are real (viewer-IP beacon on open; unbounded native-resolution decode of a decompression bomb -> OOM kill of every viewer), but each needs the victim to open one specific attacker-authored post, and neither yields data access or persistence. The errorBuilder sub-point (c) is cosmetic on its own.

---

### [medium] Attacker-controlled looking_for_posts.link_url is passed straight to launchUrl(externalApplication) with no scheme allowlist on either side

- **id**: `launchurl-unvalidated-scheme-link-url` | **front**: Client-side security | **category**: untrusted-input/url-handling | **runs**: 1+2
- **where**: `app/lib/src/features/discover/presentation/post_detail_screen.dart:163`

**Evidence**

```
app/lib/src/features/discover/presentation/post_detail_screen.dart:160-166
  if ((p['link_url'] as String?)?.isNotEmpty ?? false) ...[
    InkWell(
      onTap: () => launchUrl(
        Uri.parse(p['link_url'] as String),
        mode: LaunchMode.externalApplication,
      ),

No validation on the write side either -- backend/supabase/migrations/20260706111100_posts_ball_type.sql:12,18-22 takes `_link_url text default null` and inserts it verbatim; there is no CHECK constraint on the column (backend/supabase/migrations/20260617130000_post_attachments_columns.sql:4 `add column link_url text;`) and no regex/scheme test anywhere in the RPC.

The plugin does no filtering of its own:
~/.pub-cache/.../url_launcher_android-6.3.32/.../UrlLauncher.java:87-95
  Intent launchIntent = new Intent(Intent.ACTION_VIEW).setData(Uri.parse(url))...
  activity.startActivity(launchIntent);   // no CATEGORY_BROWSABLE, no scheme check
~/.pub-cache/.../url_launcher_ios-6.4.1/.../URLLauncherPlugin.swift:45-53
  launcher.open(url, options: options) { ... }   // UIApplication.open, canOpenURL is NOT consulted on this path
```

**Failure scenario**  
Any authenticated user creates a post with link_url = `upi://pay?pa=attacker@okhdfcbank&pn=Ground%20Booking&am=500&cu=INR` (or `whatsapp://send?phone=...`, `tel:`, `intent:`, `content://`, an arbitrary third-party app scheme). A victim opens the post detail, taps what the UI presents as a web link (Icons.link, link-teal text at line 169-175), and url_launcher fires an implicit ACTION_VIEW with no CATEGORY_BROWSABLE on Android / UIApplication.open on iOS. On Android the UPI app chooser opens pre-filled with the attacker's VPA and amount; because CATEGORY_BROWSABLE is never added, the intent can also reach exported activities that a real browser would refuse to launch. Secondary: `Uri.parse` on a malformed authority such as `https://[` throws FormatException synchronously inside onTap, and the returned Future is never awaited, so a PlatformException from the plugin becomes an unhandled async error.

**Root fix**  
Validate at both ends. Backend: add `alter table public.looking_for_posts add constraint link_url_http check (link_url is null or link_url ~* '^https?://')` and re-apply the check inside create_looking_for_post. Client: in post_detail_screen.dart parse defensively and gate before launching -- `final u = Uri.tryParse(raw); if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) { render as plain non-tappable text; return; }` -- then `await launchUrl(u, mode: LaunchMode.externalApplication)` inside a try/catch that shows a SnackBar on failure. Display the host separately from the path so the user can see where the tap goes.

**Skeptic's note**  
Every cited line is accurate. post_detail_screen.dart:160-175 renders link_url as a tappable Icons.link row and calls launchUrl(Uri.parse(raw), mode: externalApplication) with no scheme test and no await. Write side confirmed unvalidated: 20260706111100_posts_ball_type.sql:12,18-22 inserts _link_url verbatim; 20260617130000_post_attachments_columns.sql:4 is a bare `add column link_url text;` and `grep -rn 'link_url' backend/supabase/migrations | grep -iE 'check|constraint'` returns NOTHING. Read path confirmed to return it: 20260706111200_discover_reads_ball_type.sql:45 selects p.link_url. Plugin claim verified in ~/.pub-cache/hosted/pub.dev/url_launcher_android-6.3.32/.../UrlLauncher.java:84-95 - plain ACTION_VIEW + startActivity, no CATEGORY_BROWSABLE, no scheme filter (FLAG_ACTIVITY_REQUIRE_NON_BROWSER only when requireNonBrowser, which externalApplication does not set).

SEVERITY CORRECTED high -> medium: exploitation needs the victim to open one specific attacker-authored post and tap the link, and the payload's effect is handing an attacker-chosen URI to another installed app - the UPI example still requires the victim to confirm the payment in their own app. Real stored-untrusted-URI defect, not a high-impact one.

---

### [medium] No deep-link registration on either platform, so every shared /invite, /watch, /player and /tournament link is unopenable -- and team invites have no fallback path

- **id**: `no-deeplink-registration-shared-links-dead` | **front**: Client-side security | **category**: routing/deployment | **runs**: 1+2
- **where**: `app/android/app/src/main/AndroidManifest.xml:26`

**Evidence**

```
app/android/app/src/main/AndroidManifest.xml declares exactly one intent-filter -- MAIN/LAUNCHER (lines ~26-29). No VIEW/BROWSABLE filter, no `pitch.app` App Link, no custom scheme. The MERGED release manifest confirms nothing is contributed by any plugin either -- Projects/cricket-app/app/build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml (built from the sibling worktree) contains only the MAIN/LAUNCHER filter for MainActivity plus plugin-internal filters (gms MODULE_DEPENDENCIES, share_plus EXTRA_CHOSEN_COMPONENT, profileinstaller). app/ios/Runner/Info.plist has no CFBundleURLTypes and there is no .entitlements file at all (`find app/ios -name '*.entitlements'` is empty), so no Universal Links.

Yet the router treats these as the cold-start deep-link surface -- app/lib/src/core/routing/app_router.dart:52-61 and :104-151 hoist /watch/:matchId, /player/:profileId, /invite/:token, /join-tournament/:token and /tournament/:id to top level specifically 'so deep/share links cold-start correctly'.

The share payloads all emit https://pitch.app/... :
  app/lib/src/features/identity/data/identity_repository.dart:170  String inviteLink(String token) => 'https://pitch.app/invite/$token';
  app/lib/src/features/tournaments/data/tournament_repository.dart:83  joinTournamentLink
  app/lib/src/features/tournaments/presentation/tournament_page_screen.dart:34-37
```

**Failure scenario**  
A captain taps 'Invite player' (app/lib/src/features/teams/presentation/team_page_screen.dart:477-491). createTeamInvite mints a real single-use token server-side, then SharePlus sends 'Join my cricket team on Pitch: https://pitch.app/invite/<token>'. The recipient taps it: the OS finds no app registered for that host, opens a browser, and pitch.app serves nothing -- the invite is unredeemable and the token is burned into a chat log. Unlike tournaments (manage_tournament_screen.dart:353-355 also shares the raw code 'Or enter this code in the app'), there is NO in-app entry field for a team invite token, so InviteAcceptScreen is unreachable by any means and the entire registered-player invite flow is dead in the shipped app. A secondary dead end: app/lib/src/features/auth/data/oauth_sign_in.dart:80-84 hands Supabase `redirectTo: 'io.supabase.pitch://login-callback'` for the Android Apple flow, a scheme no filter claims -- currently masked only because sign_in_screen.dart:109 renders the Apple button on iOS only.

**Root fix**  
Register the links before shipping: add an `<intent-filter android:autoVerify="true">` with VIEW + DEFAULT + BROWSABLE and `<data android:scheme="https" android:host="pitch.app"/>` to MainActivity, publish /.well-known/assetlinks.json; add CFBundleURLTypes plus an Associated Domains entitlement (`applinks:pitch.app`) and /.well-known/apple-app-site-association for iOS; and add `io.supabase.pitch` as a scheme filter for the Supabase OAuth callback. Until the domain exists, add a 'Have an invite code?' text field to the team-invite flow mirroring manage_tournament_screen.dart:353-355, and share the raw token alongside the URL so the invite is redeemable without the deep link.

**Skeptic's note**  
Fully verified, including the part that makes it a real defect rather than a known deployment TODO. app/android/app/src/main/AndroidManifest.xml declares only MAIN/LAUNCHER (lines 26-29) - no VIEW/BROWSABLE, no scheme, no host. app/ios/Runner/Info.plist has no CFBundleURLTypes and `find app/ios -name '*.entitlements'` is empty. app_router.dart:53-61 and :104-151 do hoist /watch, /player, /invite/:token, /join-tournament/:token and /tournament/:id to top level for cold-start. Share payloads emit https://pitch.app/... (identity_repository.dart:170, tournament_repository.dart:83).

The asymmetry is the confirmed core: `grep -rn 'acceptInvite|InviteAcceptScreen' app/lib` shows Routes.acceptInvite (routes.dart:71) has ZERO call sites - the only entry to InviteAcceptScreen is the unregistered /invite/:token route (the one non-router hit is app/test/invite_accept_test.dart:26). Tournaments do have the fallback (tournaments_list_screen.dart:92-121, an 'Invite code' dialog that also accepts a pasted link), and its comment even names the reason: 'no hosted web domain yet, so a shared https link won't resolve in a browser'. Teams have no equivalent, and team_page_screen.dart:483-491 mints and shares a real token with no code shown. So the team-invite flow is genuinely unredeemable in the shipped app. The oauth_sign_in.dart:80-84 `io.supabase.pitch://login-callback` sub-point is accurate and correctly described as masked by the iOS-only Apple button (sign_in_screen.dart:105-117).

SEVERITY medium is correct as stated - keeping it.

---

### [medium] looking_for_posts.expires_at is never written by any client path and the feed applies no match-date floor, so Discover accumulates dead posts forever and ranks them by distance ahead of fresh ones

- **id**: `discover-posts-never-expire` | **front**: Completeness critic (missed by all fronts) | **category**: data-lifecycle | **runs**: critic
- **where**: `app/lib/src/features/discover/data/discover_repository.dart:32`

**Evidence**

```
The schema has the expiry field and the read path honours it:
  20260616203202_looking_for_posts.sql:15 `expires_at timestamptz,`
  20260706111200_discover_reads_ball_type.sql `where p.status = 'open' and (p.expires_at is null or p.expires_at > now())`
The RPC accepts it: 20260706111100_posts_ball_type.sql `_expires_at timestamptz default null` -> `insert into public.looking_for_posts(..., expires_at, ...) values (..., _expires_at, ...)`.
But nothing ever supplies it. DiscoverRepository.createPost (discover_repository.dart:32-69) has no expiresAt parameter at all and its params map never contains '_expires_at'; the composer's only call site (new_post_composer.dart:103-118) passes mode/flair/lat/lng/teamId/description/placeLabel/overs/skill/ballType/slotsNeeded/matchAt/imageUrls/linkUrl — no expiry. `grep -rn "expires" app/lib` returns only team-invite usages. So expires_at is NULL on every row and the filter is dead.
The date filter is also opt-in and defaults off: discover_screen.dart:31 `DateTime? _fromDate;` (never initialised), :59 `onOrAfter: _fromDate`, and discover_providers.dart:73 `if (q.onOrAfter != null) '_on_or_after': ...` — so `_on_or_after` is omitted and the SQL predicate `(_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)` matches everything.
There is no cleanup job anywhere: no cron, no pg_cron migration, no scheduled function in the 145 migrations.
```

**Failure scenario**  
A user posts "Need 2 players, Sat 3pm" with match_at = last Saturday and never taps "Mark filled" (which itself fails silently — see myposts-act-swallows-writes). Today, and a year from now, discover_posts still returns that post to every user within 25 km, and because the ordering is `order by p.geog <-> <probe>` (pure distance, not recency), a months-dead post 400 m away outranks a live post 5 km away. The Discover feed monotonically fills with matches that already happened, which is the failure mode that kills a matchmaking surface.

**Root fix**  
Three cheap changes: (1) default the expiry server-side — `alter table public.looking_for_posts alter column expires_at set default (now() + interval '14 days');` and in create_looking_for_post use `coalesce(_expires_at, coalesce(_match_at + interval '1 day', now() + interval '14 days'))` so a dated post dies the day after the match; (2) add a match-date floor to discover_posts independent of the caller: `and (p.match_at is null or p.match_at >= now() - interval '6 hours')`; (3) make recency part of the ordering, e.g. `order by (p.match_at is not null and p.match_at < now()), p.geog <-> <probe>` so anything stale sinks. Backfill existing rows with `update public.looking_for_posts set expires_at = created_at + interval '14 days' where expires_at is null;`.

---

### [medium] "Leave this team" and "Remove this player" can never succeed for anyone who has appeared in a match squad — the delete hits an unhandled FK RESTRICT and the raw Postgres error is shown

- **id**: `team-member-delete-fk-restrict` | **front**: Completeness critic (missed by all fronts) | **category**: data-lifecycle | **runs**: critic
- **where**: `app/lib/src/features/identity/data/identity_repository.dart:73`

**Evidence**

```
Both actions are direct client DELETEs on team_members:
  identity_repository.dart:73-74 `Future<void> removeMember(String membershipId) => _client.from('team_members').delete().eq('id', membershipId);`
team_members(id) is referenced with NO `on delete` action (default NO ACTION = RESTRICT-on-delete) by every scoring table:
  20260616200601_match_squad.sql:5 `team_member_id uuid not null references public.team_members(id),`
  20260616200801_deliveries.sql:5 `bowler_id uuid not null references public.team_members(id),`
  20260616200801_deliveries.sql:26-27 `striker_id ... references public.team_members(id), non_striker_id ... references public.team_members(id),`
  (plus dismissed_player_id, incoming_batter_id, fielder_id)
Grep over all 145 migrations shows no later ALTER adding ON DELETE to any of these.
The two callers surface the violation raw:
  team_page_screen.dart:281 `await repo.removeMember(myRow['id'] as String);` -> catch at :288 `Text('Could not leave: $e')`
  team_page_screen.dart:386 `await repo.removeMember(member['id'] as String);` -> catch at :394 `Text('Could not update: $e')`
Notably the sibling deleteTeam path DOES translate 23503 (team_page_screen.dart:299-306: `raw.contains('foreign key') || raw.contains('23503') ? 'This team has match history and cannot be deleted...'`), proving the authors knew about this FK class and only handled it for teams.
```

**Failure scenario**  
A player is added to a match squad once (add_squad_member -> a match_squad row) and bats a ball (deliveries.striker_id). Later they open the team page overflow menu -> "Leave this team" -> confirm. The DELETE fails with `PostgrestException(message: update or delete on table "team_members" violates foreign key constraint "match_squad_team_member_id_fkey" on table "match_squad", code: 23503)`, rendered verbatim in a SnackBar. The user is permanently unable to leave any team they have played for, and a captain can never remove an active player from the roster — including guests that add_match_guest silently wrote into the opponent's roster (20260701180000_rpc_add_match_guest.sql inserts into team_members).

**Root fix**  
Stop hard-deleting an identity that career stats are keyed on. Add a soft-departure column, e.g. `alter table public.team_members add column left_at timestamptz;`, replace removeMember with an organizer/self-gated RPC `leave_team(_membership_id)` that (a) hard-deletes only when `not exists (select 1 from public.match_squad where team_member_id = _membership_id)`, and (b) otherwise stamps left_at so history survives; then filter `left_at is null` in teamRosterProvider and the squad pickers. As an immediate stopgap, translate 23503 in team_page_screen.dart:288 and :394 the same way the deleteTeam branch at :299-306 already does.

---

### [medium] The tournament join link is single-use-then-dead and never expires — the exact bug that was fixed for team invites was left unfixed in its clone, and the share text invites broadcast sharing

- **id**: `tournament-invite-single-use` | **front**: Completeness critic (missed by all fronts) | **category**: product-loop-deadlock | **runs**: critic
- **where**: `backend/supabase/migrations/20260702160300_rpc_join_tournament_with_token.sql:22`

**Evidence**

```
Redemption flips the single shared token to terminal on the first tap:
  20260702160300_rpc_join_tournament_with_token.sql:22-25 `select tournament_id into _tid from public.tournament_invites where invite_token = _invite_token and status = 'pending'; if _tid is null then raise exception 'invite not found or already used';`
  :36-38 `update public.tournament_invites set status = 'accepted', redeemed_by = ..., redeemed_team_id = _team_id where invite_token = _invite_token;`
tournament_invites has no uses/max_uses/expires_at at all (20260702160000_tournament_invites.sql:10-19), even though its own header comment says it "reuses the invite_status enum + the exact shape of team_invites".
team_invites was explicitly fixed for precisely this: 20260703170000_team_invites_multiuse.sql:1-6 — "the shareable team invite was single-use-then-dead (first tapper consumed it for everyone) and a leaked token granted membership forever. Now an invite is MULTI-USE by default (share one link with the whole squad), EXPIRES after 7 days, supports an optional max_uses cap" — adding expires_at/max_uses/uses. The tournament clone never got that treatment.
The UI shares one token as a broadcast message: manage_tournament_screen.dart:349-354 `text: 'Add your team to my cricket tournament on Pitch: ${joinTournamentLink(token)}\nOr enter this code in the app: $token'` — a single Share sheet, no per-team minting loop.
```

**Failure scenario**  
Organizer taps "Invite a team" once and drops the link into a WhatsApp group of 6 clubs. Club 1's captain redeems it and is entered. Clubs 2-6 all get 'This invite has already been used or is no longer valid.' (join_tournament_screen.dart:60-62). The organizer has no visible signal that one link != one tournament, and must re-open Manage tournament and re-share a fresh link for every single team. Separately, a token that is never redeemed never expires: it stays valid for as long as the tournament is in setup, so a leaked link lets any team admin insert their own team.

**Root fix**  
Port the team_invites fix verbatim: `alter table public.tournament_invites add column expires_at timestamptz not null default (now() + interval '7 days'), add column max_uses int, add column uses int not null default 0;` then rewrite join_tournament_with_token to `select ... for update` (it currently has no row lock either — the confirmed tournament-token-no-row-lock finding), check `status='pending' and expires_at > now() and (max_uses is null or uses < max_uses)`, increment `uses` on a genuinely new tournament_teams row, and leave status='pending' so the link keeps working. Update the share copy to say the link works for every team.

---

### [medium] Anonymous guests are shown 'Request to join' and 'This is me' on team pages and get a raw Postgres foreign-key error

- **id**: `anon-request-to-join-fk-error` | **front**: Error handling & dead ends | **category**: anonymous-user | **runs**: 1+2
- **where**: `app/lib/src/features/teams/presentation/team_page_screen.dart:112`

**Evidence**

```
`final uid = ref.watch(currentSessionProvider)?.user.id;` (line 27) is NON-NULL for an anonymous Supabase session (anonBootstrapProvider signs one in - app/lib/src/core/auth/auth_providers.dart:39-65), so `if (uid != null && myRow == null)` (line 112) renders 'Request to join', and `onClaim: (uid != null && member['profile_id'] == null)` (line 139) renders 'This is me' on every guest row. The backend table is `requester_id uuid not null references public.profiles(id)` (backend/supabase/migrations/20260703190100_team_join_requests.sql:7) and an anonymous user has no profiles row. `_requestToJoin`'s catch (lines 200-208) only maps 'already pending' / 'already on this team' and otherwise renders `'Could not send the request: $raw'`. Anonymous users can reach the page: Profile tab (guest) -> 'Find players and teams' (profile_screen.dart:61-66) -> SearchScreen -> `context.push(Routes.teamPage(id))` (search_screen.dart:97-98), and search_players_and_teams is granted to `authenticated`, which is the role an anonymous Supabase JWT carries.
```

**Failure scenario**  
A guest opens a shared search result for a team and taps 'Request to join'. request_to_join runs as an authenticated-role anon user, the insert violates team_join_requests_requester_id_fkey, and the snackbar reads `Could not send the request: PostgrestException(message: insert or update on table "team_join_requests" violates foreign key constraint "team_join_requests_requester_id_fkey", code: 23503, details: Key (requester_id)=(...) is not present in table "profiles".)`. Same for 'This is me' (requestGuestClaim), whose catch at line 507 shows the bare `Text('$e')`.

**Root fix**  
Gate both affordances on `!ref.watch(isAnonymousProvider)` (the provider already exists) and, for anonymous viewers, replace them with a 'Sign in to join this team' button - the pattern DiscoverScreen (_SignInToDiscover) and PostDetailScreen._messageAuthor (post_detail_screen.dart:54-57) already use.

**Skeptic's note**  
Confirmed on every leg. anonBootstrapProvider signs in anonymously (auth_providers.dart:39-65) so currentSessionProvider is non-null for a guest, making team_page_screen.dart:112 render 'Request to join' and :139 render 'This is me'. Both backend targets require a profiles row: team_join_requests.requester_id references profiles (20260703190100:7) and guest_claim_requests.requested_by references profiles (20260615141301:4); request_to_join / request_guest_claim only check `auth.uid() is null`, which is false for an anon JWT, so the insert dies with 23503. The catches map only 'already pending' / 'already on this team' (200-208) and '$e' respectively (line ~508). Reachability confirmed: profile_screen.dart guest branch -> 'Find players and teams' -> search_screen.dart:97-98 push Routes.teamPage(id), search_players_and_teams is granted to authenticated (20260706111000_search_handle.sql:24), and teams/roster SELECT policies are `to authenticated using (true)` (20260615140701_teams_rls.sql:5-6). Severity medium is right.

---

### [medium] Ball log never sees event_kind, so v14 strike-swap/retirement event rows render as phantom balls and offer Edit/Insert that hit raw check-constraint errors

- **id**: `balllog-event-rows-rendered-as-balls` | **front**: Error handling & dead ends | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/ball_log_screen.dart:66`

**Evidence**

```
`final isEvent = d['event_kind'] != null;` - but inningsDeliveriesProvider (match_providers.dart:118-122) does not select `event_kind`, so `d['event_kind']` is always null and `isEvent` is always false. Consequently line 78 `bowler: isEvent ? 'between balls' : (names[d['bowler_id']] ?? '-')` always takes the else branch (bowler_id is NULL on event rows -> '-'), `_outcome`'s event branches at lines 97-103 are dead code, and the action sheet's `if (!isEvent)` guards at lines 143 and 149 always pass. The column exists: `alter table public.deliveries add column event_kind public.delivery_event;` (backend/supabase/migrations/20260706110000_deliveries_event_rows.sql:12).
```

**Failure scenario**  
A scorer uses 'Swap strike' or 'Retire', then opens Ball log. The event row appears as an extra illegal delivery ('0.3+', outcome '0', bowler '-') mixed into the over - exactly the phantom-ball confusion fold v14 was written to eliminate. Tapping it offers 'Edit this ball'; setting any runs on it makes edit_ball violate `deliveries_event_rows_zero`, and toggling Wicket off on a retirement row violates `deliveries_retirement_shape`, both surfacing through the catch at line 261 as a raw `PostgrestException(message: new row for relation "deliveries" violates check constraint ...)` snackbar.

**Root fix**  
Add `event_kind` to the inningsDeliveriesProvider select. The screen's isEvent logic is already correct once the column arrives.

**Skeptic's note**  
Column-selection claim is exactly right: event_kind exists (20260706110000_deliveries_event_rows.sql:12) but is absent from inningsDeliveriesProvider's select, so ball_log_screen.dart:66 `isEvent` is always false, the 'between balls' label (78) and the event branches of _outcome (97-103) are dead, and the `if (!isEvent)` guards (143, 149) always pass. Rendering harm confirmed: is_legal IS selected and is false for event rows (generated expression includes `event_kind is null`), so a strike_swap renders as '0.3+ / 0 / - to <striker>' and a retirement as '0 W retired out'. Two corrections that reduce severity from high: (a) the check constraints (deliveries_event_rows_zero, deliveries_retirement_shape) REJECT the bad edits, so there is no data corruption - only a raw PostgrestException snackbar via line 262; (b) 'Insert a ball after this' and 'Delete' on an event row work correctly, so the only broken action is Edit. Net effect is a misleading ball log plus an ugly error, not scorecard corruption.

---

### [medium] Undo, Swap strike and Retire are unreachable at the start of every over - the exact moment a scorer needs Undo

- **id**: `console-undo-unreachable-at-over-start` | **front**: Error handling & dead ends | **category**: unreachable-ui | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:512`

**Evidence**

```
`AbsorbPointer(absorbing: _bowlerId == null || _busy, ...)` wraps `_pad(...)` (lines 512-518), and `_pad` contains the Undo button (line 828), Swap strike (line 844) and Retire (line 855) alongside the run pad. `_afterBall` clears the bowler at the end of every over: `setState(() { _lastOverBowlerId = _bowlerId; _bowlerId = null; });` (lines 43-48). The GestureDetector above it (lines 504-511) converts every tap in that region into `_toast('Pick a bowler to start the over')` + the bowler picker, and the picker itself disables the previous over's bowler: `final lastOver = id == _lastOverBowlerId; ... enabled: !blocked` (lines 1021-1036).
```

**Failure scenario**  
Last ball of the over is mis-scored (a 4 entered as a 6). The over completes, _bowlerId goes null. The scorer taps Undo -> nothing happens except 'Pick a bowler to start the over' and a picker in which the bowler who actually bowled that ball is greyed out as 'Bowled last over'. To reach Undo at all they must select a DIFFERENT bowler; the undo then succeeds but _bowlerId is now the wrong bowler, so the re-recorded ball is credited to a bowler who never bowled it, corrupting both bowlers' figures. The same gate makes 'Swap strike' and 'Retire' - explicitly between-ball actions - impossible between overs.

**Root fix**  
Move Undo / Swap strike / Retire out of the AbsorbPointer-wrapped `_pad` into an always-enabled row (they do not need `_bowlerId`; `_record`'s `if (_bowlerId == null) return` guard only applies to actual deliveries). Gate only the run/extras/wicket pad on bowler selection.

**Skeptic's note**  
The widget-tree fact is correct: Undo (scoring_console_screen.dart:828), Swap strike (844) and Retire (855) all live inside `_pad`, which is wrapped by AbsorbPointer(absorbing: _bowlerId == null || _busy) at 512-513; _afterBall nulls _bowlerId at every over end (43-48) and _pickBowler disables _lastOverBowlerId ('Bowled last over', 1021-1036). The wrong-bowler-credit path is real: after Undo the legal count is no longer a multiple of bpo, so record_ball's consecutive-over guard (20260706110600_record_ball_cap_stale.sql) does not fire and the re-recorded ball is credited to the newly picked bowler, with the true bowler still blocked in the picker. Corrections: (a) 'Swap strike'/'Retire' are NOT effectively unreachable - picking the next over's bowler is a legitimate, expected action at that moment and unlocks them, so the between-overs claim is overstated; (b) an always-available correction path exists for the mis-scored ball - the app-bar 'Ball log / corrections' action (337) is outside the AbsorbPointer and edit_ball needs no bowler. The genuine defect is narrowed to Undo-at-over-start pushing the scorer into an incorrect bowler selection.

---

### [medium] DM thread load failure leaves a permanent spinner with no error, no retry and no realtime

- **id**: `dm-thread-permanent-spinner` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_thread_screen.dart:43`

**Evidence**

```
`initState` calls `_init()` fire-and-forget (line 40). `_init` (lines 43-57) awaits `_c.from('dm_messages').select(...)` with NO try/catch; `if (mounted) setState(() => _loading = false);` is line 53, after the await. The body's only failure state is `_loading ? const Center(child: CircularProgressIndicator.adaptive()) : ListView.builder(...)` (line 235) - there is no error branch and no retry anywhere on the screen.
```

**Failure scenario**  
The user opens a DM while offline, or the dm_messages RLS read is denied (thread they were removed from, expired token before refresh). The select throws, the future completes with an unhandled async error printed only to the console, `_loading` stays true forever, and `_subscribe()` / `_jump()` / `_markRead()` at lines 54-56 never run. The user stares at a spinner indefinitely; the compose box below still accepts input and sends succeed, so the screen shows a spinner above a working input with no history and no live updates.

**Root fix**  
Wrap `_init` in try/catch, set an `_error` field, and render an error + Retry state (the ErrorRetry widget in app/lib/src/core/platform/error_retry.dart already exists for exactly this). Also subscribe to realtime independently of the history load succeeding.

**Skeptic's note**  
Verified: initState calls _init() fire-and-forget (dm_thread_screen.dart:40); _init awaits the dm_messages select with no try/catch and only sets _loading=false after the await (43-53), so a throw leaves _loading true forever and skips _subscribe/_jump/_markRead (54-56); the body has exactly one failure-free branch, `_loading ? CircularProgressIndicator : ListView.builder` (line ~235), with no error state or Retry in the file. Correction to 'no way to retry': popping the thread and re-opening it re-runs _init, so the stuck state is per-visit rather than terminal - which is why I put this at medium rather than high. The compose box does stay live above the spinner, as claimed.

---

### [medium] Approving or declining a team join request swallows the error, and the comment claiming the list will reflect reality is false

- **id**: `join-request-respond-swallowed` | **front**: Error handling & dead ends | **category**: silent-write-failure | **runs**: 1+2
- **where**: `app/lib/src/features/teams/presentation/team_page_screen.dart:731`

**Evidence**

```
```dart
Future<void> _respond(WidgetRef ref, String requestId, bool approve) async {
  try {
    await ref.read(identityRepositoryProvider).respondJoinRequest(requestId, approve);
    ref.invalidate(pendingJoinRequestsProvider(teamId));
    if (approve) ref.invalidate(teamRosterProvider(teamId));
  } catch (_) {/* the list refresh reflects reality */}
}
```
The invalidates are INSIDE the try, before the catch - when respondJoinRequest throws they never execute, so no refresh happens at all and the comment is wrong.
```

**Failure scenario**  
A captain taps 'Approve' on a join request while their auth token is stale or the RPC rejects them (demoted since the page loaded). Nothing happens: no snackbar, no list change, the request row stays exactly as it was. The captain assumes the tap did not register, taps again, still nothing. The requesting player is never added and never told.

**Root fix**  
Move the invalidates into a `finally`, and show a snackbar in the catch with the mapped failure reason.

**Skeptic's note**  
Quoted code is verbatim correct (team_page_screen.dart:731-739): both invalidates sit inside the try before `catch (_) {/* the list refresh reflects reality */}`, so on a throw no refresh happens and the comment is indeed false. respond_join_request does raise for a demoted admin ('not authorized') and for an already-handled request (20260703190100_team_join_requests.sql), so the throw path is real. Medium rather than high: it is a silent no-op on an admin tap, with no data loss, and the request remains actionable after a manual refresh.

---

### [medium] 'Mark filled' and 'Cancel' on your own post fail completely silently

- **id**: `myposts-act-swallows-writes` | **front**: Error handling & dead ends | **category**: silent-write-failure | **runs**: 1+2
- **where**: `app/lib/src/features/discover/presentation/my_posts_screen.dart:13`

**Evidence**

```
```dart
Future<void> _act(WidgetRef ref, Future<void> Function() action) async {
  await action();
  ref.invalidate(myPostsProvider);
  ref.invalidate(discoverFeedProvider);
}
```
No try/catch. Both buttons route through it: `onPressed: () => _act(ref, () => repo.markFilled(id))` (line 66) and `onPressed: () => _act(ref, () => repo.cancelPost(id))` (line 71). There is no ScaffoldMessenger call anywhere in the file.
```

**Failure scenario**  
A user's post has been filled; they tap 'Mark filled' with a flaky connection (or the RPC rejects them). `action()` throws, so the two invalidates never execute, the card keeps rendering the 'open' chip and both buttons, no snackbar appears, and the exception is swallowed as an unhandled async error. The user reasonably concludes the post is closed and stops responding - while it stays live in every nearby player's Discover feed.

**Root fix**  
try/catch inside `_act`, show a snackbar with a mapped message on failure, and invalidate in a `finally` so the list re-reflects real server state either way.

**Skeptic's note**  
Code matches the quote exactly (my_posts_screen.dart:13-17): no try/catch, both TextButtons route through _act (66, 71), and the file contains no ScaffoldMessenger call at all. On a throw the two invalidates are skipped, the 'open' chip and both buttons remain, and the error becomes an unhandled async error. Severity trimmed from high to medium: no data is lost or corrupted, the post simply stays open while the user believes it closed, and a manual pull-to-refresh/re-entry shows the true state.

---

### [medium] Six write paths catch only PostgrestException, so network drops and StateErrors leave a re-enabled button and no message

- **id**: `postgrest-only-catch-hides-network-failures` | **front**: Error handling & dead ends | **category**: error-handling | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/start_match_screen.dart:107`

**Evidence**

```
`} on PostgrestException catch (e) { setState(() => _error = e.message); } finally { if (mounted) setState(() => _busy = false); }` with no generic catch - the same pattern in: start_match_screen.dart:107 (_create), app/lib/src/features/discover/presentation/new_post_composer.dart:122 (_post), app/lib/src/features/teams/presentation/create_team_screen.dart:70 (_create), app/lib/src/features/profile/presentation/edit_profile_screen.dart:114 (_save), app/lib/src/features/scoring/presentation/transfer_scorer_screen.dart:43 (_hand), app/lib/src/features/teams/presentation/claim_inbox_screen.dart:35 (_approve). Non-Postgrest throws are real here: SocketException/ClientException on any offline tap, AuthException, and IdentityRepository's own `throw StateError('No authenticated user')` (app/lib/src/features/identity/data/identity_repository.dart:19) which reaches updateMyProfile/uploadAvatar.
```

**Failure scenario**  
A user in a patchy ground fills in the New post composer and taps Post. The RPC times out with a ClientException, which does not match `on PostgrestException`; `finally` clears `_busy` so the button re-enables, `_error` stays null, and the exception becomes an unhandled async error. The composer looks untouched with all their text still in it - the user cannot tell whether the post went out, taps again, and may end up with duplicates once connectivity returns. Same shape strands 'Next: squads', 'Create team', 'Save' on Edit profile, 'Hand over scoring' and 'Approve' on the claim inbox.

**Root fix**  
Add a trailing `} catch (e) { setState(() => _error = 'Something went wrong - check your connection and try again.'); }` to each, or centralise on one `runGuarded` helper that maps PostgrestException/AuthException/network to user-facing copy.

**Skeptic's note**  
All six sites verified as `} on PostgrestException catch (e)` with no generic catch and a `finally` that clears _busy: start_match_screen.dart:107, new_post_composer.dart:122, create_team_screen.dart:70, edit_profile_screen.dart:114, transfer_scorer_screen.dart:43, claim_inbox_screen.dart:35. Non-Postgrest throws are genuinely reachable (package:http ClientException/SocketException from any offline rpc/insert, AuthException, and IdentityRepository's own StateError at identity_repository.dart:19), so the button re-enables with _error still null and no message. Note that the same files DO have generic catches elsewhere (new_post_composer.dart:81, edit_profile_screen.dart:64), so this is inconsistency rather than a blanket pattern. Medium, not high: no data loss and the user's input is preserved; the harm is a silent failure plus a possible duplicate post on retry.

---

### [medium] Cold-starting any public deep link leaves the user on a single top-level screen with no way into the app

- **id**: `public-deeplink-strands-outside-shell` | **front**: Error handling & dead ends | **category**: navigation-dead-end | **runs**: 1
- **where**: `app/lib/src/core/routing/app_router.dart:55`

**Evidence**

```
onboardingRedirect returns null for `/watch/`, `/player/`, `/invite/`, `/join-tournament/`, `/tournament/` regardless of gate (lines 55-61), and all five are declared as top-level GoRoutes outside the StatefulShellRoute (lines 106-151). None of the corresponding screens offers a route into the shell: MatchViewerScreen's only action is Share (match_viewer_screen.dart:335-342), PlayerStatsScreen/TournamentPageScreen/InviteAcceptScreen have no home affordance, and AdaptiveScaffold only draws a back button when the navigator can pop (app/lib/src/core/platform/adaptive_scaffold.dart:26-43).
```

**Failure scenario**  
A friend shares a /watch/<id> link (or the app is launched at /tournament/<id>). On cold start the route stack contains exactly one entry, so on iOS the Cupertino nav bar renders no back chevron and there is no tab bar - the user can view the scorecard and nothing else; the only escape is force-quitting and relaunching. On Android the system back button exits the app entirely rather than entering it. A first-time visitor arriving through the app's primary growth channel can never reach Discover, sign-in, or anything else.

**Root fix**  
When these screens are the root of the stack (`!context.canPop()`), render a leading 'Open Pitch' / home action that does `context.go(Routes.discover)`, so a shared link always has a door into the app.

**Skeptic's note**  
The cited trigger is WRONG and unreachable: cold-starting at /watch, /tournament, /invite etc. is impossible today because no deep link is registered on either platform (no CFBundleURLTypes, no entitlements file, no VIEW/BROWSABLE intent-filter - same evidence as team-invite-link-unreachable), and go_router's initialLocation is Routes.splash. However the defect is real via a path the finding missed: join_tournament_screen.dart:47 does `context.go(Routes.tournamentPage(tournamentId))` after a successful join, and /tournament/:id is a top-level route outside the StatefulShellRoute (app_router.dart:146-151). go() replaces the whole stack, so the user lands on a single-entry stack with no tab bar and - since AdaptiveScaffold only gets an implied back button when the navigator can pop (adaptive_scaffold.dart:26-46) - no back chevron; TournamentPageScreen's only app-bar action is Share (tournament_page_screen.dart:30-39). Android back exits the app. Severity medium.

---

### [medium] Postgres/Dart exception objects are interpolated straight into user-facing SnackBars and error text in 40+ places

- **id**: `raw-exception-interpolation-everywhere` | **front**: Error handling & dead ends | **category**: error-handling | **runs**: 1+2
- **where**: `app/lib/src/features/teams/presentation/team_page_screen.dart:474`

**Evidence**

```
Bare, unprefixed dumps: team_page_screen.dart:474, :490, :508, :651 (`SnackBar(content: Text('$e'))`), scoring_console_screen.dart:655, :690, :972 (`_toast('$e')`), ball_log_screen.dart:262, manage_tournament_screen.dart:359, :370, match_squads_screen.dart:74, :203, toss_openers_screen.dart:36, :53, start_match_screen.dart:126, :145. Prefixed-but-still-raw: matches_screen.dart:48, :236; dm_inbox_screen.dart:101, :178-184; notifications_screen.dart:77; my_posts_screen.dart:27; post_detail_screen.dart:45, :83, :219; search_screen.dart:65; new_post_composer.dart:82, :187; sign_in_screen.dart:45; settings_screen.dart:38, :73, :110; edit_profile_screen.dart:65; claim_inbox_screen.dart:52; invite_accept_screen.dart:49; team_page_screen.dart:57, :64, :224, :255, :288, :304, :357, :394, :456; my_teams_screen.dart:28; match_squads_screen.dart:61, :191; scoring_console_screen.dart:159, :381, :834, :851; transfer_scorer_screen.dart:58; live_matches_screen.dart:28; match_viewer_screen.dart:172, :261, :483, :746, :905; tournaments_list_screen.dart:46; tournament_page_screen.dart:42; join_tournament_screen.dart:65, :115; manage_tournament_screen.dart:36, :295; player_stats_screen.dart:33; create_tournament_screen.dart:70; ball_log_screen.dart:58; dm_thread_screen.dart:209. The codebase already has the right widget - ErrorRetry (app/lib/src/core/platform/error_retry.dart), documented as 'the one error state for async screens' - but it is used in exactly TWO places (discover_screen.dart:124 and profile_screen.dart:24).
```

**Failure scenario**  
Any RLS denial produces a snackbar reading `PostgrestException(message: new row violates row-level security policy for table "teams", code: 42501, details: null, hint: null)`. Any offline tap produces `ClientException with SocketException: Failed host lookup: 'ocejkqihgiinonpyafhl.supabase.co'`. Users read this as a crash, cannot act on it, and it leaks schema and table names. Worse, 38 of the async `error:` branches listed above have no Retry at all, so a transient failure requires backing out and re-entering the screen.

**Root fix**  
Introduce one `humanError(Object e)` mapper (Postgrest code/message -> copy, network -> 'check your connection') and route every snackbar through it; replace the `Center(child: Text('...\n$e'))` async error branches with `ErrorRetry(message: ..., detail: e, onRetry: ...)`, which already tucks the technical detail away in small grey text.

**Skeptic's note**  
Spot-checked and the cited lines say what is claimed: bare `SnackBar(content: Text('$e'))` at team_page_screen.dart:474, :490, :508, :651; `_toast('$e')` at scoring_console_screen.dart:655, :690, :972; `Text('$e')` at ball_log_screen.dart:262 and match_squads_screen.dart:74/:203; `SnackBar(content: Text('$e'))` at manage_tournament_screen.dart:359/:370. ErrorRetry exists and self-documents as 'the one error state for async screens' (core/platform/error_retry.dart) yet grep finds exactly two usages, discover_screen.dart:124 and profile_screen.dart:24. The user-visible consequence (raw PostgrestException / ClientException text, schema and hostname leakage, no retry) is real, so this is a defect and not merely style - but it is an aggregate polish/consistency issue with no data or correctness impact, so medium is the ceiling.

---

### [medium] Signing in from an invite or tournament-join link destroys the link - the flow can never be completed by a signed-out user

- **id**: `signin-push-destroys-invite-and-join-stack` | **front**: Error handling & dead ends | **category**: navigation-dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/teams/presentation/invite_accept_screen.dart:118`

**Evidence**

```
InviteAcceptScreen's anonymous branch does `onPressed: () => context.push(Routes.signIn)` (line 118); JoinTournamentScreen does the identical `context.push(Routes.signIn)` (app/lib/src/features/tournaments/presentation/join_tournament_screen.dart:94). The router redirect is `onboardingRedirect(ref.read(authGateProvider), state.matchedLocation)` (app/lib/src/core/routing/app_router.dart:97-98) and for AuthGate.ready it returns `Routes.discover` whenever `loc == Routes.signIn` (app_router.dart:72-77). The project's own test asserts this: `expect(onboardingRedirect(AuthGate.ready, Routes.signIn), Routes.discover);` (app/test/router_redirect_test.dart:33). A redirect is a `go()`, which replaces the whole stack, not a pop.
```

**Failure scenario**  
A captain shares a team invite. The recipient (guest/anonymous session) opens /invite/<token>, sees 'You have been invited to join Mumbai United on Pitch. Sign in to accept.', taps 'Sign in to join', authenticates with Google. refreshListenable fires, the redirect evaluates location '/sign-in' with AuthGate.ready, and go('/discover') wipes the pushed /invite route. The user lands on the Discover feed with no invite, no message, and no way back to the token - they never join the team. Identical for /join-tournament/<token>: the invited captain signs in and their team is never entered.

**Root fix**  
Carry the origin through the sign-in hop (e.g. `context.push('${Routes.signIn}?from=${Uri.encodeComponent(currentLocation)}')`) and have onboardingRedirect honour a `from` query param instead of hard-coding Routes.discover; or render the sign-in UI inline on the invite/join screens so no navigation is needed.

**Skeptic's note**  
Mechanism verified: invite_accept_screen.dart:118 and join_tournament_screen.dart:94 both `context.push(Routes.signIn)`; SignInScreen never pops itself (no context.pop/go anywhere in the file); routerRefreshProvider notifies on every authGate change (router_refresh.dart) and onboardingRedirect(ready, '/sign-in') returns Routes.discover (app_router.dart:72-77, asserted by test/router_redirect_test.dart:33), which go_router applies as a replacement, discarding the pushed route. Corrections: the title's 'can never be completed' is false for /join-tournament - the in-app 'Join with a code' dialog (tournaments_list_screen.dart:_joinWithCode) is reachable again after sign-in and the user still has the code, so the flow is recoverable with friction; and for /invite the scenario is largely moot because there is no way to open /invite/:token at all (see team-invite-link-unreachable). Real defect = lost origin context on the sign-in hop, not an unrecoverable dead end.

---

### [medium] A new signed-in user with no team gets an enabled 'Next: squads' button that can never succeed and no route to create a team

- **id**: `start-match-no-teams-deadend` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/start_match_screen.dart:124`

**Evidence**

```
The 'Your team' dropdown is built from `myTeams.when(... data: (rows) => DropdownButton(items: [for (final r in rows) ...]))` (lines 124-140) - with zero teams it renders an empty dropdown showing only the hint. `FilledButton(onPressed: _busy ? null : _create, child: const Text('Next: squads'))` (lines 206-209) is always enabled, and `_create` just sets `_error = 'Pick both teams and overs.'` (line 65). Nothing on the screen links to Routes.createTeam. Compare JoinTournamentScreen, which handles the same state properly with 'You are not an admin of any team yet.' + a 'Create a team first' button (join_tournament_screen.dart:121-131).
```

**Failure scenario**  
A brand-new user finishes onboarding, lands on Matches ('No matches yet. Start one.'), taps the 'Start a match' FAB, and finds an unusable 'Choose your team' dropdown. Tapping 'Next: squads' repeats 'Pick both teams and overs.' forever. The only cure - Profile tab > My teams > Create team - is three screens away in a different branch and is never suggested. The app's primary call to action is a dead end for every first-time user.

**Root fix**  
When `myTeams` resolves empty, replace the dropdown with the JoinTournamentScreen treatment: an explanatory line plus a 'Create a team first' FilledButton pushing Routes.createTeam, and disable the Next button.

**Skeptic's note**  
Verified: the 'Your team' dropdown is built straight from myTeams rows with no empty branch (start_match_screen.dart:124-140), 'Next: squads' is enabled whenever !_busy (206-209), _create only sets 'Pick both teams and overs.' (line 65), and nothing in the file references Routes.createTeam. The contrast with join_tournament_screen.dart:121-131 ('You are not an admin of any team yet.' + 'Create a team first') is accurate. Kept at medium: it is a real first-run dead end with no in-screen guidance, but it is recoverable through Profile -> My teams -> Create team and nothing is corrupted.

---

### [medium] Team invites are a dead feature: the shared link resolves nowhere and /invite/:token has no in-app entry point

- **id**: `team-invite-link-unreachable` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/identity/data/identity_repository.dart:170`

**Evidence**

```
`String inviteLink(String token) => 'https://pitch.app/invite/$token';` and team_page_screen.dart:483-488 shares `'Join my cricket team on Pitch: ${inviteLink(token)}'`. Neither ios/Runner/Info.plist nor android/app/src/main/AndroidManifest.xml contains any CFBundleURLTypes, applinks entitlement, or BROWSABLE/VIEW intent-filter (grep for CFBundleURLTypes|applinks|autoVerify|BROWSABLE|android:host returns nothing). `Routes.acceptInvite` is declared at app/lib/src/core/routing/routes.dart:71 and is referenced from NOWHERE in lib/ - grep confirms zero call sites. The tournament flow acknowledges this and ships a fallback ('no hosted web domain yet, so a shared https link won't resolve in a browser' - tournaments_list_screen.dart:90-91, with a 'Join with a code' dialog at line 92); team invites have no equivalent.
```

**Failure scenario**  
An admin taps 'Invite a player', the share sheet sends 'Join my cricket team on Pitch: https://pitch.app/invite/9f2a...'. The recipient taps it: the OS opens a browser (no app-link claim registered) to pitch.app, which does not serve that path. The app itself offers no 'enter invite code' screen, and the invite token is never shown as text they could paste anywhere. The invite is unusable 100% of the time, while 'Manage invites' cheerfully lists it as active.

**Root fix**  
Mirror the tournament fallback: add an 'Enter invite code' action (My teams / Team page) that pushes Routes.acceptInvite(token), and include the bare token in the shared text. Separately register the universal/app link + custom scheme before relying on the https URL.

**Skeptic's note**  
All four legs verified: identity_repository.dart:170 `inviteLink` hard-codes https://pitch.app/invite/$token; team_page_screen.dart:485 shares only that URL (no bare token, unlike manage_tournament_screen.dart:354 which appends 'Or enter this code in the app: $token'); Routes.acceptInvite (routes.dart:71) has zero call sites in lib/ (only the router's own path literal at app_router.dart:132); and there is no deep-link registration anywhere - Info.plist has no CFBundleURLTypes/applinks (grep count 0), AndroidManifest.xml has only the MAIN/LAUNCHER intent-filter, and no .entitlements file exists. 'Manage invites' does list the invite as active (team_page_screen.dart:212-263) and shows only uses/expiry, no copyable token. Lowered from high to medium: it is a dead feature, not a data or correctness fault, and admins have working alternatives ('Add guest player', and strangers can 'Request to join').

---

### [medium] Assigning a team to a group and adding a team to a tournament fail silently with zero feedback

- **id**: `tournament-group-assignment-silent-failure` | **front**: Error handling & dead ends | **category**: silent-write-failure | **runs**: 1+2
- **where**: `app/lib/src/features/tournaments/presentation/manage_tournament_screen.dart:307`

**Evidence**

```
```dart
Future<void> _setGroup(WidgetRef ref, String teamId, String group) async {
  await ref.read(tournamentRepositoryProvider).addTournamentTeam(tournamentId, teamId, group);
  ref.invalidate(tournamentOverviewProvider(tournamentId));
}
```
No try/catch (lines 307-310). Same in `_addTeam`: `await ref.read(tournamentRepositoryProvider).addTournamentTeam(tournamentId, picked, 'A'); ref.invalidate(...)` (lines 337-338), also unguarded. Every other action on this screen goes through `_run()` (line 363) which does catch and snackbar - these two bypass it.
```

**Failure scenario**  
The organizer taps the 'B' chip on a team. addTournamentTeam throws (registration closed, not the organizer, network drop). The invalidate never runs, so the chip snaps back to 'A' with no explanation. The organizer taps repeatedly, concludes the UI is broken, and cannot reach 4 teams across 2 groups - so 'Generate group fixtures' stays disabled behind 'Add at least 2 teams to each group' (line 111) with no way to diagnose why.

**Root fix**  
Route both through the existing `_run(context, ref, ...)` helper (or add the same try/catch + snackbar), and invalidate in a finally.

**Skeptic's note**  
Verified: _setGroup (manage_tournament_screen.dart:307-310) and the addTournamentTeam call inside _addTeam (337-338) are both unguarded, while every other mutation on the screen goes through _run (363-372) which catches and snackbars. One correction to the narrative: the group chip's `selected` comes from server state (`t.groupLabel == g`, line 74), so on failure the chip never moves at all - it does not 'snap back' from an optimistic state. Consequence still holds: no feedback, and canGenerate stays false behind 'Add at least 2 teams to each group.' (line 111) with nothing explaining why. Medium, not high - the failure is a silent no-op on an organizer action, recoverable by retrying with connectivity.

---

### [medium] event_kind is not selected, so v14 retirement/strike-swap event rows render in the ball log as ordinary deliveries and offer Edit/Insert that always fail

- **id**: `balllog-event-rows-render-as-balls` | **front**: Flutter state & lifecycle | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/ball_log_screen.dart:66`

**Evidence**

```
`inningsDeliveriesProvider` (match_providers.dart:117-123) does not select `event_kind`, but ball_log branches on it at L66 (`final isEvent = d['event_kind'] != null;`), L97 (`_outcome`), L138 (`_actions`) and L172 (the `outElsewhere` incoming-batter filter). All four therefore evaluate to "this is a normal ball". Event rows really do exist in the stream — `20260706110000_deliveries_event_rows.sql` adds `event_kind delivery_event` with `('strike_swap','retirement')`, and `retire_batter`/`swap_strike` insert them.
```

**Failure scenario**  
Score a match, tap "Retire" and retire the striker hurt, then open Ball log / corrections. The retirement shows as a phantom delivery labelled `0` with bowler `-` and an over-number suffixed `+` (as if it were a wide), and the row offers "Edit this ball" and "Insert a ball after this". Choosing Edit → Save sends `edit_ball` with `wicket_type=null`, which violates the `deliveries_retirement_shape` CHECK and surfaces a raw Postgres constraint message in a snackbar. The `outElsewhere` set at L167-175 also mis-classifies who is unavailable, because its `r['event_kind'] == 'retirement'` branch can never be true — a retired batter is offered as an incoming batter on other corrections.

**Root fix**  
Add `event_kind` (and `crossed`, `is_overthrow`) to the `inningsDeliveriesProvider` select. The UI logic that consumes it is already written and correct.

**Skeptic's note**  
Confirmed on every point. match_providers.dart:117-123 omits `event_kind`, while ball_log_screen.dart:66, :97-103, :138 and :172 all branch on it, so `isEvent` is always false. Event rows really are in the stream: 20260706110000_deliveries_event_rows.sql:10-12 adds the enum + column and 20260706110400_rpc_retire_batter.sql / 110500_rpc_swap_strike.sql insert them, reachable from the console's 'Retire' and 'Swap strike' buttons (scoring_console_screen.dart ~:857-871). Rendering traced: `is_legal` IS selected and is false for event rows (110000:39-41), so :67-72 produces the `N.M+` wide-style over label, `bowler_id` is null (110000:13) so the subtitle shows '-', and `_outcome` falls through to :117-118 printing '0' because :122 skips `retired_not_out`. :143-154 offers 'Edit this ball' and 'Insert a ball after this'; Edit→Save sends `_wicket_type = null`, which violates `deliveries_retirement_shape` (110000:30-34, `wicket_type in ('retired_out','retired_not_out','timed_out') and dismissed_player_id is not null`) and surfaces raw via :262 `SnackBar(content: Text('$e'))`. One refinement on the `outElsewhere` claim (:167-175): the retirement row is not skipped entirely — `r['wicket_type'] != null` is true, so it falls into the else branch and contributes `r['striker_id']` instead of `dismissed_player_id`. That is accidentally correct when the STRIKER retired and wrong when the non-striker retired (wrong batter excluded, retired batter offered as incoming). Medium is right.

---

### [medium] Undo has no in-flight guard, so a double tap deletes two deliveries

- **id**: `console-undo-double-tap` | **front**: Flutter state & lifecycle | **category**: double-submit | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:830`

**Evidence**

```
L828-838 the Undo `_Btn` never sets or checks `_busy`, and the pad's `AbsorbPointer` (L512-513) only absorbs when `_bowlerId == null || _busy` — since Undo never sets `_busy`, it stays live for the whole RPC round trip. `undo_last_ball` (20260616202001_rpc_corrections.sql:14-15) is `delete from deliveries where seq = (select max(seq) ...)` — each call removes a different, real ball. The same applies to the Swap-strike button (L844-854), which writes a second `strike_swap` event row.
```

**Failure scenario**  
Mid-over, tap Undo twice in quick succession (well under the ~200-500ms hosted round trip — a natural impatient double tap). Two `undo_last_ball` calls fire; the second deletes the ball BEFORE the one the scorer meant to remove. Two legitimate deliveries are gone from an event-sourced ledger with no redo, and the scorer sees only one refresh. On the strike-swap button, two taps produce two junk event rows that both show up in the ball log as phantom entries.

**Root fix**  
Wrap Undo and Swap-strike in the same `if (_busy) return; setState(() => _busy = true); ... finally { if (mounted) setState(() => _busy = false); }` pattern used by `_record`, and await the refold before re-enabling.

**Skeptic's note**  
Confirmed. scoring_console_screen.dart:1255-1277 `_Btn` is a bare `OutlinedButton(onPressed: onTap)` with no disabled state and no debounce; the Undo handler (~:829-838) and the Swap-strike handler (~:844-854) never read or set `_busy`, and the pad's `AbsorbPointer(absorbing: _bowlerId == null || _busy)` (:512-513) therefore stays open for the whole round trip when a bowler is selected mid-over. 20260616202001_rpc_corrections.sql:7-16 `undo_last_ball` confirmed as `delete from public.deliveries where innings_id = _innings_id and seq = (select max(seq) ...)`; it takes `pg_advisory_xact_lock`, which serialises the two calls but does not make the second a no-op — each deletes a different, real delivery. `undo_last_ball` is not covered by the `_expected_last_seq` fence (that is record_ball only, 20260706110600:44-46). Severity medium, not high: the loss is visible in the score line that refreshes immediately after, and the ball can be re-entered via `insert_ball` from the ball log. The strike-swap half of the claim is also true but produces two cancelling `strike_swap` event rows — cosmetic junk, no state corruption.

---

### [medium] The inbox's realtime subscriptions are wired to ref.listen, which never fires on first mount because dmInboxProvider is already warm from the Discover badge

- **id**: `dm-inbox-listen-never-fires` | **front**: Flutter state & lifecycle | **category**: realtime | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_inbox_screen.dart:86`

**Evidence**

```
L85-89:
```dart
final inbox = ref.watch(dmInboxProvider);
ref.listen(dmInboxProvider, (_, next) {
  final threads = next.value;
  if (threads != null) _syncSubscriptions(threads);
});
```
flutter_riverpod 3.3.2 `consumer.dart:524-547` — `WidgetRef.listen` has **no** `fireImmediately` parameter (the source comment says so explicitly); it only fires on subsequent changes. `dmInboxProvider` is a plain `FutureProvider` (discover_providers.dart:145) and riverpod 3.3.2 `future_provider.dart:110` defaults `isAutoDispose = false`, so it is never disposed. `discover_screen.dart:82` watches `dmUnreadCountProvider`, which watches `dmInboxProvider` — the default Discover tab warms it at app launch.
```

**Failure scenario**  
Cold-launch the app (Discover renders, `dmInboxProvider` resolves to AsyncData for the mail badge). Tap the mail icon → Messages. `ref.listen` registers but the provider's value is unchanged, so `_syncSubscriptions` never runs and `_subs` stays empty. Have the other user send a DM: no channel exists, nothing invalidates, the row's unread badge/preview/ordering never update — the screen looks frozen until the user manually pulls to refresh. The DM-5 "live inbox" is dead on the most common entry path.

**Root fix**  
Call `_syncSubscriptions(inbox.value ?? const [])` directly in `build` (or in a post-frame callback) in addition to `ref.listen`, so the already-loaded case is covered.

**Skeptic's note**  
Confirmed. flutter_riverpod-3.3.2 consumer.dart:522-547 verified: `WidgetRef.listen` has no `fireImmediately` parameter and the source comment says so explicitly ('We can't implement a fireImmediately flag...'); it forwards to `container.listen` without it, so the listener fires only on subsequent emissions. dm_inbox_screen.dart:85-89 confirmed as the sole caller of `_syncSubscriptions`. The warm-provider claim checks out: discover_screen.dart:82 `ref.watch(dmUnreadCountProvider)`, discover_providers.dart:199-200 `dmUnreadCountProvider` watches `dmInboxProvider` (:145), and Discover is the post-splash landing route (app_router.dart:69, :168). Also verified that Discover's element stays mounted under the pushed `/discover/messages` route (same StatefulShellBranch navigator, MaterialPageRoute maintainState), so `dmInboxProvider` keeps its resolved value and never re-emits — the auto-dispose question in the finding is moot either way. Result: `_subs` stays empty on the primary entry path, no channel is opened, and DM-5's live inbox is inert until a manual pull-to-refresh. Medium stands.

---

### [medium] DmThreadScreen._init has no error handling and calls _subscribe() unconditionally after the await

- **id**: `dm-thread-init-unguarded` | **front**: Flutter state & lifecycle | **category**: error-handling | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_thread_screen.dart:43`

**Evidence**

```
L43-57:
```dart
Future<void> _init() async {
  final rows = await _c.from('dm_messages').select(...).eq('thread_id', widget.threadId).order('created_at');
  for (final r in ...) { _ids.add(...); _messages.add(r); }
  if (mounted) setState(() => _loading = false);
  _subscribe();
  _jump();
  _markRead();
}
```
No try/catch; `_loading` (L31, initialised `true`) is only cleared on the success path, and `build` L235-236 renders a bare `CircularProgressIndicator` whenever `_loading` is true, with no retry affordance. `_init()` is fired-and-forgotten from `initState` L40. `_subscribe()` L71 uses the `_c` getter (`ref.read`), which throws once the element is unmounted.
```

**Failure scenario**  
(a) Open a DM thread while offline or if the `dm_messages` RLS select 403s: the PostgrestException propagates out of the un-awaited `_init()` as an unhandled async error; the screen spins forever, `_subscribe()` never runs, and even when connectivity returns the thread stays blank and dead. (b) Tap a conversation and immediately tap back before the history query returns: `mounted` is false, so `_subscribe()`'s `ref.read` throws the riverpod StateError as an uncaught async exception, and `_markRead()` never runs so the unread badge stays.

**Root fix**  
Wrap `_init` in try/catch, set an `_error` field and render a retry, and bail with `if (!mounted) return;` before `_subscribe()` / `_jump()` / `_markRead()`.

**Skeptic's note**  
Confirmed as written. dm_thread_screen.dart:43-57 verified: no try/catch around the `dm_messages` select, `_loading` (:31, initialised true) cleared only on the success path, and `_subscribe()`/`_jump()`/`_markRead()` all called after the await with only the `setState` guarded by `mounted`. `build` :235-236 renders a bare `CircularProgressIndicator.adaptive()` whenever `_loading` — there is no error branch and no retry affordance anywhere in the file. `_init()` is fired and not awaited from `initState` :40, so the exception surfaces as an unhandled async error. Scenario (a) is the substantive defect: offline or any transport failure leaves a permanently blank spinning thread with no recovery path even after connectivity returns. Scenario (b) is real but is the same underlying `ref`-after-unmount issue as dm-thread-ref-in-dispose (`_c` at :34 → consumer.dart:469-477), and it is a console error only, not user-visible; `_markRead` at :61-66 is itself already try/catch'd. Medium is fair for the dead-spinner; the fix as proposed is correct.

---

### [medium] DmThreadScreen.dispose() calls ref.read → StateError; realtime channel + controllers never released, later broadcast does setState-after-dispose

- **id**: `dm-thread-ref-in-dispose` | **front**: Flutter state & lifecycle | **category**: lifecycle | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_thread_screen.dart:174`

**Evidence**

```
L34: `SupabaseClient get _c => ref.read(supabaseClientProvider);`
L173-178:
```dart
void dispose() {
  if (_channel != null) _c.removeChannel(_channel!);
  _input.dispose();
  _scroll.dispose();
  super.dispose();
}
```
flutter_riverpod 3.3.2 `lib/src/core/consumer.dart` L469-477: `_assertNotDisposed()` **throws a StateError (not an assert)** when `!context.mounted`, and L503-506 `ConsumerStatefulElement.unmount()` calls `super.unmount()` first — Flutter `framework.dart` L4851 `Element.unmount()` sets `_widget = null` (and L3657 `bool get mounted => _widget != null`) BEFORE `StatefulElement.unmount()` L6028 calls `state.dispose()`. So `ref` is guaranteed to throw inside dispose(). The same file's sibling screen already knows this: `match_viewer_screen.dart:48` — `SupabaseClient? _client; // captured for safe teardown (ref is unsafe in dispose)`.
```

**Failure scenario**  
Discover → mail icon → tap any conversation → tap back. `dispose()` line 174 evaluates `_c` → `ref.read` → StateError thrown out of `State.dispose()`. Consequences, in order: (a) `removeChannel` never runs, so the private `dm:<threadId>` channel stays joined on the websocket for the app's lifetime; (b) `_input.dispose()`/`_scroll.dispose()`/`super.dispose()` are skipped (debug also fires the framework's "dispose failed to call super.dispose" assert); (c) the still-live `onBroadcast` closure at L79-90 holds the dead State — when the other participant sends the next message, `setState(() => _messages.add(record))` (L86, which has no `mounted` guard) runs on a defunct State: assert in debug, `markNeedsBuild()` on a defunct element in release. Every thread ever opened accumulates one leaked channel, so the crash rate grows with usage.

**Root fix**  
Mirror match_viewer_screen: capture `SupabaseClient? _client = ref.read(supabaseClientProvider)` in `initState`, use `_client` in `dispose()`, and add `if (!mounted) return;` at the top of the broadcast callback before `setState`.

**Skeptic's note**  
Mechanism verified end-to-end, but the consequences are overstated. Verified: flutter_riverpod-3.3.2 lib/src/core/consumer.dart:371 `BuildContext get context => this;` and :469-477 `_assertNotDisposed()` is a real `throw StateError`, called from `read` at :553-557. Flutter framework.dart:4851-4866 `Element.unmount()` sets `_widget = null` BEFORE framework.dart:6028 `StatefulElement.unmount()` calls `state.dispose()`, and :3657 `mounted => _widget != null` — so `context.mounted` is false inside dispose() and `ref.read` throws. dm_thread_screen.dart:34 + :174 confirmed; the sibling comment at match_viewer_screen.dart:48 (`SupabaseClient? _client; // captured for safe teardown (ref is unsafe in dispose)`) confirmed. Route `/discover/messages/:threadId` is a pushed sub-route (app_router.dart:197-207), so dispose runs on every back tap. CORRECTIONS: (1) the thrown error does NOT escape to the user — framework.dart:3435-3439 `finalizeTree()` wraps `_inactiveElements._unmountAll` in a try/catch that deliberately reports rather than activating an ErrorWidget, so there is no crash and no red screen in any mode; (2) the later `setState` on the defunct State does NOT crash in release: `_element` is still non-null (nulled only after dispose returns) but framework.dart:5339 `markNeedsBuild()` early-returns when `_lifecycleState != active` — only the debug assert fires; (3) 'crash rate grows with usage' is wrong. Real residual harm: one leaked `dm:<threadId>` realtime channel per thread visited, `_input`/`_scroll` never disposed, `super.dispose()` skipped, and debug/profile console errors. That is a lifecycle/resource bug, not a critical.

---

### [medium] Organizer bracket actions have no in-flight guard and advance_playoffs is not concurrency-safe, so a double tap creates two 'final' fixtures

- **id**: `tournament-advance-double-tap` | **front**: Flutter state & lifecycle | **category**: double-submit | **runs**: 2
- **where**: `app/lib/src/features/tournaments/presentation/manage_tournament_screen.dart:363`

**Evidence**

```
`ManageTournamentScreen` is a `ConsumerWidget` with no busy state at all; L363-372:
```dart
Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function(TournamentRepository) action) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try { await action(ref.read(tournamentRepositoryProvider)); ref.invalidate(tournamentOverviewProvider(tournamentId)); }
  catch (e) { messenger?.showSnackBar(SnackBar(content: Text('$e'))); }
}
```
The buttons (L104, L126, L153) stay enabled for the whole round trip. `20260625150800_rpc_advance_playoffs.sql` guards only with a read (`_has_final := exists (...)`) and takes **no advisory lock**, and `20260625150200_tournament_teams_matches.sql:18-25` has no unique constraint on `(tournament_id, bracket_slot)` — PK is `match_id` alone.
```

**Failure scenario**  
With both semifinals complete, the organizer double-taps "Advance to final". Two `advance_playoffs` transactions both read `_has_final = false` and both insert a `matches` row + a `tournament_matches` row with `stage='final', bracket_slot='F'`. The manage screen and the public bracket now show two Finals; `_playoffs`' `finalDone = fin.every((f) => f.isComplete)` (L144) can only be satisfied by scoring both, so "Crown the champion" is unreachable and the tournament is stuck with no UI to delete the duplicate.

**Root fix**  
Convert the screen to `ConsumerStatefulWidget` with a `_busy` flag that disables all three action buttons while `_run` is awaiting, and add `perform pg_advisory_xact_lock(hashtextextended(_tournament_id::text,0));` plus a `unique (tournament_id, bracket_slot)` index server-side.

**Skeptic's note**  
Confirmed. manage_tournament_screen.dart:17 `class ManageTournamentScreen extends ConsumerWidget` — no State, no busy flag anywhere; :363-372 `_run` awaits the RPC then invalidates, and the three action buttons (:104 generateGroupFixtures, :126 generatePlayoffs, :153 advancePlayoffs) derive `onPressed` purely from the provider value, so all stay enabled for the whole round trip. 20260625150800_rpc_advance_playoffs.sql:11 `_has_final := exists (...)` is an unlocked read-then-insert with no `pg_advisory_xact_lock` (contrast record_ball/edit_ball, which both take one), and 20260625150200_tournament_teams_matches.sql:18-25 confirms `match_id` is the only PK with just a non-unique `tournament_matches_tid_idx` — nothing prevents two `stage='final', bracket_slot='F'` rows. Under READ COMMITTED two overlapping transactions both see false and both insert. Verified the recovery claim too: `_playoffs` :144 `finalDone = fin.every((f) => f.isComplete)` gates 'Crown the champion', and myMatchesProvider (match_providers.dart:198-203, `_isTournamentMatch` filter, comment MTCH-5) deliberately excludes tournament-linked matches from the Matches tab — so the organizer genuinely has no delete affordance for the duplicate fixture. Medium: needs a rapid double tap inside the round-trip window on an organizer-only screen, but the tournament is then unrecoverable from the UI.

---

### [medium] compute_innings_state.did_not_bat lists batters who were dismissed without facing a ball, so the scorecard shows a run-out batter under "Did not bat"

- **id**: `did-not-bat-includes-dismissed-batter` | **front**: Scoring fold correctness | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110100_fold_v14_events.sql:174`

**Evidence**

```
The did_not_bat set is derived purely from the `_batters` map:
  line 171-175: `select coalesce(jsonb_agg(ms.team_member_id order by ms.batting_order nulls last), '[]') from public.match_squad ms where ms.match_id = _match_id and ms.team_id = _batting_team and not (_batters ? ms.team_member_id::text)`
But `_batters` is only ever written for the FACING batter (line 95-103: `_btkey := _facing::text`). A batter who is dismissed without facing (non-striker run out, obstructing, timed out) or who retires without facing never enters `_batters`. compute_innings_cards gets this right - it force-creates a card line for the dismissed batter at line 121 - so state and cards also disagree here.
PROVEN on the live DB (p2 run out off the very first ball while at the non-striker's end):
  STATE did_not_bat = ["7a15568e-...(p2)", ...]
  STATE fall_of_wickets = [{"wicket_number":1,"score_at_fall":0,"dismissed_player_id":"7a15568e-...(p2)","over":"0.1"}]
  CARDS p2 line = {"runs":0,"balls":0,"how_out":"run_out","dismissed":true,...}
The viewer renders this list verbatim: app/lib/src/features/scoring/presentation/match_viewer_screen.dart:756 `final dnb = (s['did_not_bat'] as List?)...` and line 830-836 prints `'Did not bat: ...'`; its only filter is `atCrease`, which does not exclude dismissed players.
```

**Failure scenario**  
First ball of the innings, the non-striker is run out for 0. The scorecard tab then simultaneously shows "Fall of wickets: 1-0 (P2, 0.1)" and "Did not bat: P2, ...", and P2 has no row in the batting card at all (state.batting only contains facing batters). Every innings with a non-striker run-out or a bat-less retirement produces this self-contradictory scorecard, and it is the shared/exported card too.

**Root fix**  
In compute_innings_state, force a `_batters` entry for the dismissed batter the same way compute_innings_cards does - inside the wicket block (after `_out` is resolved at line 139) and inside the retirement block (line 51), do `_batters := jsonb_set(_batters, array[_out::text], coalesce(_batters -> _out::text, jsonb_build_object('batter_id',_out,'runs',0,'balls',0,'fours',0,'sixes',0)))`. That fixes did_not_bat and makes the state batting list match the cards batting list.

**Skeptic's note**  
CONFIRMED. Verified 20260706110100_fold_v14_events.sql:95-103 - the _batters map is keyed only on _facing (the striker), and the wicket block at 138-154 never creates a line for _out, unlike compute_innings_cards which force-creates one (20260706110200:117-125, with a comment explicitly naming 'a non-striker run out without facing'). did_not_bat (fold:171-175) is `not (_batters ? ms.team_member_id::text)`, so any batter dismissed or retired without facing a ball lands in did_not_bat AND in fall_of_wickets (fold:140-141) simultaneously, and gets no batting row at all. Reachable in-app: the console's wicket sheet exposes run_out/obstructing with a who-is-out picker (scoring_console_screen.dart:1047-1057 _needsWhoOut, dismissedPlayerId passed at :85), and every new batter who arrives at the non-striker's end can be run out before facing. Rendering confirmed: app/lib/src/features/scoring/presentation/match_viewer_screen.dart:756 reads did_not_bat, :776 filters only by atCrease, :832-836 prints 'Did not bat: ...'. Stronger than the finding states - the MISS-9 full-scorecard SHARE image is built from the same state.batting list with no atCrease synthesis (match_viewer_screen.dart:200-215), so the exported card omits the dismissed batter's row entirely (and also any not-out batter who has faced no ball). Severity corrected high -> medium: it is a scorecard-display contradiction only; compute_innings_cards gets it right, so career stats, leaderboards and POTM are unaffected, and nothing persists.

---

### [medium] Anonymous sign-in is enabled and auto-bootstrapped, so every "authenticated-only" privacy boundary is reachable by anyone holding the public anon key

- **id**: `anonymous-session-collapses-authenticated-boundary` | **front**: Data exposure / PII | **category**: pii-exposure | **runs**: 1
- **where**: `backend/supabase/config.toml:180`

**Evidence**

```
`enable_anonymous_sign_ins = true` (backend/supabase/config.toml:180), and the client mints a session on every launch and again after sign-out: app/lib/src/core/auth/auth_providers.dart:45 and :61 `await client.auth.signInAnonymously();`. backend/README.md:55,98 makes this mandatory ("The Flutter client must signInAnonymously() before subscribing"). A Supabase anonymous user's JWT carries `role: authenticated` — it is distinguishable only by the is_anonymous claim, which nothing in the SQL layer checks (no migration references is_anonymous).

Every privacy control written as `to authenticated` therefore gates on nothing:
- backend/supabase/migrations/20260615140301_profiles_rls.sql:3,7-10 — `grant select ... on public.profiles to authenticated` plus `for select to authenticated using (true)`, so GET /rest/v1/profiles?select=* returns the whole directory: id, display_name, handle, city, photo_url, batting_style, bowling_style, playing_role. backend/supabase/migrations/20260617122500_public_profile_minimal.sql:3 asserts the opposite as its design guarantee: "phone / city / playing_role stay authenticated-only".
- backend/supabase/migrations/20260616203501_post_replies.sql:11 — `for select to authenticated using (true)`: every reply body on every post.
- backend/supabase/migrations/20260615140901_team_members_rls.sql:5-6 — every team's full roster.
- backend/supabase/migrations/20260706111200_discover_reads_ball_type.sql:38 — `grant execute ... discover_posts ... to authenticated`, which is what makes the location-oracle finding exploitable with no signup and no attributable identity.
The gate at app/lib/src/features/discover/presentation/discover_screen.dart:37 (`if (ref.watch(isAnonymousProvider))`) is client-side only and has no server counterpart.
```

**Failure scenario**  
An attacker extracts the publishable anon key from the release APK, POSTs {} to /auth/v1/signup to mint an anonymous JWT (rate limit is 30/hour/IP per config.toml:205, trivially rotated), and with role: authenticated dumps /rest/v1/profiles?select=* — every user's name, @handle, city, photo, playing role and batting/bowling style — plus every post reply body and every team roster, then drives the discover_posts trilateration attack. No account, no email, no traceable identity, and nothing in the schema can tell this caller apart from a real signed-up user.

**Root fix**  
Treat is_anonymous as a first-class distinction in the SQL layer. Add `public.is_real_user() returns boolean` = `coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true`, and require it in the policies/grants that are meant to mean "a real account": the profiles select policy (or move city/playing_role/bowling_style behind an RPC the way phone was moved to profile_private), post_replies select, and discover_posts (guard at the top, raise 28000 otherwise). Leave the deliberately public surfaces (match:% broadcast, the anon viewer tables, public_profile_minimal) untouched — those already have their own anon grants and do not need the authenticated role.

**Skeptic's note**  
Core claim confirmed: the SQL layer cannot distinguish an anonymous session from a real account. `grep -rn is_anonymous backend/` returns zero hits across all 145 migrations and config. Proven live: I minted an HS256 JWT with the local JWT secret carrying role=authenticated, aud=authenticated and is_anonymous=true, and GET /rest/v1/profiles?select=* returned HTTP 200 with the full directory (id, display_name, photo_url, city, batting_style, bowling_style, playing_role, handle) for every row, while the same request with the bare anon key returned 42501 'permission denied for table profiles'. The cited policies read as claimed: profiles_rls.sql:3,6-9 (grant + using(true)), post_replies.sql:10-11, team_members_rls.sql:2,5-6, discover_reads_ball_type.sql:36. The client bootstrap is real (auth_providers.dart:45 and :61) and the gate at discover_screen.dart:37 is client-side only.

CORRECTIONS: (1) The cited evidence line is weak on its own. backend/supabase/config.toml:180 configures the LOCAL stack only — hosted anon sign-in is a dashboard setting, and the currently-running local container in fact has GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED=false (stale container), so /auth/v1/signup returns 'anonymous_provider_disabled' here. The precondition does hold on the deployment that matters: CLAUDE.md:39 records 'Anonymous sign-ins ON' for hosted ref ocejkqihgiinonpyafhl, and the client hard-depends on it. (2) The 'no signup required' framing overstates the delta: enable_signup = true (config.toml:176), so a throwaway email account already reaches every one of these surfaces. Anonymous sessions remove attribution and friction, they are not the sole enabler. (3) profiles no longer has a phone column (dropped in 20260701120150_profiles_drop_phone.sql:18), so no phone number leaks via this path — the finding's own column list is accurate, only its quotation of the public_profile_minimal comment invites that misreading.

Severity medium is right.

---

### [medium] delete_my_account()'s anonymization leaves profile_locations intact — exact home lat/lng plus a street-level place_label survive "GDPR erasure"

- **id**: `delete-account-location-residue` | **front**: Data exposure / PII | **category**: pii-retention | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:30`

**Evidence**

```
The anonymize branch scrubs only four things (lines 25-32):
```sql
    update public.profiles set display_name = 'Deleted user', photo_url = null, city = null, ...
    delete from public.profile_private where id = _me;
    delete from public.looking_for_posts where author_id = _me;
    delete from public.notifications where recipient_id = _me;
```
public.profile_locations (backend/supabase/migrations/20260616203101_locations.sql:1-6: profile_id, geog geography(Point,4326), place_label) is never touched, and because the profiles row is deliberately kept alive the `on delete cascade` never fires. The header comment on line 12 nonetheless claims "The person is gone (GDPR)".

Proven against the running local DB (BEGIN/ROLLBACK) — user saves a home base, owns a match, then deletes their account:
```
              what               |    lat    |    lng    |   place_label   
---------------------------------+-----------+-----------+-----------------
 profile_locations after erasure | 19.076123 | 72.877456 | 12 Nariman Road
```
The app writes this row for every signed-in user: app/lib/src/features/discover/presentation/location_screen.dart:60 calls setMyLocation (app/lib/src/features/discover/data/discover_repository.dart:120-126 -> set_my_location) with the device GPS fix. The same branch also leaves post_replies, dm_messages, blocked_users, guest_claim_requests and team_join_requests rows keyed to the user; the location row is the acute one because it is precise geodata.
```

**Failure scenario**  
A user who has scored a match saves their home ground as their discover anchor, then deletes their account because they are being harassed on the platform. delete_my_account() reports success and the UI says the account is gone, but the database still stores their home coordinates to six decimal places plus the reverse-geocoded street label, indefinitely, keyed to a profile row that is still present. Any future feature, backup export, support query or SQL-level breach re-exposes it, and the deletion receipt shown to the user is false.

**Root fix**  
Add `delete from public.profile_locations where profile_id = _me;` to the anonymize branch, alongside deletes for public.post_replies where author_id = _me, public.blocked_users where blocker_id = _me or blocked_id = _me, public.team_join_requests where requester_id = _me, and public.guest_claim_requests where requested_by = _me. Extend backend/supabase/tests/97-delete-account.test.sql to assert profile_locations is empty for the deleted uid. Either blank dm_messages.body for messages the user sent, or state explicitly in the privacy policy that sent messages are retained as the recipient's data.

**Skeptic's note**  
Confirmed and reproduced. The anonymize branch (20260703160000_rpc_delete_my_account.sql:25-32) touches only profiles, profile_private, looking_for_posts and notifications; public.profile_locations (20260616203101_locations.sql:1-6) is never referenced, and since the profiles row is deliberately kept, its on-delete-cascade never fires. Reproduced in BEGIN/ROLLBACK: set_my_location(19.076123, 72.877456, '12 Nariman Road'), create two teams + a match, delete_my_account() → profiles.display_name = 'Deleted user' but profile_locations still holds lat 19.076123, lng 72.877456, place_label '12 Nariman Road'. The write path is real (app/lib/src/features/discover/presentation/location_screen.dart:59-68 → discover_repository.dart:124-129 → set_my_location, guarded only to skip anonymous sessions), and the residue list is accurate — post_replies/dm_messages/blocked_users/team_join_requests/guest_claim_requests all have CASCADE FKs to profiles that likewise never fire because the profiles row survives.

Severity lowered from high to medium: this is pure retention, not exposure. profile_locations has only the owner-scoped policy `profile_locations_owner_all` (locations.sql:10-11), the RPC that reads it is self-scoped (my_home_location, 20260625120000:6-14), and the auth user is banned_until='infinity' with sessions/identities deleted — so no live caller can read the retained row. The harm is a false erasure receipt plus a backup/breach/future-feature exposure, not a reachable leak.

---

### [medium] The DM inbox only subscribes from a ref.listen callback, which never fires because dmInboxProvider is already resolved when the screen mounts - inbox live updates are dead on the normal path

- **id**: `rt-inbox-listen-never-fires` | **front**: Realtime & concurrency | **category**: realtime | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_inbox_screen.dart:86`

**Evidence**

```
_syncSubscriptions has exactly one caller, a change-only listener (dm_inbox_screen.dart:84-89):
```dart
final inbox = ref.watch(dmInboxProvider);
ref.listen(dmInboxProvider, (_, next) {
  final threads = next.value;
  if (threads != null) _syncSubscriptions(threads);
});
```
`ref.listen` in flutter_riverpod-3.3.2 (lib/src/core/consumer.dart:524-546) has no fireImmediately and only calls the listener on a subsequent change. dmInboxProvider is already in the data state before this screen mounts, because the parent Discover tab keeps it alive: discover_screen.dart:82 `count: ref.watch(dmUnreadCountProvider)` and discover_providers.dart:199-206 `final dmUnreadCountProvider = Provider<int>((ref) { final inbox = ref.watch(dmInboxProvider).value ?? const []; ... })`. DiscoverScreen sits below /discover/messages in the same branch Navigator (app_router.dart:198), so it stays mounted and the provider is never disposed.
```

**Failure scenario**  
User is on Discover (dmInboxProvider loads, transitions loading -> data while DmInboxScreen is not yet mounted). User taps Messages. DmInboxScreen builds, ref.watch returns AsyncData immediately, ref.listen registers but never fires. _syncSubscriptions is never called, _subs stays empty, and the inbox has zero realtime subscriptions - a new incoming DM does not move the row, does not bump the unread badge, and does not reorder the list. The feature only starts working after some unrelated invalidation of dmInboxProvider.

**Root fix**  
Call _syncSubscriptions from the data branch of the `inbox.when(...)` build (or from a post-frame callback seeded with `ref.read(dmInboxProvider).value`) in addition to the listener, so the current value is handled and not just future changes.

**Skeptic's note**  
Verified: _syncSubscriptions has exactly one caller (dm_inbox_screen.dart:86-89), consumer.dart:524-546 ref.listen has no fireImmediately and only notifies on a subsequent change, and dmInboxProvider is a plain (non-autoDispose) FutureProvider (discover_providers.dart:145) kept resolved and alive by DiscoverScreen's `count: ref.watch(dmUnreadCountProvider)` (discover_screen.dart:82 -> discover_providers.dart:199-206) which stays mounted below /discover/messages in the same branch navigator. So on the Discover -> Messages path _subs is empty on mount and no inbox channel exists. Scope correction: it is not permanently dead - the inbox's own pull-to-refresh (line 103), opening any thread (_markRead's invalidate), compose, or a block all invalidate the provider and populate _subs; and the thread screen carries its own channel. So the real impact is 'a DM arriving while the user sits on a freshly opened inbox does not move the row or bump the badge', which matches medium, not higher.

---

### [medium] DmInboxScreen.dispose() calls ref.read, which throws StateError during unmount, so its realtime channels are never removed and leak on every visit

- **id**: `rt-ref-read-in-dispose-throws` | **front**: Realtime & concurrency | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_inbox_screen.dart:75`

**Evidence**

```
dm_inbox_screen.dart:72-81:
```dart
@override
void dispose() {
  if (_subs.isNotEmpty) {
    final c = ref.read(supabaseClientProvider);   // line 75
    for (final ch in _subs.values) { c.removeChannel(ch); }
  }
  super.dispose();
}
```
flutter_riverpod-3.3.2 lib/src/core/consumer.dart:469-477 - `read` calls `_assertNotDisposed()`, which throws when `!context.mounted`:
```dart
throw StateError('Using "ref" when a widget is about to or has been unmounted is unsafe. ... To safely refer to the state of providers inside State.dispose(), save the provider state in a field of your State class.');
```
Flutter framework.dart:6028-6030 - StatefulElement.unmount() calls `super.unmount()` (which sets `_widget = null` at framework.dart:4863, making `context.mounted` false) BEFORE `state.dispose()`. The sibling screen already knows this: match_viewer_screen.dart:48 `SupabaseClient? _client; // captured for safe teardown (ref is unsafe in dispose)`, and dm_thread_screen.dart:174 correctly uses the captured `_c`. dm_inbox_screen is the only dispose() in app/lib that touches ref.
```

**Failure scenario**  
User opens Messages, opens any conversation (which invalidates dmInboxProvider via _markRead and therefore populates _subs), then navigates back out of Messages. dispose() runs with _subs non-empty, ref.read throws StateError, the exception escapes dispose and is reported as a framework error, and the `removeChannel` loop never executes. Every private 'dm:<id>' channel stays joined on the socket. Repeating the visit accumulates joined channels, and each still fires `ref.invalidate(dmInboxProvider)` against a disposed widget's captured ref.

**Root fix**  
Capture the client in a field during initState (`_client = ref.read(supabaseClientProvider);`) exactly as MatchViewerScreen does at match_viewer_screen.dart:58-59, and use `_client?.removeChannel(ch)` in dispose. Never touch ref in dispose.

**Skeptic's note**  
Verified in the pinned sources: flutter_riverpod-3.3.2/lib/src/core/consumer.dart:469-477 _assertNotDisposed throws a plain StateError (not an assert, so it fires in release too) whenever !context.mounted, and read() calls it at :555-558; framework.dart:4851-4865 Element.unmount sets _widget = null (mounted false) and StatefulElement.unmount (:6028-6030) calls super.unmount() BEFORE state.dispose(). So dm_inbox_screen.dart:75 throws and the removeChannel loop at :76-78 never runs. Reachability confirmed: _subs is populated by any dmInboxProvider change while the inbox is mounted - including its own pull-to-refresh invalidate at line 103 - not just by opening a thread. Two corrections to the consequence: the throw does not crash the app (BuildOwner.finalizeTree, framework.dart:3339-3438, catches and reports it via _reportException), but it does abort the rest of that _unmountAll pass, so sibling elements queued behind it also skip dispose. Severity medium: leaked joined channels plus recurring error reports, no data loss or security impact.

---

### [medium] undo_last_ball has no _expected_last_seq fence and no client busy-guard, so it deletes whatever is currently the last ball - including another device's just-recorded ball, or two balls on a double tap

- **id**: `scor-undo-unfenced` | **front**: Realtime & concurrency | **category**: concurrency | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260616202001_rpc_corrections.sql:14`

**Evidence**

```
undo_last_ball takes only the innings id (20260616202001_rpc_corrections.sql:7-16):
```sql
create or replace function public.undo_last_ball(_innings_id uuid)
...
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));
  delete from public.deliveries where innings_id = _innings_id
    and seq = (select max(seq) from public.deliveries where innings_id = _innings_id);
```
record_ball got a fence in the same sweep (20260706110600_record_ball_cap_stale.sql:43-46) but undo did not. The console's Undo button also never sets _busy, while the pad's AbsorbPointer is driven by _busy (scoring_console_screen.dart:512-513 `AbsorbPointer(absorbing: _bowlerId == null || _busy, ...)`):
```dart
_Btn(
  label: 'Undo',                       // line 829
  onTap: () async {
    try { await _repo.undoLastBall(inningsId); }   // line 832 - no setState(() => _busy = true)
    catch (e) { _toast('Could not undo: $e'); }
    ref.invalidate(inningsStateProvider(inningsId));
  },
),
```
Same omission on 'Swap strike' (scoring_console_screen.dart:845-852).
```

**Failure scenario**  
(1) Single device: the scorer taps Undo twice inside the RPC round-trip (the pad stays interactive because _busy is never set). Two undo_last_ball calls run, two deliveries are deleted, the scorer intended one. (2) Two devices on the same scorer account (the exact threat model SCOR-24 was written for): tablet records ball seq=40; the phone, whose console holds a stale fold and never subscribes to realtime, taps Undo. undo_last_ball deletes max(seq)=40 - the tablet's ball - not the ball the phone's user was looking at (seq=39). No error is raised on either device; the delivery is silently gone.

**Root fix**  
Add an `_expected_last_seq bigint` parameter to undo_last_ball, taken after the advisory lock, and raise the same 'the innings changed on another device' error when it does not match max(seq); have the console pass s['last_seq'] exactly as _record does. Independently, wrap the Undo and Swap-strike handlers in the `setState(() => _busy = true) ... finally _busy = false` pattern that _record (scoring_console_screen.dart:70-71) and _retire (962-974) already use, so the AbsorbPointer blocks the second tap.

**Skeptic's note**  
Both halves verified. undo_last_ball exists in exactly one migration (grep over all 145 files: only 20260616202001_rpc_corrections.sql), takes only _innings_id, and deletes max(seq) - no fence, never superseded. match_repository.dart:195-196 passes only _innings_id. The console's Undo (scoring_console_screen.dart:828-838) and Swap strike (843-853) handlers never set _busy, while the AbsorbPointer that gates the pad is driven by _busy (512-513) and _Btn (1255-1277) is a plain OutlinedButton with no internal debounce, so a second tap inside the round-trip does fire a second RPC and two deliveries are deleted. Severity lowered from high to medium: the harm is one extra delivery silently deleted (recoverable by re-recording, and the fold/score redisplays immediately); the two-device variant is real but needs the same scorer account live on two devices at once.

---

### [medium] Release build silently falls back to the debug signing key when android/key.properties is absent

- **id**: `release-falls-back-to-debug-signing` | **front**: Build & release config | **category**: release-signing | **runs**: 1+2
- **where**: `app/android/app/build.gradle.kts:57`

**Evidence**

```
app/android/app/build.gradle.kts:53-63:
```kotlin
buildTypes {
    release {
        signingConfig = if (keystorePropertiesFile.exists()) {
            signingConfigs.getByName("release")
        } else {
            signingConfigs.getByName("debug")
        }
    }
}
```
`key.properties` is gitignored (app/android/.gitignore:14 `key.properties`, plus `**/*.jks`), and oauth-provisioning.md:18 confirms the keystore itself lives at `~/pitch-release-keystore.jks`, OUTSIDE the repo. The fallback emits no warning, no log line, and no build failure.
```

**Failure scenario**  
Three concrete failures. (1) Play Store: `flutter build appbundle --release` on any machine without key.properties yields an AAB signed with the Android debug key; Play rejects it at upload with 'You uploaded an APK or Android App Bundle that was signed in debug mode', discovered only after the release is cut. (2) Google Sign-In: the registered Android OAuth clients bind package `dev.pitch.pitch_app` to exactly two SHA-1s — debug `93:8A:C0:0B:...:1E:56` and release `43:1A:49:F8:...:52:4F` (oauth-provisioning.md:12,18). A debug-key fallback on a *different* machine produces a third, unregistered SHA-1, so `GoogleSignIn.authenticate()` (app/lib/src/features/auth/data/oauth_sign_in.dart:55) fails with ApiException:10 (DEVELOPER_ERROR) — and since the email/password shim is `kDebugMode`-only (sign_in_screen.dart:59), the release APK then has no working sign-in at all. (3) The friend already has an install signed with the release key; a debug-signed 'update' fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE and can only be installed by uninstalling first, destroying the local session/data.

**Root fix**  
Remove the silent fallback. Either fail the build (`throw GradleException("android/key.properties missing - cannot build a signed release")` inside the `release { }` block when `!keystorePropertiesFile.exists()`), or keep the fallback but make it impossible to mistake: `println("WARNING: key.properties absent - release will be DEBUG-SIGNED")` and set `versionNameSuffix = "-unsigned"` / `applicationIdSuffix = ".debugsigned"` so a debug-signed artifact cannot masquerade as the real one. Also read the keystore path/passwords from env vars as a CI fallback before falling through to debug.

**Skeptic's note**  
Code verified verbatim at app/android/app/build.gradle.kts:53-63 — `signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")`, with the comment at :10-12 confirming the fallback is intentional. `key.properties` is gitignored (app/android/.gitignore:13, not :14 as cited — trivial off-by-one) alongside `**/*.keystore` and `**/*.jks` (:14-15), and oauth-provisioning.md:18 confirms the keystore lives at `~/pitch-release-keystore.jks`, outside the repo. No warning, no failure. The three failure paths are mechanically sound; the strongest is (3), since a debug-signed 'update' over the friend's release-signed install genuinely fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE. SEVERITY CORRECTED high -> medium, on two grounds. (a) Failure (1) — Play rejecting a debug-signed AAB — is caught loudly by Play at upload, so it wastes time but cannot ship. (b) Failure (2) as written overstates the reach: on THIS machine the debug keystore's SHA-1 `93:8A:C0:0B:...:1E:56` IS a registered Android OAuth client (oauth-provisioning.md:12,16), so a debug-signed build here still has working Google sign-in; DEVELOPER_ERROR only appears on a second machine with a different debug keystore, and this is a single-developer project with no CI. The claim that the release APK would then have no sign-in at all (because sign_in_screen.dart:59 gates the email/password shim on `kDebugMode`) is correct as far as it goes, but only in that cross-machine case.

---

### [medium] posts_update_author drops the is_team_admin condition that posts_insert_author enforces, allowing team impersonation in the Discover feed

- **id**: `rls-posts-update-team-impersonation` | **front**: RLS & authorization | **category**: authorization-bypass | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260616203202_looking_for_posts.sql:26`

**Evidence**

```
create policy "posts_insert_author" on public.looking_for_posts for insert to authenticated
  with check (author_id = (select auth.uid()) and (team_id is null or public.is_team_admin(team_id)));
create policy "posts_update_author" on public.looking_for_posts for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));

The UPDATE policy's WITH CHECK omits the `team_id is null or is_team_admin(team_id)` clause, so the insert-time team gate (also enforced in create_looking_for_post, 20260706111100_posts_ball_type.sql:17) is a one-shot check the author can undo. discover_posts joins the post's team_id straight to teams.name and returns it as `team_name` (20260706111200_discover_reads_ball_type.sql:24,21), as does post_detail (:49,46).
```

**Failure scenario**  
Verified live. Attacker is not an admin of the victim's team (is_team_admin = f, so create_looking_for_post with _team_id would raise 'not authorized'). Instead:
 1. rpc/create_looking_for_post('team_seeking_opponent','loser_pays',lat,lng,'come get some') with no team.
 2. PATCH /rest/v1/looking_for_posts?id=eq.<my post> {"team_id":"<victim's team uuid>"} -> UPDATE 1.
 3. discover_posts(lat,lng,50000) returns that post with team_name = 'Andheri Sluggers' (the victim's team) and author_name = 'Attacker'.
The post now advertises, arranges fixtures for, and collects replies on behalf of a team the attacker has no relationship with; team ids are freely enumerable via teams_select_authenticated `using (true)` and search_players_and_teams.

**Root fix**  
Make the UPDATE policy match the INSERT policy: `with check (author_id = (select auth.uid()) and (team_id is null or public.is_team_admin(team_id)))`. Given looking_for_posts already funnels creation through a SECURITY DEFINER RPC, the cleaner option is to revoke UPDATE from authenticated and add an update_looking_for_post RPC that re-runs the same team-admin check (cancel_post / mark_post_filled already exist for the status transitions).

**Skeptic's note**  
Confirmed. 20260616203202_looking_for_posts.sql:22 grants update to authenticated; :24-25 (insert) enforces `team_id is null or is_team_admin(team_id)` while :26-27 (update) enforces only `author_id = auth.uid()`. The only later change to these policies is 20260702170000_looking_for_posts_hide_geog.sql:7-11, which replaces the SELECT policy and leaves posts_update_author untouched; create_looking_for_post's team gate (20260706111100_posts_ball_type.sql:17) is therefore one-shot. Reproduced live in a rolled-back transaction: is_team_admin(<victim team>)=f, create_looking_for_post with no team, then `update looking_for_posts set team_id=<victim team>` -> UPDATE 1, and discover_posts(19.1,72.8,50000) returned that post with team_name='Lions 131223' (the victim's team) and author_name=the attacker - matching the join at 20260706111200_discover_reads_ball_type.sql:21-24. Medium is the right ceiling: the impersonation is a display-name/attribution issue in the feed and post_detail; the forged team_id confers no privileged capability over the victim team.

---

### [medium] All 183 widget tests run only on the 800x600 default surface; at a real phone width the unmodified suite has 5 failures on 3 screens

- **id**: `no-widget-test-runs-on-a-phone-viewport` | **front**: Stale Flutter tests | **category**: test-coverage | **runs**: 2
- **where**: `app/test/match_viewer_test.dart:71`

**Evidence**

```
`grep -rn "physicalSize|setSurfaceSize|textScaler" app/test` -> no matches, and app/test has no `flutter_test_config.dart`. Every test renders at the flutter_test default 800x600 logical, wider than any phone the app ships on.

EXPERIMENT: added only `app/test/flutter_test_config.dart` setting `implicitView.physicalSize = Size(1170,2532)` / `devicePixelRatio = 3.0` (iPhone 13/14/15/16 Pro = 390x844 logical), changed nothing else, ran `flutter test`:
```
00:08 +178 -5: Some tests failed.
Failing tests:
  test/bridge_test.dart: team_seeking_opponent post offers Propose a match on TargetPlatform.android
  test/bridge_test.dart: team_seeking_opponent post offers Propose a match on TargetPlatform.iOS
  test/discover_test.dart: feed filter bar offers skill / overs / date filters (DISC-3)
  test/tournament_screens_test.dart: public page: 4 tabs + champion banner on TargetPlatform.iOS
  test/tournament_screens_test.dart: public page: 4 tabs + champion banner on TargetPlatform.android
```
Diagnostics captured via `FlutterError.onError`:
- `A RenderFlex overflowed by 54 pixels on the right.` -> `Row:app/lib/src/features/discover/presentation/post_detail_screen.dart:103` (FlairChip + mode label, neither child Flexible)
- `A RenderFlex overflowed by 26 pixels on the right.` -> `Row:app/lib/src/features/tournaments/presentation/tournament_page_screen.dart:92` (`_ChampionBanner`: Icon + `Text('Champions: ${name}')`, Text has no Expanded/Flexible)
- discover_test.dart:80 `tester.tap(find.text('<= 20 ov'))` warns "would not hit test" (chip off the right edge) so line 82 `expect(seenQueries.last.maxOvers, 20)` receives `null`.

Honest caveat: flutter_test uses the Ahem test font (1em per glyph), so the exact pixel counts are inflated versus a real font. The structural defect is real regardless - both Rows place an unbounded `Text` beside a fixed-width child with no `Flexible`/`Expanded`, so they overflow for long team names or with OS text scaling.
```

**Failure scenario**  
A team named e.g. "Mumbai Indians Cricket Club" (or any user with iOS/Android 'Larger Text' enabled) opens a completed tournament page: `_ChampionBanner`'s Text runs past the container and Flutter paints the yellow/black overflow stripes across the champion banner. Same for the flair + mode row on post detail. Neither can ever be caught by the current suite because no test renders at a phone width or a non-1.0 textScaler.

**Root fix**  
Add `app/test/flutter_test_config.dart` pinning a phone surface (390x844) for the whole suite; wrap the Text children of both Rows in `Flexible(child: Text(..., overflow: TextOverflow.ellipsis))`; make the DISC-3 filter test scroll the filter bar before tapping the overs chip. Optionally add a second pass at textScaler 1.5.

**Skeptic's note**  
Independently reproduced. app/test has no flutter_test_config.dart and zero physicalSize/setSurfaceSize/textScaler references. I copied app/ to a scratchpad, added ONLY a flutter_test_config.dart pinning implicitView.physicalSize = 1170x2532 / devicePixelRatio 3.0, and got exactly '+178 -5' with precisely the 5 failures named (bridge_test x2, discover_test DISC-3, tournament_screens_test x2) and RenderFlex overflows of 54 and 26 pixels. That also confirms the suite is 183 tests, not 159. Both Rows are structurally as described: app/lib/src/features/discover/presentation/post_detail_screen.dart:103 (FlairChip + bare Text) and app/lib/src/features/tournaments/presentation/tournament_page_screen.dart:92 (_ChampionBanner: Icon + SizedBox + bare Text, no Flexible/Expanded). CORRECTION TO SEVERITY: the pixel numbers are Ahem-font artifacts, as the finding concedes. With a real 14pt w600 font the banner has ~316 logical px for 'Champions: <name>' on a 390-wide phone, so the fixture string 'Champions: Dadar Dynamos' fits comfortably; overflow needs a ~30+ character team name or textScale of roughly 1.4+. Consequence is cosmetic overflow stripes on the banner / flair row, not broken function — medium, not high.

---

### [medium] MISS-9 "Share the full scorecard instead" throws Duplicate GlobalKey and can leave the capture button dead - zero test coverage

- **id**: `share-full-scorecard-duplicate-globalkey` | **front**: Stale Flutter tests | **category**: correctness | **runs**: 2
- **where**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart:157`

**Evidence**

```
One GlobalKey is reused by two RepaintBoundaries in two modal routes.

match_viewer_screen.dart:52  `final GlobalKey _shareKey = GlobalKey();`
match_viewer_screen.dart:135-137 (summary sheet)
```
                RepaintBoundary(
                  key: _shareKey,
                  child: MatchShareCard(
```
match_viewer_screen.dart:154-159 (the MISS-9 entry point)
```
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _shareFullScorecard();
                  },
                  child: const Text('Share the full scorecard instead'),
```
match_viewer_screen.dart:239-241 (full scorecard sheet)
```
                RepaintBoundary(
                  key: _shareKey,
                  child: FullScorecardCard(
```
`_shareFullScorecard()` only awaits already-cached providers, so `showModalBottomSheet` runs while the first sheet's pop animation is still in flight and both boundaries hold `_shareKey`.

PROVEN by running a probe widget test against an unmodified copy of app/lib (Flutter 3.44.2):
```
PROBE exception: FlutterError
  Duplicate GlobalKey detected in widget tree.
  ... The specific parent that did not update after having one or more children
  forcibly removed due to GlobalKey reparenting is: Column(...)
PROBE FullScorecardCard found: 1
PROBE MatchShareCard still in tree: 0
```
Reproduced at the default 800x600 surface AND at iPhone 13/14/15/16 Pro size (physicalSize 1170x2532 @3.0 = 390x844 logical), using the same `_pump` fixture as app/test/match_viewer_test.dart.

Coverage: `grep -rn "FullScorecardCard" app/test app/integration_test` -> no matches. app/test/match_viewer_test.dart:192-205 opens the share sheet but only asserts `find.text('Pitch')`, `find.text('45/2')` and `find.widgetWithText(FilledButton, 'Share image')`; it never taps 'Share the full scorecard instead'. app/test/match_share_card_test.dart only builds the small `MatchShareCard`.
```

**Failure scenario**  
User opens /watch/<id>, taps the share icon (match_viewer_screen.dart:338-340), then taps "Share the full scorecard instead". Flutter reports "Duplicate GlobalKey detected in widget tree" (error banner/console error in debug; undefined reparenting in release). Because `_shareKey` has been forcibly reparented, `_captureAndShare` (line 267-269) can resolve `_shareKey.currentContext` to the boundary that was torn out or to null, in which case `if (boundary == null) return;` makes the "Share image" button do nothing at all - a silently dead button on the headline Sweep-Unit-D feature. The 183-test suite is green through all of this.

**Root fix**  
Give each sheet its own GlobalKey (e.g. `_summaryShareKey` and `_scorecardShareKey`), or `await` the first sheet's `showModalBottomSheet` future before calling `_shareFullScorecard()` so the first route is fully gone. Then add a widget test that taps 'Share the full scorecard instead', asserts `tester.takeException()` is null, and asserts `FullScorecardCard` renders the batting/bowling rows.

**Skeptic's note**  
Mechanism verified by reading app/lib/src/features/scoring/presentation/match_viewer_screen.dart (one _shareKey at :52, used at :136 in the summary sheet and :240 in the full-scorecard sheet, read at :268) and reproduced empirically on an unmodified copy of app/ in my scratchpad: tapping 'Share the full scorecard instead' produces exactly one FlutterError, 'Duplicate GlobalKey detected in widget tree ... The specific parent that did not update ... is Column(...)'. Without a FlutterError.onError override the probe test FAILS, so a real test would catch it. TWO CORRECTIONS. (a) The 'silently dead button' half is NOT supported: after the reparent my probe shows MatchShareCard in tree = 0, FullScorecardCard in tree = 1, and the surviving 'Share image' button's _captureAndShare resolves a boundary and completes with no exception. The key moves to the NEW boundary, so the user still gets the right image; the observable damage is the framework error (console error in debug, silent subtree truncation in release) plus the outgoing sheet losing its card mid-animation. That is why severity is medium, not critical. (b) Worth adding for whoever writes the test: at the flutter_test default 800x600 surface the TextButton lays out at Offset(400, 651.5), outside the 600-tall root, so a naive tester.tap() misses with 'would not hit test' and nothing happens — the probe only reproduces after tester.ensureVisible(). The zero-coverage claim (no 'FullScorecardCard' reference anywhere in app/test or app/integration_test) is correct.

---

### [medium] Sweep B/C/D features and mandatory-path screens have no widget test; console_sweep only asserts that two buttons' labels exist

- **id**: `sweep-features-with-no-widget-test` | **front**: Stale Flutter tests | **category**: test-coverage | **runs**: 2
- **where**: `app/test/console_sweep_test.dart:83`

**Evidence**

```
The test that claims SCOR-16 coverage never opens either flow:
```
// app/test/console_sweep_test.dart:83-94
testWidgets('console offers swap strike + retire on $platform', (tester) async {
  ...
  expect(find.text('Swap strike'), findsOneWidget);
  expect(find.text('Retire'), findsOneWidget);
```
Both are labels of `_Btn`s inside the pad, which the same fixture renders under `AbsorbPointer(absorbing: _bowlerId == null || _busy)` (scoring_console_screen.dart:512-513). The retire sheet `_retire` (scoring_console_screen.dart:867-977) is never opened: `grep -rn "Retire batter" app/test app/integration_test` -> no matches.

Screens with ZERO widget test (every *_screen.dart in app/lib cross-referenced against imports in app/test):
- app/lib/src/features/scoring/presentation/toss_openers_screen.dart (mandatory step of every match setup)
- app/lib/src/features/profile/presentation/edit_profile_screen.dart
- app/lib/src/features/messages/presentation/dm_thread_screen.dart
- app/lib/src/features/discover/presentation/my_posts_screen.dart
- app/lib/src/features/tournaments/presentation/tournaments_list_screen.dart

New sweep functionality with no widget test: the guest career page (`PlayerStatsScreen(isGuest: true)` / `guestPlayerStatsProvider`, app/lib/src/features/stats/data/stats_providers.dart:22-33, route /player/guest/:memberId at app/lib/src/core/routing/app_router.dart:116-122) - app/test/player_stats_test.dart only ever builds `PlayerStatsScreen(profileId: 'p1')` with `isGuest` defaulting to false and only overrides `playerStatsProvider`; the schedule editor (`updateMatchSchedule`, start_match_screen.dart:87 and manage_tournament_screen.dart:287); and `FullScorecardCard`.
```

**Failure scenario**  
`guest_player_profile` returns no row for an unknown or deleted member id, so `res as Map` at stats_providers.dart:27 throws a TypeError and every /player/guest/<id> link from a roster row renders the error state; nothing in the suite exercises the guest branch. Likewise a regression in toss_openers_screen blocks every new match at setup unnoticed, and the retire sheet's null-assert at scoring_console_screen.dart:966 `(who == 'striker' ? strikerId : nonStrikerId)!` crashes when the fold has a null non-striker, with the suite green.

**Root fix**  
Add widget tests that (a) tap 'Retire', assert the sheet's chips/dropdown and the exact retireBatter args via a spy repository, (b) build `PlayerStatsScreen(profileId: 'm1', isGuest: true)` with `guestPlayerStatsProvider` overridden including the null-RPC-response case, (c) cover toss_openers_screen, edit_profile_screen, dm_thread_screen, my_posts_screen and tournaments_list_screen on both platforms.

**Skeptic's note**  
Every claim checks out. app/test/console_sweep_test.dart:83-90 asserts only find.text('Swap strike') / find.text('Retire'), and those _Btns live inside _pad, which the fixture renders under AbsorbPointer(absorbing: _bowlerId == null || _busy) at app/lib/src/features/scoring/presentation/scoring_console_screen.dart:512-513 with no bowler picked — so the labels are inert. grep for 'Retire batter' and 'FullScorecardCard' across app/test and app/integration_test returns nothing, and grep for each of toss_openers_screen, edit_profile_screen, dm_thread_screen, my_posts_screen, tournaments_list_screen returns no test file. app/test/player_stats_test.dart:84-87 overrides only playerStatsProvider and builds PlayerStatsScreen(profileId: 'p1') with isGuest defaulting to false, while the guest route exists at app/lib/src/core/routing/app_router.dart:116-122. The guest-null failure path is REAL: backend/supabase/migrations/20260706111900_rpc_guest_player_profile.sql is a plain SQL function selecting from team_members, so an unknown/deleted member id yields zero rows and the RPC returns NULL, which makes 'res as Map' at app/lib/src/features/stats/data/stats_providers.dart:27 throw. ONE CORRECTION: the retire null-assert at scoring_console_screen.dart:966 does not 'crash' — it is evaluated inside the try whose catch (e) { _toast('$e'); } at :970-971 swallows it, so a null non-striker produces a toast, not a crash. Severity medium stands.

---

### [medium] Every scoring/discover write RPC name, parameter name and extras-composition rule can be corrupted and all 183 tests stay green

- **id**: `write-path-entirely-unverified-mutations-survive` | **front**: Stale Flutter tests | **category**: test-coverage | **runs**: 2
- **where**: `app/test/scoring_test.dart:13`

**Evidence**

```
No test in app/test constructs a spy/fake repository that records calls. The only fake is a stub that asserts nothing:
```
// app/test/scoring_test.dart:13-16
class _FakeMatchRepository extends Fake implements MatchRepository {
  @override
  Future<void> markInningsBreak(String matchId) async {}
}
```
`grep -rn "recordBall|retireBatter|swapStrike|updateMatchSchedule|guest_player_profile" app/test app/integration_test` -> only integration tests call raw RPCs; no widget test exercises MatchRepository at all.

MUTATION RUN (copy of app/, `flutter test`, baseline 183 passed). 14 simultaneous mutations, ALL SURVIVED - "183: All tests passed!":
- app/lib/src/features/scoring/presentation/scoring_console_screen.dart:90 `expectedLastSeq: lastSeq` -> `null` (SCOR-24 optimistic-concurrency fence disabled)
- app/lib/src/features/scoring/data/match_repository.dart:137 `'_expected_last_seq'` -> `'_MUT_expected_last_seq'`
- match_repository.dart:155 `'_retiring_batter_id'` -> `'_MUT_batter_id'`
- match_repository.dart:162 `rpc('swap_strike'` -> `rpc('MUT_swap_strike'`
- match_repository.dart:167 `rpc('mark_innings_break'` -> `rpc('MUT_mark_innings_break'`
- match_repository.dart:177 `'_scheduled_at'` -> `'_MUT_scheduled_at'`
- match_repository.dart:25 `'_rules': {'max_overs_per_bowler': ...}` -> `'_MUT_rules'` (SCOR-15 bowler quota never reaches create_match)
- app/lib/src/features/stats/data/stats_providers.dart:26 `rpc('guest_player_profile'` -> `rpc('MUT_guest_player_profile'`
- app/lib/src/features/discover/data/discover_repository.dart:68 `params['_ball_type']` -> `params['_MUT_ball_type']`
- scoring_console_screen.dart:295 `wides: 1 + runs` -> `wides: 1` (extra runs off a wide silently dropped)
- scoring_console_screen.dart:305 `noballSecondaryKind: runs > 0 ? nbKind : null` -> `null`
- scoring_console_screen.dart:291 `final pen = penalty ? 5 : 0;` -> `final pen = 0;` (+5 penalty never recorded)
- scoring_console_screen.dart:1237-1239 `dismissedId` always `strikerId` (a run-out of the non-striker credits the wrong batter)
- scoring_console_screen.dart:848 `await _repo.swapStrike(inningsId);` -> no-op
```

**Failure scenario**  
Any of these is a shipping regression that reaches the hosted DB: e.g. `record_ball` gains `_expected_last_seq` in migration 20260706110600 but the client sends `_MUT_expected_last_seq` -> PostgREST raises "function public.record_ball(...) does not exist", every ball tap fails, and the suite is green. Or `_rules` is dropped from create_match -> `max_overs_per_bowler` is never set, record_ball's cap never fires, and the SCOR-15 'At over limit' UI that console_sweep_test.dart:153-160 DOES assert is decoration over a rule the server never enforces.

**Root fix**  
Add a recording fake: `class _SpyMatchRepository extends Fake implements MatchRepository` that captures every call's named arguments, override `matchRepositoryProvider` with it in console_sweep_test/scoring_test, and assert the exact args for a wide+2, a no-ball with byes, a +5 penalty, a non-striker run-out, retire, swap-strike and expectedLastSeq. Separately add a contract test per RPC asserting the Dart param-name set matches the migration's CREATE FUNCTION signature.

**Skeptic's note**  
The coverage gap is real and every citation checks out: app/test/scoring_test.dart:13-16 is the only MatchRepository fake and it overrides markInningsBreak only; nothing in app/integration_test imports MatchRepository or calls recordBall (integration tests hit raw c.rpc(...) instead, e.g. live_push_test.dart:117), so no test in the repo pins a single client-side RPC name, param name, or extras-composition rule. All cited lines are exact: match_repository.dart:25 '_rules', :137 '_expected_last_seq', :155 '_retiring_batter_id', :162 swap_strike, :167 mark_innings_break, :177 '_scheduled_at'; scoring_console_screen.dart:90 expectedLastSeq: lastSeq, :291 pen = penalty ? 5 : 0, :295 wides: 1 + runs, :305 noballSecondaryKind, :848 swapStrike, :1237-1239 dismissedId. CORRECTION TO SEVERITY: there is no live defect — I diffed the Dart param set against the current signature in backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:15-24 and every name the client sends exists there, including _expected_last_seq. This is a pure regression-detection gap (a future mutation ships green), not a shipping bug, so 'critical' is inflated; medium.

---

### [medium] _expected_last_seq is a max(seq) high-water mark, not a version token: edit_ball changes the state without changing it, so test 102's 'stale append is rejected' assertion overclaims

- **id**: `stale-fence-blind-to-edits` | **front**: Stale pgTAP tests | **category**: correctness | **runs**: 2
- **where**: `backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:43`

**Evidence**

```
record_ball_cap_stale.sql:43-46 `select coalesce(max(seq),0) into _cur_last from public.deliveries where innings_id = _innings_id; if _expected_last_seq is not null and _cur_last <> _expected_last_seq then raise exception 'the innings changed on another device - refresh before recording'`. compute_innings_state exposes it as `'last_seq', _last_seq` (fold_v14_events.sql:215) where `_last_seq := d.seq` per row - i.e. also just max(seq). edit_ball (20260705120100_corrections_apply_guard.sql) mutates runs/extras/wicket_type in place and never touches seq; delete_ball of a non-last row leaves max(seq) unchanged too. tests/102-record-ball-cap-stale.test.sql:43-46 only exercises the append shape and labels it 'an append computed against a stale state is rejected'.
```

**Failure scenario**  
Reproduced: two balls recorded, device A folds and holds last_seq=2. Device B calls edit_ball on seq 1 turning a single into a six - compute_innings_state now reports runs=7 and a different striker, but last_seq is still 2. Device A then calls `record_ball(..., _expected_last_seq := 2)` and it is ACCEPTED (returned delivery id 3fa98326-...). Device A's ball is attributed to the striker it thought was on strike, silently corrupting the innings - precisely the interleaving SCOR-24 claims to prevent. The same hole applies to delete_ball of a mid-innings delivery.

**Root fix**  
Make the token a real version: add a monotonic `revision bigint` to innings bumped by an AFTER INSERT/UPDATE/DELETE trigger on deliveries, return it as the fold's version field, and fence record_ball / edit_ball / insert_ball / delete_ball / retire_batter / swap_strike on it. Then extend test 102 with an edit_ball case and a delete_ball case.

**Skeptic's note**  
Mechanism confirmed and reproduced. The fence at backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:43-46 compares coalesce(max(seq),0) against _expected_last_seq, and the fold's token is the same quantity (20260706110100_fold_v14_events.sql:43,215). edit_ball (20260705120100_corrections_apply_guard.sql:24-31) never touches seq; delete_ball (20260623130000_restamp_strike.sql:71-83) deletes without renumbering. Reproduced: two balls -> last_seq=2; edit_ball on seq 1 to 6 runs -> state runs jumps to 6, striker changes, last_seq still 2; record_ball(..., _expected_last_seq := 2) is ACCEPTED. Deleting the mid-innings seq-2 row left last_seq=3 with only 2 rows, so deletes evade it too. The console does pass the token (scoring_console_screen.dart:90,783,1249), so the two-device path is live.

SEVERITY CORRECTED high -> medium. The finding overstates the harm: record_ball re-folds server-side and stamps striker_id/non_striker_id from the CURRENT state (record_ball_cap_stale.sql:48-50,101), so the row written is internally consistent; what leaks through is the scorer's intent (runs/wicket_type/dismissed_player_id chosen against a stale view, notably a dismissed_player_id who is no longer at the crease) with no 'refresh first' warning. Real gap in the SCOR-24 guarantee, not silent wholesale innings corruption. Test 102's label ('an append computed against a stale state is rejected', tests/102:43-46) does overclaim as described.

---

### [medium] inningsDeliveriesProvider never selects event_kind, so the ball log renders v14 event rows as phantom balls and offers an Edit that violates a check constraint

- **id**: `ball-log-missing-event-kind-column` | **front**: Dart<->SQL contract | **category**: dart-postgres-contract | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/data/match_providers.dart:119`

**Evidence**

```
The select list is `'id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat, extra_wides, extra_no_ball_penalty, extra_byes, extra_leg_byes, is_legal, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id'` (match_providers.dart:117-124) - `event_kind` is absent, and PostgREST returns only what is selected. BallLogScreen depends on it five times: `final isEvent = d['event_kind'] != null;` (:66), `bowler: isEvent ? 'between balls' : ...` (:78), `_outcome`'s strike_swap/retirement branches (:97-103), the action sheet's `if (!isEvent)` guards on Edit/Insert (:138, :143, :149), and the incoming-batter exclusion set's `r['event_kind'] == 'retirement'` test (:172). All evaluate against a permanently-null key. Verified the column exists on the table (`information_schema.columns` for public.deliveries lists `event_kind`). Constraint proof, executed on the local DB inside a rolled-back txn: applying exactly the UPDATE edit_ball performs (20260705120100_corrections_apply_guard.sql:22-30) to a retire_batter-written 'retired_not_out' event row - which _BallEdit.fromDelivery maps to wicketType=null at ball_log_screen.dart:347 - produced `ERROR 23514: new row for relation "deliveries" violates check constraint "deliveries_retirement_shape"` (constraint defined at 20260706110000_deliveries_event_rows.sql:29-33).
```

**Failure scenario**  
Scorer taps 'Swap strike' or retires a batter, then opens the ball log. The strike-swap row renders as a ball with over label '0.3+', outcome '0' and bowler '-' (a phantom extra); the retirement row renders as a wicket ball. Tapping either offers 'Edit this ball' and 'Insert a ball after this'. Tapping Edit on a retired-hurt row and pressing Save with no changes fires edit_ball with _wicket_type=null and produces a raw 23514 check-constraint error in a snackbar. Separately, at :172 the exclusion set falls through to the else branch and adds the event row's striker_id, so the batter who did NOT retire is removed from the incoming-batter dropdown while the batter who DID retire is offered as a replacement.

**Root fix**  
Add `event_kind` (and see the sibling finding for `extra_penalty`) to the select in match_providers.dart:119-121. The screen's isEvent logic is already correct once the column arrives. Add a widget test that feeds a row with event_kind:'retirement' through BallLogScreen and asserts the Edit/Insert tiles are absent.

**Skeptic's note**  
Mechanism verified. inningsDeliveriesProvider selects exactly 'id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat, extra_wides, extra_no_ball_penalty, extra_byes, extra_leg_byes, is_legal, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id' (app/lib/src/features/scoring/data/match_providers.dart:117-124) - no event_kind, and PostgREST returns only the projected columns, so every `d['event_kind']` read in BallLogScreen (:66, :78, :97-103, :138, :143, :172) evaluates against a missing key. The column does exist on the table (added in 20260706110000_deliveries_event_rows.sql:12). Consequences confirmed: isEvent is always false, so event rows render as balls (is_legal IS selected and is false for event rows per the re-added generated expression at 20260706110000:41-43, so they get the '<over>.<ball>+' extra-ball label) and the action sheet offers 'Edit this ball' / 'Insert a ball after this' on them. The 23514 claim holds by construction: _BallEdit.fromDelivery maps wicket_type 'retired_not_out' to null (ball_log_screen.dart:347), editBall omits _wicket_type when null (match_repository.dart:226) so the SQL default null applies, and edit_ball's UPDATE sets wicket_type=null (20260705120100:27) which violates deliveries_retirement_shape (20260706110000:29-33, requires wicket_type in ('retired_out','retired_not_out','timed_out') and dismissed_player_id not null) - surfaced as a raw snackbar (:562). The :164-174 exclusion-set bug is also real: retire_batter stores striker_id = the PRE-retirement striker (20260706110400:41-44), so when the non-striker retires the set excludes the batter who stayed and offers the retired batter as an incoming replacement. Severity lowered from high to medium: nothing here corrupts data on its own - it is cosmetic phantom rows, a blocked edit that errors loudly (fail-safe, the row is unchanged), and one wrong dropdown filter that requires a scorer to actively pick the retired batter to cause harm.

---

## LOW

### [low] profiles.photo_url and teams.logo_url are free-text columns the owner can set to any URL, and InitialsAvatar loads them as NetworkImage on nearly every social surface

- **id**: `avatar-networkimage-user-controlled-beacon` | **front**: Client-side security | **category**: untrusted-input/privacy | **runs**: 1+2
- **where**: `app/lib/src/features/identity/presentation/initials_avatar.dart:26`

**Evidence**

```
app/lib/src/features/identity/presentation/initials_avatar.dart:22-27
  final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
  return CircleAvatar(
    ...
    foregroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,

The write path is a raw table UPDATE with a table-wide column grant, not a validating RPC:
app/lib/src/features/identity/data/identity_repository.dart:23-33,53,57-58
  await _client.from('profiles').update(rest).eq('id', _uid);   // `rest` is whatever the caller passes
  Future<void> setMyPhoto(String url) => updateMyProfile({'photo_url': url});
  Future<void> setTeamLogo(String teamId, String url) =>
      _client.from('teams').update({'logo_url': url}).eq('id', teamId);

backend/supabase/migrations/20260615140301_profiles_rls.sql:3
  grant select, insert, update on public.profiles to authenticated;   -- no column list; RLS is row-level only

Render sites (all with a server-supplied photoUrl): search_screen.dart:88-89, dm_inbox_screen.dart:118 and :251, team_page_screen.dart:83,:572,:707, claim_inbox_screen.dart:85, player_stats_screen.dart:86 (the login-free public /player/:id route).
```

**Failure scenario**  
An attacker signs in, then issues `PATCH /rest/v1/profiles?id=eq.<self>` with {"photo_url":"https://attacker.example/px.gif"} -- RLS permits it because the row is theirs and the grant is not column-scoped, and no CHECK exists on the column. They then appear in search results (any 2-letter query matching their display_name), in the DM inbox of anyone they message, and on team rosters. Every one of those screens fires a GET to attacker.example from the viewer's device, so the attacker gets a continuous IP/geo log of who looked at them -- including from /player/:profileId, which onboardingRedirect (app/lib/src/core/routing/app_router.dart:55-60) deliberately exposes login-free. NetworkImage also has no error handling here, so a URL that 404s leaves an empty circle with the initials fallback suppressed (line 28-29 sets child to null whenever photoUrl is non-empty).

**Root fix**  
Make the URL server-validated rather than free text: add `alter table public.profiles add constraint photo_url_own_storage check (photo_url is null or photo_url ~ '^https://<ref>\.supabase\.co/storage/v1/object/public/avatars/')` and the same for teams.logo_url, and narrow the grant to `grant update (display_name, handle, city, batting_style, photo_url) on public.profiles to authenticated`. In InitialsAvatar, reject non-https/non-project hosts before constructing NetworkImage and keep the initials child rendered as the fallback (drop the `hasPhoto ? null :` so a failed load still shows initials).

**Skeptic's note**  
Mechanism verified end to end. initials_avatar.dart:22-27 builds NetworkImage(photoUrl!) with no host/scheme check. Write path verified: identity_repository.dart:30 does `_client.from('profiles').update(rest)` with caller-supplied keys, :53 setMyPhoto, :57-58 setTeamLogo. 20260615140301_profiles_rls.sql:3 is `grant select, insert, update on public.profiles to authenticated;` with NO column list, and the update policy is row-scoped only (auth.uid() = id). `grep -rn 'photo_url|logo_url' backend/supabase/migrations | grep -iE 'check|constraint'` returns NOTHING - no CHECK exists. Server does return it to viewers: 20260706111000_search_handle.sql:6,8 includes photo_url. The login-free render site is real: stats/presentation/player_stats_screen.dart:86 passes id.photoUrl, and app_router.dart:53-61 exempts /player/ from the gate. Bonus: the comment at initials_avatar.dart:27 ('Initials remain as the fallback if the image fails to load') is FALSE - line 28-29 sets child to null whenever photoUrl is non-empty and there is no onForegroundImageError, so a failed load yields a blank teal circle.

SEVERITY CORRECTED medium -> low: this is the same beacon class as the post-image finding but narrower - the payoff is an IP/UA log of who viewed the attacker's own profile, no data access, no crash vector (avatars are small, and radius-bounded layout limits the decode-bomb angle less than the finding implies but the CircleAvatar still decodes at native resolution).

---

### [low] One GlobalKey (_shareKey) is attached to two RepaintBoundary widgets that are mounted at the same time during the 'share the full scorecard' handoff

- **id**: `duplicate-globalkey-sharekey` | **front**: Client-side security | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart:52`

**Evidence**

```
app/lib/src/features/scoring/presentation/match_viewer_screen.dart:52
  final GlobalKey _shareKey = GlobalKey();

First attachment, inside the summary sheet -- lines 135-137:
  RepaintBoundary(
    key: _shareKey,
    child: MatchShareCard(...

Second attachment, inside the full-scorecard sheet -- lines 239-241:
  RepaintBoundary(
    key: _shareKey,
    child: FullScorecardCard(...

The handoff at lines 152-158 pops the first sheet and immediately starts building the second:
  TextButton(
    onPressed: () {
      Navigator.pop(sheetCtx);
      _shareFullScorecard();
    },
    child: const Text('Share the full scorecard instead'),

and _captureAndShare resolves the boundary purely by key -- line 267-269:
  final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
```

**Failure scenario**  
Navigator.pop starts a ~200 ms exit animation; the first sheet's element stays mounted for its duration. _shareFullScorecard then awaits matchInningsListProvider/matchTeamNamesProvider/matchProvider/matchSquadProvider, which resolve from the Riverpod cache in a handful of microtasks -- far faster than 200 ms -- and calls showModalBottomSheet. The second RepaintBoundary is therefore built while the first is still in the tree, so two live elements claim the same GlobalKey. In debug and in `flutter test` this trips GlobalKey._debugVerifyGlobalKeyReservation and the MISS-9 full-scorecard sheet renders a 'Duplicate GlobalKey detected in widget tree' error box instead of the card. In release the assert is compiled out and the registry silently rebinds to the later element, so the bug is invisible in the shipped build and only bites during development -- which is exactly why the sweep-D verification would not have caught it.

**Root fix**  
Use a distinct key per sheet: add `final GlobalKey _fullCardKey = GlobalKey();` and attach it at line 240, then have _captureAndShare take the key as a parameter (`Future<void> _captureAndShare(GlobalKey key, String title)`) so each call site resolves its own boundary. Alternatively make the key sheet-local by declaring it inside the builder closure rather than on the State.

**Skeptic's note**  
Verified line-exact. match_viewer_screen.dart:52 declares one _shareKey; it is attached at :135-136 (MatchShareCard) and again at :239-240 (FullScorecardCard); the handoff at :156-158 is `Navigator.pop(sheetCtx); _shareFullScorecard();` un-awaited; _captureAndShare resolves purely by key at :267-268. The race is real: the ModalBottomSheetRoute stays in the overlay for its ~200ms exit transition, while _shareFullScorecard's awaits (matchInningsListProvider / matchTeamNamesProvider / matchProvider / matchSquadProvider) are all providers build() already watches, so they resolve from cache in microtasks and showModalBottomSheet runs while the first boundary is still mounted -> two live elements on one GlobalKey.

One correction to the stated mechanism: it is not deterministic. For a two-innings match, the per-innings loop at :217-218 reads inningsStateProvider(inn['id']) for innings the viewer never opened, which can require a network round-trip and exceed the 200ms exit, hiding the collision. The 'always fires' framing is too strong - it is cache-dependent, hitting the single-innings/live case reliably. Release behavior as described is right (assert compiled out, registry rebinds to the later element, and since the second sheet's own button captures the second boundary the shipped output is still correct). Severity low is correct.

---

### [low] A release build made without --dart-define-from-file silently ships pointing at http://127.0.0.1:54321 with the local publishable key -- no release-mode guard

- **id**: `env-release-defaults-to-localhost` | **front**: Client-side security | **category**: config | **runs**: 1+2
- **where**: `app/lib/src/core/config/env.dart:11`

**Evidence**

```
app/lib/src/core/config/env.dart:11-21
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

app/lib/main.dart:10-13 consumes them with no assertion:
  await Supabase.initialize(url: SupabaseEnv.url, publishableKey: SupabaseEnv.publishableKey);

The hosted config lives only in a gitignored file (app/.gitignore last line: `hosted_defines.json`; `git ls-files app | grep -iE 'defines'` returns nothing), and CLAUDE.md:39 confirms "Default (no flag) = local 127.0.0.1." There is no `kReleaseMode` check anywhere in env.dart or main.dart -- the only kReleaseMode/kDebugMode uses in app/lib are the sign-in shim guard and the platform checks.
```

**Failure scenario**  
Someone runs `flutter build apk --release` (the plain command, or CI without the secret file mounted) and gets a signed APK that builds and installs cleanly. On launch, Supabase.initialize points at 127.0.0.1:54321, which on Android with targetSdk 36 is additionally blocked as cleartext, so every screen shows 'Could not load...' with no indication that the build is misconfigured. The gradle release config compounds this -- app/android/app/build.gradle.kts:60-66 falls back to the DEBUG signing key when key.properties is absent -- so a fully broken, debug-signed artifact is producible by the documented one-liner and is indistinguishable from a good one until a user installs it.

**Root fix**  
Fail the build instead of failing silently. In env.dart add a compile-visible guard consumed by main.dart before Supabase.initialize: `if (kReleaseMode && (url.contains('127.0.0.1') || url.contains('localhost'))) { throw StateError('release build has no SUPABASE_URL; pass --dart-define-from-file=hosted_defines.json'); }`. Better, drop the defaultValue entirely and keep a separate `local_defines.json` (also gitignored) so BOTH local and hosted builds must name their target explicitly.

**Skeptic's note**  
Code claims all check out. app/lib/src/core/config/env.dart:10-20 has defaultValue 'http://127.0.0.1:54321' and the local publishable key; main.dart:10-13 passes them to Supabase.initialize with no assertion; there is no kReleaseMode reference in either file. app/.gitignore last line is `hosted_defines.json` and `git ls-files app | grep -i defines` returns nothing, so the hosted config is genuinely absent from the tree. The gradle sub-claim is also accurate: app/android/app/build.gradle.kts:53-64 falls back to signingConfigs.getByName("debug") when key.properties is missing. The manifest sets no usesCleartextTraffic and no network-security-config, so cleartext to 127.0.0.1 is blocked by platform default.

SEVERITY CORRECTED medium -> low: no security consequence (the local publishable key is a well-known non-secret, and pointing at 127.0.0.1 leaks nothing), and the failure is not silent to the user - every screen errors immediately on launch. This is a build-ergonomics footgun that produces an obviously dead artifact, documented in CLAUDE.md:39 ('Default (no flag) = local 127.0.0.1'), not a shipped vulnerability.

---

### [low] A user whose profile insert keeps failing is locked out of the entire app with no sign-out escape

- **id**: `create-profile-no-escape` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/core/routing/app_router.dart:70`

**Evidence**

```
`case AuthGate.needsProfile: return loc == Routes.createProfile ? null : Routes.createProfile;` (lines 70-71) forces every non-public location to the create-profile screen. CreateProfileScreen (app/lib/src/features/onboarding/presentation/create_profile_screen.dart) has no sign-out, no 'continue as guest', and no back affordance - its only terminal action is `_save`, whose failure path just sets `_error` (lines 152-162).
```

**Failure scenario**  
A user signs in with Google on a device where the profiles upsert is rejected (RLS drift after the 63 pending migrations land, a unique-handle race, or a persistent 5xx). AuthGate stays needsProfile, the redirect pins them to /onboarding/create-profile forever, and they cannot sign out to fall back to guest browsing or retry with a different account. The only remedy is clearing app data or reinstalling.

**Root fix**  
Add a 'Sign out' / 'Continue as a guest' text button to CreateProfileScreen that calls `auth.signOut()` (the anonBootstrap listener then re-establishes a guest session and the gate drops to anonymous).

**Skeptic's note**  
Verified: onboardingRedirect pins every non-public location to Routes.createProfile while gate == needsProfile (app_router.dart:70-71), and create_profile_screen.dart contains no signOut, no guest option and no context.push/go at all - _save's only failure path sets _error (lines 155-166). Trigger is more speculative than stated, though: a failed profile READ yields AuthGate.error, which holds on splash, not needsProfile (auth_gate.dart), and the save is an upsert with the 23505 handle collision already mapped to a friendly retry message, so 'locked out' needs a persistent server-side rejection of a legitimate upsert. A missing escape hatch on a forced-modal screen is a real gap - low.

---

### [low] claim_request and join_request notifications are tappable rows that do nothing

- **id**: `notifications-dead-taps` | **front**: Error handling & dead ends | **category**: dead-end | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/notifications_screen.dart:43`

**Evidence**

```
`_open` handles only post_reply / dm / match_live / invite_accepted and falls through to `default: break;` (lines 46-57). `_icon` (lines 34-41) has no case for 'join_request' either. The backend writes both types: `values (tm.profile_id, 'claim_request', NEW.membership_id, ...)` (backend/supabase/migrations/20260703150100_notification_triggers.sql:60) and `'join_request', _team_id, ... || ' asked to join ' || ...` (20260703190100_team_join_requests.sql:46-47). Every row is rendered as a `ListTile(... onTap: () => _open(context, n))` (line 102) with no visual distinction.
```

**Failure scenario**  
A captain gets 'Ravi asked to join Mumbai United'. They tap it. Nothing happens - no navigation, no snackbar, not even a ripple destination. They tap again, then give up; the join request sits unanswered in a place they never learn about (the inline _JoinRequests block on the team page). The join_request notification even carries the team id in ref_id, so the correct destination is already available and simply unused.

**Root fix**  
Add `case 'join_request': context.push(Routes.teamPage(ref_));` and `case 'claim_request': context.push(Routes.claimInbox);` to _open, add matching icons, and render non-actionable rows without an onTap.

**Skeptic's note**  
Verified: notifications_screen.dart:43-57 _open handles only post_reply/dm/match_live/invite_accepted with `default: break;`, _icon (34-41) has claim_request but no join_request case, and every row gets onTap: () => _open(...) (line 102). Both types are really written by the backend: notify_claim_request inserts 'claim_request' with ref_id = membership_id (20260703150100:58-60) and request_to_join inserts 'join_request' with ref_id = _team_id (20260703190100:45-47). Downgraded to low: the tap is a no-op, but the join request is not hidden - the team page renders _JoinRequests inline for admins (team_page_screen.dart:122, 687-728), and claim requests have their own reachable Claim inbox screen. It is a dead affordance, not a lost workflow.

---

### [low] The 'Propose a match' DM pastes a bare route path instead of a link

- **id**: `propose-match-dm-sends-bare-path` | **front**: Error handling & dead ends | **category**: correctness | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/start_match_screen.dart:99`

**Evidence**

```
```dart
await repo.sendDm(threadId,
    'I proposed a match against your team ($overs overs). '
    "Let's set it up - watch it live once we start: ${Routes.viewMatch(id)}");
```
`Routes.viewMatch(matchId) => '/watch/$matchId'` (app/lib/src/core/routing/routes.dart:62) - a router path, not a URL. Elsewhere the codebase wraps tokens in a real origin (`inviteLink`, `joinTournamentLink`).
```

**Failure scenario**  
A user proposes a match from a discover post. The poster receives the DM 'I proposed a match against your team (20 overs). Let's set it up - watch it live once we start: /watch/3f8a1c2e-...'. It is not tappable, not copy-pasteable into anything useful, and exposes an internal route shape. The bridge's whole payoff - the recipient following the live match - never happens.

**Root fix**  
Add a `matchLink(String id) => 'https://pitch.app/watch/$id'` helper next to inviteLink and use it here (and register the app link, as with the other share URLs).

**Skeptic's note**  
Verified: start_match_screen.dart:95-99 interpolates Routes.viewMatch(id), and routes.dart:62 defines it as '/watch/$matchId' - a router path, not a URL, unlike inviteLink (identity_repository.dart:170) and joinTournamentLink (tournament_repository.dart:83). Correction to the impact claim: wrapping it in https://pitch.app/... would not make it work either, since no domain is hosted and no app link is registered (the tournament share text openly says as much), so today the payoff is unreachable either way. Real but cosmetic - low.

---

### [low] The toss screen tells the scorer to 'go back and add them' but the squads screen was destroyed by pushReplacement

- **id**: `toss-go-back-impossible` | **front**: Error handling & dead ends | **category**: navigation-dead-end | **runs**: 1
- **where**: `app/lib/src/features/scoring/presentation/toss_openers_screen.dart:177`

**Evidence**

```
`setState(() => _error = 'The bowling side needs at least 2 squad members - go back and add them.');` (lines 177-179). The wizard is built entirely from pushReplacement: StartMatchScreen does `context.pushReplacement(Routes.matchSquads(id))` (start_match_screen.dart:106) and MatchSquadsScreen does `context.pushReplacement(Routes.matchToss(widget.matchId))` (match_squads_screen.dart:58). Both replace the top route, so from the toss screen the only thing beneath is the /matches branch root - the squads screen no longer exists in the stack.
```

**Failure scenario**  
A scorer resumes a fixture whose bowling side has one squad member. The toss screen refuses with 'go back and add them'. Pressing back lands on the Matches list, not the squads screen. Re-entering via the match tile goes to MatchSquadsScreen, which (see the duplicate-key finding) then fails with a 23505 on save. The instruction is literally impossible to follow.

**Root fix**  
Either keep the wizard on push (not pushReplacement) so 'back' means the previous step, or make the error actionable: `context.push(Routes.matchSquads(matchId))` behind an 'Edit squads' button on the toss screen.

**Skeptic's note**  
The navigation mechanism is real: start_match_screen.dart:106 and match_squads_screen.dart:58 both use pushReplacement, so from the toss screen the squads route no longer exists and 'back' lands on /matches. But the finding overstates it - the instruction IS followable in two steps (back -> tap the still-'setup' match tile -> MatchSquadsScreen, matches_screen.dart:162), and the reachability of the error itself is narrow: _next() already enforces >=2 picks per side (match_squads_screen.dart:32-37), so a bowling side with <2 squad rows only arises after a partially-failed save. Severity corrected medium->low.

---

### [low] Popping the scoring console while record_ball is in flight throws StateError from ref.invalidate, then _toast dereferences a defunct BuildContext

- **id**: `console-pop-midflight-ref-throw` | **front**: Flutter state & lifecycle | **category**: lifecycle | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/scoring_console_screen.dart:38`

**Evidence**

```
`_afterBall` L37-39:
```dart
ref.invalidate(inningsStateProvider(inningsId));
final fresh = await ref.read(inningsStateProvider(inningsId).future);
```
No `mounted` guard before either call; flutter_riverpod 3.3.2 `consumer.dart:568-569` `invalidate()` calls `_assertNotDisposed()`, which throws a StateError (L469-477) once the element is unmounted. The throw is caught by `_record`'s handler L100-107, which falls through to `_toast(raw)`; `_toast` L172-175 does `ScaffoldMessenger.maybeOf(context)` on the same defunct context. `AdaptiveScaffold` (core/platform/adaptive_scaffold.dart) always renders an implied back button and there is no `PopScope` anywhere in `app/lib` (grep: none), so popping mid-flight is a one-tap action; `_busy` disables only the run pad, not the nav bar.
```

**Failure scenario**  
On a slow/hosted connection, tap `4` on the pad and immediately tap the nav-bar back arrow (or swipe back on iOS). The delivery IS written server-side, then `_afterBall`'s `ref.invalidate` throws `Bad state: Using "ref" when a widget is about to or has been unmounted is unsafe`. In debug/profile, `ScaffoldMessenger.maybeOf` on the defunct element trips `_debugCheckStateIsActiveForAncestorLookup` → "Looking up a deactivated widget's ancestor is unsafe" thrown from an async callback (red screen / uncaught error). In release the snackbar renders showing the raw Bad-state text to the scorer right after a ball that actually succeeded.

**Root fix**  
Guard every post-await `ref` use: `if (!mounted) return;` immediately after `await _repo.recordBall(...)` and at the top of `_afterBall`, and make `_toast` a no-op when `!mounted`.

**Skeptic's note**  
The throw is real; every claimed user-visible consequence is wrong. Confirmed: scoring_console_screen.dart:37-39 `ref.invalidate(...)` then `await ref.read(...future)` with no `mounted` guard, reached after `await _repo.recordBall(...)` at :73-91; consumer.dart:565-569 `invalidate()` calls `_assertNotDisposed()` which throws StateError once the element is unmounted; the catch at :100-107 falls through to `_toast(raw)`; `_toast` :172-175 calls `ScaffoldMessenger.maybeOf(context)` unguarded; grep confirms zero `PopScope`/`WillPopScope` in app/lib and AdaptiveScaffold (core/platform/adaptive_scaffold.dart) uses a plain AppBar / CupertinoNavigationBar with an implied back button on the pushed `:matchId/score` route (app_router.dart:248). CORRECTIONS: (1) 'red screen' is wrong — the debug assert lives in framework.dart:5082 `_debugCheckStateIsActiveForAncestorLookup()` inside `dependOnInheritedWidgetOfExactType`; it throws out of an un-awaited async callback and is reported, not rendered as an ErrorWidget. (2) 'In release the snackbar renders showing the raw Bad-state text' is FALSE and backwards: in release the assert is stripped and framework.dart:5083 reads `_inheritedElements?[T]`, which `Element.deactivate()` already set to null — so `maybeOf` returns null and `_toast` is a silent no-op. Net effect in a shipped build: nothing at all happens; the ball was recorded and the screen is already gone. Debug/profile gets a console error. Low.

---

### [low] DmInboxScreen.dispose() calls ref.read → StateError; DM channels leak and super.dispose() is skipped

- **id**: `dm-inbox-ref-in-dispose` | **front**: Flutter state & lifecycle | **category**: lifecycle | **runs**: 1+2
- **where**: `app/lib/src/features/messages/presentation/dm_inbox_screen.dart:75`

**Evidence**

```
L72-81:
```dart
void dispose() {
  if (_subs.isNotEmpty) {
    final c = ref.read(supabaseClientProvider);
    for (final ch in _subs.values) { c.removeChannel(ch); }
  }
  super.dispose();
}
```
Same proof as the DM-thread case: flutter_riverpod 3.3.2 `consumer.dart:469-477` `_assertNotDisposed()` throws when `!context.mounted`, and Flutter's `Element.unmount()` nulls `_widget` before `state.dispose()` runs. `/discover/messages` is a pushed sub-route (`core/routing/app_router.dart:198-199`), so this dispose path runs on every back navigation.
```

**Failure scenario**  
Discover → mail icon → Messages → pull-to-refresh (this makes `ref.listen` at L86 fire and populate `_subs`) → tap back. `ref.read` throws, `removeChannel` never executes for any thread, `super.dispose()` is skipped (debug: "dispose failed to call super.dispose" assert). Every visited thread's `dm:<id>` channel stays subscribed and its callback keeps calling `ref.invalidate(dmInboxProvider)` (L65) through a ref that now throws.

**Root fix**  
Capture the `SupabaseClient` in a State field during `initState`/`_syncSubscriptions` and use that field in `dispose()`.

**Skeptic's note**  
Confirmed, with the same riverpod/Flutter proof as dm-thread-ref-in-dispose (consumer.dart:371/469-477/553-557; framework.dart:4851-4866 then :6028). dm_inbox_screen.dart:72-81 verified verbatim — note the author DID defend the same call in `_syncSubscriptions` with a try/catch at :45-50 but left `dispose()` bare, which makes it a genuine oversight rather than a misread. Reachability is real but narrower than for the thread screen and depends on this file's OTHER bug: `_subs` is only populated by `_syncSubscriptions`, which is only reached through `ref.listen` (:86-89), so on the common warm-provider path `_subs` stays empty and `if (_subs.isNotEmpty)` short-circuits before the throw. Pull-to-refresh (:103 `ref.invalidate(dmInboxProvider)`) or `_compose` (:175) does make the listener fire and populate `_subs`, so the described scenario holds. CORRECTIONS: no crash in any mode — framework.dart:3435-3439 `finalizeTree()` catches and reports; and the 'dispose failed to call super.dispose' assert (framework.dart:6030-6041) never actually runs, because the exception from `state.dispose()` propagates before it. Residual harm is a leaked `dm:<id>` channel per subscribed thread plus uncaught StateErrors from the leaked `ref.invalidate` callback at :65. Low.

---

### [low] Two TextEditingControllers created inside async dialog helpers are never disposed

- **id**: `leaked-text-controllers` | **front**: Flutter state & lifecycle | **category**: resource-leak | **runs**: 1+2
- **where**: `app/lib/src/features/tournaments/presentation/manage_tournament_screen.dart:224`

**Evidence**

```
`manage_tournament_screen.dart:224` `final venueCtrl = TextEditingController(text: f.venue ?? '');` — used at L290 after the sheet closes, never `.dispose()`d on any path. Same pattern at `app/lib/src/features/profile/presentation/settings_screen.dart:44` `final ctrl = TextEditingController();` inside `_changeEmail`, never disposed.
```

**Failure scenario**  
Open the organizer's Manage tournament screen and tap the calendar icon on a fixture, then dismiss the sheet; repeat for each fixture (a 2-group tournament has 6+ group fixtures). Each open leaks a `TextEditingController` and its `ChangeNotifier` listeners for the process lifetime; Flutter's leak-tracking harness (and `flutter test --track-widget-leaks`) flags each one. Same for every "Change email" dialog open in Settings.

**Root fix**  
Create the controller before the `await`, and dispose it in a `finally` after the sheet/dialog future completes (or hoist it into a small StatefulWidget sheet that owns its own dispose).

**Skeptic's note**  
Confirmed, both sites, exactly as cited. manage_tournament_screen.dart:224 `final venueCtrl = TextEditingController(text: f.venue ?? '');` inside `_editSchedule`, still read at :287 (`venueCtrl.text.trim()`) after the sheet returns and never disposed on any path; it is reachable from the per-fixture calendar button at :204. settings_screen.dart:44 `final ctrl = TextEditingController();` inside `_changeEmail`, read at :59, never disposed. These are the only two such sites. Genuine but minor: a few hundred bytes plus a ChangeNotifier per dialog open, no functional impact; the value is mostly in keeping leak-tracking test harnesses clean. Low is correct.

---

### [low] Switching from the summary share sheet to the full-scorecard sheet mounts two RepaintBoundaries with the same GlobalKey

- **id**: `viewer-duplicate-globalkey-share` | **front**: Flutter state & lifecycle | **category**: crash | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart:240`

**Evidence**

```
One key, two simultaneously-mountable subtrees: L52 `final GlobalKey _shareKey = GlobalKey();`, used at L135-137 (`RepaintBoundary(key: _shareKey, child: MatchShareCard(...))`) inside `_share`'s sheet and at L239-241 (`RepaintBoundary(key: _shareKey, child: FullScorecardCard(...))`) inside `_shareFullScorecard`'s sheet. The handoff is L155-161: `onPressed: () { Navigator.pop(sheetCtx); _shareFullScorecard(); }`. `_shareFullScorecard` L181-200 only awaits `matchInningsListProvider`, `matchTeamNamesProvider`, `matchProvider`, `matchSquadProvider` and `inningsStateProvider(latest)` — all of which `build()` (L282-285) and `_body` already watch, so on a single-innings live match every `.future` is already complete and resolves in microtasks, well inside the bottom sheet's 200 ms exit animation.
```

**Failure scenario**  
Open `/watch/<matchId>` on a live (one-innings) match with the Live tab showing, tap the share icon, then tap "Share the full scorecard instead". The first sheet's route is still in the overlay animating out when the second sheet builds. Flutter's `Element._retakeInactiveElement` finds `_shareKey`'s element still parented and, in debug/profile, throws "Multiple widgets used the same GlobalKey" → red error widget instead of the scorecard sheet. In release it silently steals the boundary out of the outgoing sheet (content pops out mid-animation).

**Root fix**  
Give each sheet its own key (`_summaryShareKey` / `_fullShareKey`), or pass the key down as a local `GlobalKey` created per sheet and hand it to `_captureAndShare`.

**Skeptic's note**  
Reparenting is real; the stated failure mode is wrong. Confirmed: match_viewer_screen.dart:52 one `_shareKey`, used at :135-137 (MatchShareCard) and :239-241 (FullScorecardCard), with the handoff at :155-161 `Navigator.pop(sheetCtx); _shareFullScorecard();`. Timing confirmed: :282-285 `build` watches matchProvider/matchTeamNamesProvider/matchInningsListProvider/matchSquadProvider and :480/:743/:901 watch `inningsStateProvider`, and `_share` itself already awaited `inningsStateProvider(latest)` at :122 — so every `.future` in `_shareFullScorecard` (:182-200) is already complete and resolves in microtasks, well inside the 200 ms bottom-sheet exit. framework.dart:4481-4530 `_retakeInactiveElement` confirms the steal path (`Widget.canUpdate` is true for two RepaintBoundary widgets sharing the key → `parent.forgetChild` + `parent.deactivateChild`). CORRECTIONS: 'red error widget instead of the scorecard sheet' is FALSE — the duplicate-key error is raised inside an `assert(() {...}())` in framework.dart:3341-3432 `finalizeTree()`, whose catch at :3435-3439 exists specifically 'to avoid activating the ErrorWidget'; it is a reported FlutterError only, and it is stripped entirely in release. The only real user-visible effect, in every mode, is the outgoing sheet's summary card vanishing during its 200 ms exit animation; the new sheet and `_captureAndShare` both work because `_shareKey.currentContext` now resolves to the new boundary. Cosmetic glitch plus a debug-only console error / `tester.takeException` in widget tests. Low.

---

### [low] The record_ball optimistic-concurrency fence keys on max(seq), which edit_ball and delete_ball never change - the exact stale-vs-correction race it was built for still passes

- **id**: `last-seq-fence-blind-to-corrections` | **front**: Scoring fold correctness | **category**: concurrency | **runs**: 1
- **where**: `backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:44`

**Evidence**

```
The fence is purely a max-seq comparison:
  line 42-46: `select coalesce(max(seq),0) into _cur_last from public.deliveries where innings_id = _innings_id; if _expected_last_seq is not null and _cur_last <> _expected_last_seq then raise exception 'the innings changed on another device - refresh before recording' ...`
and the fold's token is likewise just the last row's seq (20260706110100:43 `_last_seq := d.seq;`).
But edit_ball never touches `seq` (20260705120100:15-33 - it updates runs/extras/wicket columns only), and delete_ball deletes a row without renumbering (20260623130000_restamp_strike.sql:80 `delete from public.deliveries where id = _delivery_id;` - the only follow-up is `restamp_innings_strike`). So editing ball 12 of 42, or deleting any non-final ball, leaves max(seq) = 42 and the fence passes. Only insert_ball (which shifts seqs up) and undo of the tail move max(seq). The migration header claims the opposite: "a stale device's append is rejected instead of silently interleaving with another scorer's corrections" (lines 7-9).
```

**Failure scenario**  
Two authorised scorers on one match (owner + transferred scorer, both pass is_match_scorer). Device A folds the innings at last_seq = 42 and shows batter X on strike. Device B opens the ball log and edits ball 12 from a single to a dot, or deletes ball 12 - downstream strike rotation flips, so the striker is now Y, but max(seq) is still 42. Device A taps "4" with _expected_last_seq = 42; the fence passes, record_ball re-folds and credits the four to Y. The scorer who tapped the button saw X on screen and gets no warning, which is precisely the interleaving the fence was added to stop.

**Root fix**  
Make the version token reflect content, not row count - e.g. return a hash/max of `updated_at` alongside max(seq) from compute_innings_state (`md5(string_agg(id::text || seq || updated_at, ',' order by seq))` or `max(greatest(created_at, updated_at))` plus the row count), and have record_ball compare that. Cheaper alternative: bump a per-innings `revision` column in edit_ball / insert_ball / delete_ball / undo_last_ball / retire_batter / swap_strike and fence on that instead of max(seq).

**Skeptic's note**  
The mechanical claim checks out. The fence is a bare max(seq) compare (20260706110600:42-46) against the fold's token (_last_seq := d.seq, 20260706110100:43). edit_ball (20260705120100:15-33, and the original at 20260623130000) updates value columns + updated_at and never seq; delete_ball (20260623130000:~80) deletes a single row with no renumbering, so deleting any non-tail ball leaves max(seq) unchanged. Only insert_ball (which shifts seq up) and a tail delete/undo move the token, so an edit or a mid-log delete is invisible to the fence, contradicting the migration header at lines 6-9. I also confirmed the console has no realtime subscription to close the window from the other side (onBroadcast/RealtimeChannelConfig appear only in match_viewer_screen.dart:75-91; scoring_console_screen.dart has none), so device A genuinely will not learn of B's edit. Severity dropped to low because the concrete corruption in the failure scenario does not hold up: record_ball re-folds from scratch after the fence (line 48) and stamps the striker the CURRENT log implies, so if B's correction was right, crediting Y is the right answer, not a corruption - the appended ball is always self-consistent with the log. What is actually lost is the staleness warning (and the duplicate-entry protection when B deleted a ball A is about to re-enter). Gap in a best-effort guarantee, not a data-integrity defect.

---

### [low] record_ball accepts deliveries into an already-completed innings (retire_batter and swap_strike both guard, record_ball does not), and compute_innings_cards counts those orphans

- **id**: `record-ball-no-innings-over-guard` | **front**: Scoring fold correctness | **category**: correctness | **runs**: 1
- **where**: `backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:48`

**Evidence**

```
record_ball v3 folds the state at line 48 (`_state := public.compute_innings_state(_innings_id);`) and then reads striker/non-striker/free-hit from it, but never checks `_state->>'innings_status'`. Both sibling event RPCs do check: retire_batter (20260706110400:20-22) and swap_strike (20260706110500:16-18) each raise `'the innings is over'`. compute_innings_state merely files the extra rows into `orphaned_deliveries` (20260706110100:44) and excludes them from every total; compute_innings_cards has no orphan concept at all and, when its all_out differs (see the squad_size finding) or when the innings ended on overs/target, folds them straight into the batting and bowling cards.
PROVEN on the live DB (3-player squad -> state all_out = 2):
  AFTER ALL OUT: state status=completed wickets=2 runs=0
  record_ball(_i,_bw,4) SUCCEEDS -> state runs=0, orphaned_deliveries=["21e9c020-..."]
  CARDS batting-runs-sum=4, CARDS bowler runs_conceded=4  vs  STATE bowler runs_conceded=0
```

**Failure scenario**  
A scorer (or a second authorised scorer, or the correction path) appends a ball after the innings has ended - e.g. insert_ball adds a missed earlier wicket, which moves the all-out point backwards and turns every later real delivery into an orphan. compute_innings_state discards those runs/balls; compute_innings_cards counts them. The match viewer scorecard (built from state) shows 40/7 while the persisted POTM, the player's career batting average and the tournament leaderboard (all built from cards) include the discarded runs. The two never reconcile, and nothing surfaces the mismatch to the user.

**Root fix**  
Add the same guard the event RPCs use to record_ball, immediately after line 48: `if _state->>'innings_status' <> 'in_progress' then raise exception 'the innings is over' using errcode = 'P0001'; end if;`. Separately, make compute_innings_cards return the orphan list too (or share the `_ended` decision with the state fold) so the two folds can never disagree about which rows are in the innings.

**Skeptic's note**  
The literal claim is true: 20260706110600_record_ball_cap_stale.sql folds the state at line 48 and reads striker/non-striker/free_hit at 49-51 but never tests _state->>'innings_status', while retire_batter (20260706110400:19-21) and swap_strike (20260706110500) both raise 'the innings is over'. So record_ball will insert a delivery into a completed innings and return success. BUT the stated harm is largely wrong and mostly a restatement of finding 1: compute_innings_cards DOES have an end-of-innings gate - 20260706110200:30 'if _ended then continue;' - so post-end deliveries are skipped by cards too. Cards and state compute _ended from identical conditions (target / all_out / max_legal) and differ in exactly one input: squad_size. The claim 'compute_innings_cards has no orphan concept at all and folds them straight into the cards' is therefore false at squad_size 11; the cited proof (3-player squad, state all_out 2 vs cards all_out 10) is the squad_size divergence again, not an independent defect. What actually remains: an append into a finished innings silently produces a row the fold discards. The app already mitigates both ends - scoring_console_screen.dart:389/458 replaces the whole run pad with the end panel once innings_status == 'completed', and lines 437-448 render an explicit 'N balls recorded after the innings ended - remove or fix them in the ball log' banner off state.orphaned_deliveries. Reduces to a missing server-side guard / API asymmetry: low.

---

### [low] retire_batter permits a retired-hurt with no incoming batter on the last pair, and the fold then leaves the retired batter at the crease scoring runs

- **id**: `retire-hurt-no-incoming-keeps-batting` | **front**: Scoring fold correctness | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110400_rpc_retire_batter.sql:27`

**Evidence**

```
retire_batter line 27: `if _incoming_batter_id is null and coalesce((_state->>'wickets_remaining')::int, 99) >= 2 then raise ... end if;` - so a NULL incoming is accepted whenever wickets_remaining < 2, for retired_out AND retired_not_out alike.
The fold's retirement branch only replaces a batter inside `if d.incoming_batter_id is not null` (20260706110100:60-66) and only ends the innings via `if _wickets >= _all_out` (line 67). For `retired_not_out` `_wickets` is not incremented (line 52), so with a NULL incoming nothing happens at all: no replacement, no end. Same in cards (20260706110200:44-48) and restamp (20260706110300:35-39).
PROVEN on the live DB (3-player squad, 1 wicket down -> wickets_remaining = 1):
  retire_batter(_i, striker, false, null) SUCCEEDS
  AFTER retire-hurt(no incoming): status=in_progress wickets=1 striker=a5100fb8(the retired batter) non=63ee5f25
  next ball for 4 is credited to him: card = {"runs":4,"balls":1,"fours":1,"how_out":"retired_not_out","dismissed":false}
This is exactly the corruption the v14 header claims to have fixed ("v13 never applied a retired_not_out replacement at all - the retiring batter kept batting", 20260706110100:5-6).
```

**Failure scenario**  
Last pair at the crease (wickets_remaining = 1), one batter is injured. Any API client - or the app after any future change to the retire sheet, which today only disables the button client-side (app/lib/src/features/scoring/presentation/scoring_console_screen.dart:951-953) - calls retire_batter(out=false, incoming=null). The RPC returns success, the innings stays in_progress, and the batter who just walked off keeps facing deliveries and accumulating runs and balls on a card that is simultaneously labelled "retired not out".

**Root fix**  
In retire_batter, make the NULL-incoming exemption conditional on the retirement actually ending the innings: allow it only when `_out` is true and wickets_remaining = 1 (i.e. this retirement is the final wicket); otherwise always require an incoming batter. Belt-and-braces in the fold: in the retirement branch of all three folds, if `d.incoming_batter_id is null` and the retiring batter is at the crease and the innings did not end, treat the innings as ended rather than silently leaving the retired batter on strike.

**Skeptic's note**  
The code hole is real and I could not refute it. 20260706110400_rpc_retire_batter.sql:27 exempts a NULL incoming whenever wickets_remaining < 2 regardless of _out, but a retired_not_out increments no wicket (fold 20260706110100:52), applies no replacement (fold:60-66 is inside `if d.incoming_batter_id is not null`), and cannot trigger the end check (fold:67), so the event is a no-op that leaves the retired batter on strike - identical in cards (110200:44-48) and restamp (110300:35-39). The guard is only sound for the cases it was copied from (record_ball 20260706110600:66-70, where the last wicket ends the innings) and for _out=true. Also note line 30's `_incoming_batter_id in (_striker,_non_striker)` evaluates to NULL and never fires on this path. Severity corrected high -> low on reachability: the app can never send it. app/lib/src/features/scoring/presentation/scoring_console_screen.dart:949-955 disables the Retire button whenever incoming == null, and the incoming list excludes the crease pair and everyone already gone (:880-893), so on the last pair the sheet simply cannot be submitted. The only caller that reaches the bug is a hand-written RPC call by the match's own scorer (is_match_scorer is a single matches.scorer_id, 20260616200401:8-11), i.e. self-inflicted, and it is repairable by deleting the event row. This is a guard-logic fix, not a live-data emergency.

---

### [low] The retirement branch closes the partnership unconditionally but only resets the running counters when an incoming batter is named, double-counting the stand

- **id**: `retirement-partnership-not-reset` | **front**: Scoring fold correctness | **category**: correctness | **runs**: 1
- **where**: `backend/supabase/migrations/20260706110100_fold_v14_events.sql:57`

**Evidence**

```
20260706110100:57-66 -
  `_partnerships := _partnerships || jsonb_build_object('wicket_number',_wickets,'batter_a',_ps_a,'batter_b',_ps_b,'runs',_runs-_ps_start_runs, ...);`   -- always appended
  `if d.incoming_batter_id is not null then ... _ps_a_runs := 0; _ps_b_runs := 0; _ps_start_runs := _runs; _ps_start_legal := _legal; end if;`   -- reset only inside the guard
With a NULL incoming (reachable per the retire_batter finding) the stand is emitted as closed while `_ps_start_runs`/`_ps_start_legal` still point at the old start, so `current_partnership` (line 208-209) re-reports the same runs and balls. Additionally, `'wicket_number', _wickets` is stamped even for retired_not_out, where `_wickets` was not incremented, so the emitted stand carries the PREVIOUS wicket's number.
OBSERVED on the live DB (proof run with a retired_not_out mid-innings): `partnerships` contained two entries both with `"wicket_number": 1` - one closed by the actual first wicket, one closed by the retirement.
```

**Failure scenario**  
A batter retires hurt at 30 for the stand with no incoming batter named. The fold emits a closed partnership of 30 runs, then `current_partnership` keeps counting from the same start, so a stand that produced 45 runs in total is reported as 30 + 45 = 75 across the two rows. Separately, in every innings containing a retired-not-out, two partnership entries share the same `wicket_number`, so any consumer that keys or labels stands by wicket number ("1st wicket partnership") renders two conflicting rows for the same wicket.

**Root fix**  
Move the `_ps_a/_ps_b/_ps_a_runs/_ps_b_runs/_ps_start_runs/_ps_start_legal` reset out of the `if d.incoming_batter_id is not null` guard so the running partnership is always restarted whenever a stand is emitted, and give retired_not_out stands a distinguishing key (e.g. emit `'wicket_number', null` plus `'ended_by','retirement'`) instead of reusing the previous wicket's number.

**Skeptic's note**  
Both code claims are literally true at 20260706110100_fold_v14_events.sql:57-66: the partnership object is appended unconditionally, while _ps_a/_ps_b/_ps_a_runs/_ps_b_runs/_ps_start_runs/_ps_start_legal are reset only inside 'if d.incoming_batter_id is not null', and the emitted object stamps 'wicket_number', _wickets even for retired_not_out where _wickets was not incremented. Severity cut to low for two independent reasons. (a) The double-count half is entirely chained to the previous finding - the only way to reach a retirement with a NULL incoming is the retire_batter exemption, which the app cannot produce; with an incoming batter (every app-generated retirement) the reset does run and current_partnership is correct. (b) The duplicate-wicket_number half has no consumer: grep across app/lib finds zero readers of state['partnerships'] - match_viewer_screen.dart:531 reads only 'current_partnership', and no SQL consumer (career stats, POTM, leaderboard, standings) touches the partnerships array either. So today it is a latent data-shape wart in an unread field, not a rendered defect. 'any consumer that keys stands by wicket number renders two conflicting rows' is hypothetical.

---

### [low] edit_ball and insert_ball are EXECUTE-granted to PUBLIC, exposing the correction writers on the anon PostgREST surface

- **id**: `edit-insert-ball-public-execute` | **front**: Migration safety | **category**: security-hardening | **runs**: 2
- **where**: `backend/supabase/migrations/20260616202001_rpc_corrections.sql:88`

**Evidence**

```
Lines 84-87 do `revoke all on function public.undo_last_ball(uuid) from public;` and `revoke all on function public.delete_ball(uuid) from public;` but lines 88-89 grant edit_ball/insert_ball to authenticated without ever revoking the default PUBLIC EXECUTE. 20260705120100_corrections_apply_guard.sql recreates both with `create or replace`, which preserves the ACL. Confirmed on the live DB: `proacl` for edit_ball and insert_ball is `{=X/postgres,postgres=X/postgres,authenticated=X/postgres}` — the leading `=X` is the PUBLIC grant; every other RPC in the schema is `{postgres=X,...}`.
```

**Failure scenario**  
An unauthenticated (anon-key) caller can invoke POST /rest/v1/rpc/edit_ball and /rpc/insert_ball. Today the SECURITY DEFINER bodies stop at `if not public.is_match_scorer(_m) then raise exception 'not authorized'` because auth.uid() is null, so there is no data leak or write. The defect is that these two writers are the only ones on the public surface with no revoke: any future edit that adds a lookup, side effect, or error path ahead of the guard becomes an unauthenticated write against deliveries, and the pattern diverges from every sibling function.

**Root fix**  
Add `revoke all on function public.edit_ball(uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text) from public;` and the matching revoke for `public.insert_ball(uuid,bigint,uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid)` in a new migration, then re-grant to authenticated.

**Skeptic's note**  
ACL claim verified independently. 20260616202001_rpc_corrections.sql:84-89 revokes PUBLIC on undo_last_ball and delete_ball but only grants edit_ball/insert_ball to authenticated, and grep over all 145 migrations finds no revoke for either; 20260705120100_corrections_apply_guard.sql:3/35 uses `create or replace`, preserving the ACL. Introspected on the live DB: edit_ball and insert_ball are `{=X/postgres,postgres=X/postgres,authenticated=X/postgres}` while delete_ball, undo_last_ball, record_ball and retire_batter are all `{postgres=X/postgres,authenticated=X/postgres}` — so the leading PUBLIC grant is real and these two are the only outliers. Exploitability is nil today, as the finding itself concedes: edit_ball's first statement is a bare SELECT then `if not public.is_match_scorer(_m) then raise` (20260705120100:17-20) and insert_ball checks before any write (:44-46), and is_match_scorer returns false for a null auth.uid(). The only observable anon effect is a 'delivery not found' vs 'not authorized' oracle on a guessed uuid. Correctly filed as low-severity hardening/consistency.

---

### [low] retire_batter on the last pair with no incoming batter is accepted and leaves the retired-hurt batter at the crease still scoring

- **id**: `retire-hurt-last-pair-noop` | **front**: Migration safety | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110400_rpc_retire_batter.sql:27`

**Evidence**

```
`if _incoming_batter_id is null and coalesce((_state->>'wickets_remaining')::int, 99) >= 2 then raise exception 'an incoming batter is required (this is not the last wicket)'`. The guard is copied from the wicket path but never consults `_out`. For `_out = false` the row is written with wicket_type='retired_not_out' (line 34), and the fold's retirement branch (20260706110100_fold_v14_events.sql:52-66) does NOT increment `_wickets` for retired_not_out and only swaps the batter `if d.incoming_batter_id is not null` — so with a null incoming batter nothing happens at all.
```

**Failure scenario**  
Verified on the live DB (rolled back): 11-a-side innings, 9 wickets down (wickets_remaining = 1). `select public.retire_batter(innings, <striker>, false, null)` succeeds and returns an event id. compute_innings_state afterwards still reports striker_id = the batter who just retired hurt and innings_status='in_progress'. Adding one more delivery gives that batter runs=6, balls=1 in compute_innings_cards while the same card line reads how_out='retired_not_out', dismissed=false. The scorecard says the player retired hurt and simultaneously credits them runs scored after retiring — the exact SCOR-16 corruption the migration says it root-fixes.

**Root fix**  
Make the incoming-batter requirement depend on the retirement kind: require `_incoming_batter_id` unconditionally when `_out` is false (a retire-hurt never ends the innings), and only allow the null-incoming shortcut when `_out` is true AND `wickets_remaining <= 1`. Mirror that in the fold: for a retirement event with a null incoming batter and wicket_type='retired_not_out', either reject at write time or treat it as ending the innings.

**Skeptic's note**  
The RPC-level defect is real: 20260706110400_rpc_retire_batter.sql:27-29 gates the null-incoming shortcut only on `wickets_remaining >= 2` and never consults `_out`, so with 9 of 10 wickets down `retire_batter(innings, striker, false, null)` is accepted; line 34 writes wicket_type='retired_not_out'; the fold's retirement branch (20260706110100:44-67) neither increments _wickets for retired_not_out nor swaps the pair when incoming_batter_id is null, and cards (20260706110200:36-49) stamps how_out='retired_not_out'/dismissed=false on a batter who keeps facing balls. Line 30's `_incoming_batter_id in (_striker,_non_striker)` is NULL, so it does not catch it either. BUT the caller-side guard the finding omits does exist and closes the only app path: the console's retirement sheet disables submission until an incoming batter is picked — scoring_console_screen.dart:948-951, `onPressed: incoming == null ? null : () => Navigator.pop(context, true)` — and match_repository.dart:147-158 is the sole caller. So the corruption is reachable only by a hand-crafted PostgREST call from an already-authorised scorer against their own match, where they can already write arbitrary values. Severity corrected high -> low: guard asymmetry worth fixing, no reachable user-facing failure.

---

### [low] join_tournament_with_token reads the invite without FOR UPDATE, so a single-use tournament token can be redeemed twice concurrently

- **id**: `tournament-token-no-row-lock` | **front**: Migration safety | **category**: concurrency | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260702160300_rpc_join_tournament_with_token.sql:20`

**Evidence**

```
`select tournament_id into _tid from public.tournament_invites where invite_token = _invite_token and status = 'pending';` — no `for update`. The status flip to 'accepted' happens only at line 35-37, after the tournament_teams insert. The sibling primitive this file says it mirrors, accept_invite, explicitly locks: `... from public.team_invites where invite_token = _invite_token for update;` with the comment 'Lock the row: concurrent redeemers serialize here (TEAM-3 TOCTOU fix)' (20260703170000_team_invites_multiuse.sql:27-32).
```

**Failure scenario**  
Two team admins tap the same shared tournament join link at the same moment. Both transactions read status='pending', both pass the checks, both insert their own team into tournament_teams, and both write status='accepted' with their own redeemed_by/redeemed_team_id. A token the organizer minted for one team admits two, redeemed_by/redeemed_team_id record only the last writer, and the bracket's team count is one higher than the organizer expects when they generate fixtures.

**Root fix**  
Add `for update` to the invite select (line 20-21) so concurrent redeemers serialize, matching accept_invite; the second transaction then re-reads status='accepted' and raises 'invite not found or already used'.

**Skeptic's note**  
Confirmed as read. 20260702160300_rpc_join_tournament_with_token.sql:20-21 selects the pending invite with no `for update`, and the status flip is at :35-37 after the tournament_teams insert at :31-33; the sibling accept_invite does lock (20260703170000_team_invites_multiuse.sql:27-32, `... where invite_token = _invite_token for update;` with the TEAM-3 TOCTOU comment). Two concurrent redeemers naming different teams therefore both pass the pending check and both insert (the ON CONFLICT at :33 is on (tournament_id, team_id), so it does not collapse distinct teams), and the last writer's redeemed_by/redeemed_team_id wins. Severity low is right and arguably generous: the consent boundary that matters, is_team_admin(_team_id) at :16-18, still holds for both winners, the file's own header already accepts that a leaked token can add a team the organizer can see and remove, and the concrete harm is an extra team in the bracket plus lost provenance on one row.

---

### [low] Anon can enumerate every object (and owner UUID) in the public avatars and post-images buckets, and account deletion never removes those objects

- **id**: `storage-objects-anon-enumeration` | **front**: Data exposure / PII | **category**: pii-exposure | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260625140000_avatars_bucket.sql:21`

**Evidence**

```
```sql
create policy "avatars_public_read"
  on storage.objects for select to public
  using (bucket_id = 'avatars');
```
Identical policy at backend/supabase/migrations/20260617130100_post_images_bucket.sql:21 for post-images. A `for select` policy on storage.objects authorises the Storage LIST endpoint, not just object download — public bucket plus this policy means unauthenticated listing, not merely unguessable-URL access.

Verified against the running local DB (BEGIN/ROLLBACK) with the role set to anon (i.e. only the publishable anon key, no session at all):
```
            what            |                     name                      
----------------------------+-----------------------------------------------
 anon can enumerate avatars | 11111111-1111-1111-1111-111111111111/face.jpg
```
Upload paths are `<uid>/<timestamp>.<ext>` (app/lib/src/features/discover/data/discover_repository.dart:28 and app/lib/src/features/identity/data/identity_repository.dart:46-51), so the listing is itself a directory of every user's auth UUID. Compounding it, backend/supabase/migrations/20260703160000_rpc_delete_my_account.sql:26 nulls profiles.photo_url but never deletes the storage object.
```

**Failure scenario**  
Anyone with the app's publishable anon key (extractable from the shipped APK) posts {"prefix":"","limit":1000} to /storage/v1/object/list/avatars, receives the full list of <uid>/ folders, then lists each folder and downloads every profile photo in the system — a complete face-and-UUID dataset harvested without an account. Separately, a user who deletes their account has their photo removed from the UI while the JPEG stays publicly listable and downloadable at its original URL forever.

**Root fix**  
Scope the read policies to individual objects rather than the whole bucket so LIST returns nothing useful: replace the blanket `using (bucket_id = 'avatars')` with a policy that also requires the object to be referenced by a live row (e.g. `and exists (select 1 from public.profiles p where p.photo_url like '%' || storage.objects.name)`), or keep the buckets public for GET-by-URL but drop the storage.objects SELECT policy for the anon/public role so the list endpoint is denied. Separately, have delete_my_account remove the caller's storage objects: `delete from storage.objects where bucket_id in ('avatars','post-images') and (storage.foldername(name))[1] = _me::text;`.

**Skeptic's note**  
Mechanism confirmed, impact overstated. The cited lines are exact: 20260625140000_avatars_bucket.sql:21-23 and 20260617130100_post_images_bucket.sql:21-23 are both `for select to public using (bucket_id = ...)`. Verified anon SELECT is authorised at the DB layer (inserted one storage.objects row inside BEGIN/ROLLBACK, `set local role anon`, the row was visible), and the Storage LIST endpoint answers the anon key with 200 `[]` rather than 401/403 for both buckets — so with objects present, anon listing does return them. Upload paths are `<uid>/<micros>.<ext>` (discover_repository.dart:26-29, identity_repository.dart:46-51), so the listing is a UUID directory. The second half is a genuine and separate defect: 20260703160000_rpc_delete_my_account.sql:26 nulls profiles.photo_url and nothing ever deletes the storage object, so an erased user's face stays publicly fetchable at its original URL.

Severity lowered from medium to low. Both buckets are declared `public = true` at bucket_creation (avatars_bucket.sql:8, post_images_bucket.sql:7) — world-readable-by-URL is the deliberate design for CDN loading, so the only incremental exposure is enumerability. And that increment is small: profiles is readable by any authenticated caller (20260615140301_profiles_rls.sql:3,6-9) and carries both id and photo_url, so anyone who spends one unconfirmed-email signup (config.toml [auth.email] enable_signup=true, enable_confirmations=false — verified: instant authenticated JWT) already has the full UUID+avatar-URL list. The anon-vs-authenticated distinction the finding leans on is worth roughly one HTTP request.

---

### [low] update_match_schedule mutates venue/scheduled_at but the matches broadcast trigger only fires on status or result, so open viewers never see the change

- **id**: `rt-schedule-change-no-broadcast` | **front**: Realtime & concurrency | **category**: realtime | **runs**: 1
- **where**: `backend/supabase/migrations/20260702140000_broadcast_innings_matches.sql:41`

**Evidence**

```
20260702140000_broadcast_innings_matches.sql:39-45:
```sql
-- Only push when something a watcher cares about changed (status / result),
-- not on every toss/venue edit during setup.
create trigger matches_broadcast
  after update on public.matches
  for each row
  when (old.status is distinct from new.status or old.result is distinct from new.result)
  execute function public.broadcast_match_change();
```
20260706111700_rpc_update_match_schedule.sql:20-26 explicitly permits the edit on a LIVE match (it only rejects 'complete'/'abandoned'):
```sql
if _st in ('complete','abandoned') then raise exception 'this match already finished' ...
update public.matches set scheduled_at = _scheduled_at, venue = nullif(trim(_venue), '') where id = _match_id;
```
and the viewer renders that column from the cached matches row (match_viewer_screen.dart:1050, 1075): `if (venue != null && venue.isNotEmpty) tile('Venue', venue)`.
```

**Failure scenario**  
A tournament organiser corrects the ground on a live fixture (venue 'Ground A' -> 'Ground B') via update_match_schedule. No broadcast is emitted, so every open /watch/:id keeps rendering 'Ground A' on the Info tab indefinitely - there is no other refresh path on that screen besides _refold.

**Root fix**  
Extend the trigger's WHEN clause to include the columns the viewer renders: `old.venue is distinct from new.venue or old.scheduled_at is distinct from new.scheduled_at`. Setup-time churn is already excluded by the receive policy, since match_is_publicly_viewable rejects 'setup' topics (20260702140100_broadcast_receive_gate.sql:7-11).

**Skeptic's note**  
Verified. The trigger WHEN clause is exactly as quoted (20260702140000_broadcast_innings_matches.sql:41-45, status/result only) and grep shows matches_broadcast is created in that one migration and never replaced. update_match_schedule (20260706111700_rpc_update_match_schedule.sql:20-26) only rejects 'complete'/'abandoned', so venue/scheduled_at can be changed on a LIVE match - which the trigger's own justification comment ('not on every toss/venue edit during setup') does not cover. The viewer renders venue from the cached matches row (match_viewer_screen.dart:1050 and :1075) and has no pull-to-refresh: the only other invalidation is the error-state retry at :315-320. So an open /watch/:id keeps the stale ground. Severity low is correct - cosmetic staleness on the least-viewed tab, and the same trigger already correctly pushes the things that matter.

---

### [low] The viewer's re-fold invalidates only three providers; inningsWagonProvider is never invalidated, so the live wagon wheel is frozen at its first read

- **id**: `rt-viewer-wagon-never-refolded` | **front**: Realtime & concurrency | **category**: realtime | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart:94`

**Evidence**

```
match_viewer_screen.dart:94-101:
```dart
void _refold() {
  if (!mounted) return;
  ref.invalidate(matchProvider(widget.matchId));
  ref.invalidate(matchInningsListProvider(widget.matchId));
  for (final id in _knownInnings) { ref.invalidate(inningsStateProvider(id)); }
}
```
But the Charts tab also watches a fourth provider (match_viewer_screen.dart:901-902):
```dart
final state = ref.watch(inningsStateProvider(innings['id'] as String));
final wagon = ref.watch(inningsWagonProvider(innings['id'] as String));
```
inningsWagonProvider is an independent family FutureProvider that queries deliveries directly (match_providers.dart:129-133). All four tabs live in an IndexedStack (match_viewer_screen.dart:378-393), so every child - including the Charts tab - is built on the first frame and its providers resolve immediately.
```

**Failure scenario**  
A viewer opens /watch/:id at over 5. inningsWagonProvider resolves once with the shots recorded so far. For the rest of the innings every delivery INSERT broadcast fires _refold, so the score, scorecard and charts-from-state update, but inningsWagonProvider is never invalidated: the wagon wheel keeps showing the over-5 snapshot for the whole session with no indication it is stale.

**Root fix**  
Add `ref.invalidate(inningsWagonProvider(id))` to the _refold loop over _knownInnings, or move the invalidation set into a single helper that enumerates every per-innings provider the viewer reads.

**Skeptic's note**  
Verified exactly as stated. match_viewer_screen.dart:94-101 _refold invalidates matchProvider, matchInningsListProvider and inningsStateProvider only; _ChartsTab also watches inningsWagonProvider (match_viewer_screen.dart:902), which is an independent non-autoDispose FutureProvider.family querying deliveries directly (match_providers.dart:129-138) and is invalidated nowhere in lib/ (grep: two hits only - the definition and that watch). All four tabs are IndexedStack children (match_viewer_screen.dart:378-393), so the Charts tab is built on the first frame and the wagon future resolves once and is cached for the life of the screen. Cosmetic staleness of one chart, so low is right.

---

### [low] The optimistic-concurrency token is max(seq) alone, so edit_ball and delete_ball change the innings without changing the token - a stale device's wicket is accepted and dismisses the wrong batter

- **id**: `scor-fence-token-blind-to-edits` | **front**: Realtime & concurrency | **category**: concurrency | **runs**: 2
- **where**: `backend/supabase/migrations/20260706110600_record_ball_cap_stale.sql:43`

**Evidence**

```
The fence compares only max(seq) (20260706110600_record_ball_cap_stale.sql:42-46):
```sql
-- SCOR-24: reject an append computed against a state another device replaced
select coalesce(max(seq),0) into _cur_last from public.deliveries where innings_id = _innings_id;
if _expected_last_seq is not null and _cur_last <> _expected_last_seq then
  raise exception 'the innings changed on another device - refresh before recording' using errcode = 'P0001';
end if;
```
But edit_ball (20260705120100_corrections_apply_guard.sql:24-32) only UPDATEs a row and delete_ball (20260616202001_rpc_corrections.sql:18-28 / 20260623130000_restamp_strike.sql:71-82) deletes by id with no renumbering - neither changes max(seq). Meanwhile the client sends server-authoritative-looking values derived from its cached fold: scoring_console_screen.dart:1080-1081
```dart
final strikerId = s['striker_id'] as String?;
final nonStrikerId = s['non_striker_id'] as String?;
```
and scoring_console_screen.dart:1235-1249
```dart
final dismissedId = _needsWhoOut(type) && whoOut == 'non_striker' ? nonStrikerId : strikerId;
await _record(..., dismissedId: dismissedId, ..., lastSeq: (s['last_seq'] as num?)?.toInt());
```
record_ball never validates _dismissed_player_id against the freshly folded striker/non-striker (it only re-derives _striker/_non_striker for stamping, 20260706110600:48-51).
```

**Failure scenario**  
Scorer account signed in on phone and tablet. Innings has 40 deliveries. On the tablet the scorer opens the ball log and edits delivery seq=12 from '1 run' to '2 runs' (edit_ball -> restamp_innings_strike flips the strike rotation for every subsequent ball). max(seq) is still 40. On the phone, whose console still shows the pre-edit fold, the scorer records a caught dismissal: the phone sends _dismissed_player_id = the pre-edit striker, and _expected_last_seq = 40, which matches. The fence passes, and the fold dismisses the batter who is now at the non-striker's end - the wrong player is out, and the batting card is corrupted from that ball onward. The same holds for delete_ball on any non-tail delivery.

**Root fix**  
Make the token cover mutations that do not move max(seq): compute it as e.g. `max(seq) || ':' || count(*) || ':' || max(updated_at)` (or add a monotonic `revision` bigint on innings that every mutating RPC bumps) and have compute_innings_state return that same composite as last_seq. Additionally, have record_ball reject a _dismissed_player_id that is neither the freshly folded striker nor non-striker instead of trusting the client.

**Skeptic's note**  
The token claim is true (20260706110600_record_ball_cap_stale.sql:42-46 compares only max(seq); edit_ball UPDATEs in place and delete_ball deletes by id with no renumbering, so neither moves max(seq); the console has NO realtime subscription - grep for channel/onBroadcast/realtime in scoring_console_screen.dart returns nothing - so its fold really is stale until an invalidate). BUT the finding's headline failure is REFUTED: fold v14 line 139 is `if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing;` - for caught/bowled/lbw/stumped/hit_wicket the fold IGNORES the client-supplied _dismissed_player_id and derives the out batter from its own freshly folded strike, so the quoted 'scorer records a caught dismissal -> wrong player is out' cannot happen, and the same re-derivation makes a stale device's ordinary runs/extras append correctly. What survives is much narrower: only run_out / obstructing (and retirement events) consume the client value, so the constructible defect is 'stale device records a run-out after another device edited or deleted a non-tail delivery -> the wrong batter is credited with the dismissal in fall_of_wickets and is replaced at the wrong end'. That needs same-account dual devices plus an out-of-band edit/delete, hence low, not high.

---

### [low] transfer_scorer takes a match-scoped advisory lock while every innings mutation takes an innings-scoped lock, so its documented serialisation against a concurrent record_ball does nothing

- **id**: `transfer-scorer-wrong-lock-key` | **front**: Realtime & concurrency | **category**: concurrency | **runs**: 1
- **where**: `backend/supabase/migrations/20260617121000_transfer_scorer.sql:17`

**Evidence**

```
20260617121000_transfer_scorer.sql:16-19:
```sql
-- serialise against a concurrent record_ball on the same match
perform pg_advisory_xact_lock(hashtextextended(_match_id::text, 0));
select * into _m from public.matches where id = _match_id for update;
```
Every mutating scoring path locks on the INNINGS id instead: record_ball (20260706110600_record_ball_cap_stale.sql:40), undo_last_ball / delete_ball / edit_ball / insert_ball (20260616202001_rpc_corrections.sql:13, 26, 48, 72), retire_batter (20260706110400_rpc_retire_batter.sql:16), swap_strike (20260706110500_rpc_swap_strike.sql:13) - all `hashtextextended(_innings_id::text, 0)`. Different key space, so the two locks never contend. The `for update` on matches also does not help: record_ball only does a plain SELECT of matches (20260706110600:33-36) and is_match_scorer is a STABLE plain SELECT (20260616200401_is_match_scorer.sql:8-11), neither of which takes a row lock.
```

**Failure scenario**  
A captain transfers scoring from the old scorer's phone to a new device while the old scorer has a tap in flight. transfer_scorer acquires lock(match_id) and updates matches.scorer_id. Concurrently record_ball acquires lock(innings_id) - uncontended - reads matches under its own READ COMMITTED snapshot taken before the transfer committed, passes is_match_scorer, and inserts the delivery. Both transactions commit. A ball is recorded by an account that is no longer the scorer, after the transfer, which is precisely what the in-code comment claims is prevented.

**Root fix**  
Use one lock key for the whole match: have transfer_scorer take pg_advisory_xact_lock on the innings ids of the match as well (or, better, switch every scoring RPC to lock on hashtextextended(match_id) and drop the innings-scoped key), and re-check is_match_scorer after the lock is held rather than before it.

**Skeptic's note**  
The factual claim is correct and I confirmed it: 20260617121000_transfer_scorer.sql:17 locks hashtextextended(_match_id) while every scoring mutation locks hashtextextended(_innings_id) - record_ball 20260706110600_record_ball_cap_stale.sql:40, undo/delete/edit/insert 20260616202001_rpc_corrections.sql:13/26/48/72, retire_batter 20260706110400:16, swap_strike 20260706110500:13. Different key space, zero contention, so the in-code comment at :16 is false. is_match_scorer (20260616200401_is_match_scorer.sql:1-12) is a STABLE plain SELECT and record_ball reads matches without FOR UPDATE (20260706110600:33-36), so the FOR UPDATE at transfer_scorer:19 does not help either. Two corrections though. (1) Severity: medium is inflated. The concrete outcome is one delivery committed by the outgoing scorer inside a sub-second window during a handover - the ball is legitimate cricket data recorded by someone who was authorised moments earlier; no corruption, no privilege escalation, no scorecard divergence. Low. (2) The proposed fix is partly wrong: record_ball performs its is_match_scorer check at line 38, BEFORE taking the advisory lock at line 40, so unifying the lock key alone would not close the window - the authorisation decision is already made on the pre-transfer snapshot. Only re-checking is_match_scorer after the lock is held (which the finding mentions second) actually fixes it.

---

### [low] iOS release has no working sign-in: the Apple button is rendered but the Sign in with Apple entitlement was never added

- **id**: `ios-no-working-signin-missing-apple-entitlement` | **front**: Build & release config | **category**: platform-configuration | **runs**: 1+2
- **where**: `app/ios/Runner.xcodeproj/project.pbxproj:363`

**Evidence**

```
`grep -n "CODE_SIGN_ENTITLEMENTS\|com.apple.developer\|SystemCapabilities" app/ios/Runner.xcodeproj/project.pbxproj` returns nothing, and `find app/ios -name '*.entitlements'` returns nothing — there is no `Runner.entitlements`. Yet app/lib/src/features/auth/presentation/sign_in_screen.dart:109-119 renders the button unconditionally on iOS:
```dart
if (defaultTargetPlatform == TargetPlatform.iOS) ...[
  OutlinedButton(onPressed: ... => ref.read(oAuthServiceProvider).appleSignIn(), child: const Text('Continue with Apple')),
],
```
which reaches `SignInWithApple.getAppleIDCredential(...)` at app/lib/src/features/auth/data/oauth_sign_in.dart:92. The project's own oauth-provisioning.md:74 lists the missing step verbatim: 'in Xcode, Runner target > Signing & Capabilities > + Sign in with Apple (writes Runner.entitlements with com.apple.developer.applesignin)'. Meanwhile the Google path is gated off on iOS: env.dart:33-40 `googleConfigured` requires `googleIosClientId.isNotEmpty` on iOS, and `GOOGLE_IOS_CLIENT_ID` has no default and is not in hosted_defines (2026-07-05-final-done-audit.md:74 confirms), so oauth_sign_in.dart:35-40 throws 'Google sign-in is not configured yet.' And the email/password shim is behind `if (kDebugMode)` (sign_in_screen.dart:59).
```

**Failure scenario**  
Build an iOS release/TestFlight IPA. Tap 'Continue with Apple': ASAuthorizationController rejects the request because the app has no `com.apple.developer.applesignin` entitlement, `getAppleIDCredential` throws `SignInWithAppleAuthorizationException(AuthorizationErrorCode.unknown, 1000)`, and the screen shows 'Sign-in failed: ...'. Tap 'Continue with Google': 'Google sign-in is not configured yet.' The email fields are compiled out. Result: an iOS user can never leave the anonymous session — every account-scoped feature (creating teams, scoring, invites) is unreachable. The 2026-07-05 audit marks this 'explicitly_deferred', but deferral only covers Google; the Apple button is still shipped and still throws.

**Root fix**  
Either finish the capability or stop shipping the dead button. To finish: add `ios/Runner/Runner.entitlements` containing `com.apple.developer.applesignin = [Default]`, set `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` in both Debug and Release build configurations of the Runner target in project.pbxproj, and enable the Sign in with Apple capability on the App ID in the Apple Developer portal. To defer honestly: gate the Apple button on a build-time define the way Google is gated (`SupabaseEnv.appleConfigured`) so it is absent rather than broken, and stop hiding the only remaining sign-in behind `kDebugMode` on iOS.

**Skeptic's note**  
Every factual claim checks out. `grep -n 'CODE_SIGN_ENTITLEMENTS|com.apple.developer|SystemCapabilities' app/ios/Runner.xcodeproj/project.pbxproj` returns nothing, and `find app/ios -name '*.entitlements'` returns nothing — there is no Runner.entitlements and no build setting referencing one. app/lib/src/features/auth/presentation/sign_in_screen.dart:107-119 does render the Apple button unconditionally when `defaultTargetPlatform == TargetPlatform.iOS`, reaching `SignInWithApple.getAppleIDCredential` at app/lib/src/features/auth/data/oauth_sign_in.dart:92. The Google path on iOS is indeed dead: env.dart:33-40 `googleConfigured` requires `googleIosClientId.isNotEmpty` on iOS, `GOOGLE_IOS_CLIENT_ID` has no `defaultValue` (env.dart:29-30), and oauth-provisioning.md:19 lists the iOS Google client as 'STILL NEEDED'. The email/password shim is `kDebugMode`-gated (sign_in_screen.dart:59). So an iOS release build genuinely has zero working sign-in. SEVERITY CORRECTED high -> low: no iOS release can currently be produced at all. oauth-provisioning.md:55 lists 'Apple Developer Program ($99/yr)' as still-needed, :56-57 list the App ID capability and the Supabase Apple provider as still-needed, and task #64 (wire iOS Google client) is still pending. iOS today is a simulator-only target where the debug shim works. This is a dead button on a platform with no distribution path, not a live user-facing outage — and oauth-provisioning.md:15 records 'Google sign-in only for v1; Apple deferred', so the deferral is real; the defect is narrowly that the button was not gated the way Google's was.

---

### [low] Every SharePlus call omits sharePositionOrigin while the app ships as an iPad-supported universal binary, so all sharing fails on iPad

- **id**: `ipad-share-missing-position-origin` | **front**: Build & release config | **category**: platform-configuration | **runs**: 1+2
- **where**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart:275`

**Evidence**

```
All four call sites pass `ShareParams` with no `sharePositionOrigin`:
- match_viewer_screen.dart:275-277 `SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: '$title - live on Pitch'))`
- teams/presentation/team_page_screen.dart:483-488
- tournaments/presentation/tournament_page_screen.dart:34-37
- tournaments/presentation/manage_tournament_screen.dart:351-357
The app is a universal binary: `TARGETED_DEVICE_FAMILY = "1,2"` at app/ios/Runner.xcodeproj/project.pbxproj:367, 493 and 546, and app/ios/Runner/Info.plist:68-74 declares `UISupportedInterfaceOrientations~ipad`. share_plus 13.1.0 hard-fails this case — FPPSharePlusPlugin.m:424-443:
```objc
BOOL isIpad = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
if (isIpad && hasPopoverPresentationController && (!isCoordinateSpaceOfSourceView || CGRectIsEmpty(origin))) {
  ... result([FlutterError errorWithCode:@"error" message:sharePositionIssue details:nil]); return;
}
```
and share_plus README.md:263-268 states it 'may cause a crash or leave the UI unresponsive'.
```

**Failure scenario**  
On any iPad (including App Review, which tests iPad builds for universal apps), tapping Share on a match, team, or tournament calls into the plugin with an empty origin rect; the plugin returns a FlutterError and no share sheet ever appears. In match_viewer_screen.dart:150 and :249 the call is `onPressed: () => _captureAndShare(...)` — un-awaited and outside any try/catch (the try/catch at :112 and :177 wraps only the sheet construction, not `_captureAndShare`, which is defined at :266 with no error handling) — so the PlatformException surfaces as an unhandled async error and the button is simply dead. tournament_page_screen.dart:34 has the same bare `onPressed`. Two sites (team_page_screen.dart:478, manage_tournament_screen.dart:345) do catch it and show a raw plugin-internal string in a SnackBar.

**Root fix**  
Pass the origin at every call site. Capture it from the tapped widget's render box, e.g. `final box = context.findRenderObject() as RenderBox?;` then `ShareParams(..., sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size)`. Wrap `_captureAndShare` in try/catch and surface a user-facing message. Alternatively, if iPad is out of scope for v1, set `TARGETED_DEVICE_FAMILY = "1"` in all three build configurations so the app is iPhone-only and never runs in the iPad idiom.

**Skeptic's note**  
Fully verified. `grep -rn 'SharePlus|sharePositionOrigin|ShareParams' app/lib` returns exactly the four cited construction sites and ZERO occurrences of `sharePositionOrigin`: match_viewer_screen.dart:275-277, teams/presentation/team_page_screen.dart:483-488, tournaments/presentation/tournament_page_screen.dart:34-37, tournaments/presentation/manage_tournament_screen.dart:351-357. `TARGETED_DEVICE_FAMILY = "1,2"` confirmed at app/ios/Runner.xcodeproj/project.pbxproj:367, 493, 546, and `UISupportedInterfaceOrientations~ipad` at app/ios/Runner/Info.plist:68-74. The plugin guard is real — I read the resolved dependency (pubspec.lock:1026-1033 pins share_plus 13.1.0) at ~/.pub-cache/hosted/pub.dev/share_plus-13.1.0/ios/share_plus/Sources/share_plus/FPPSharePlusPlugin.m:424-443, which returns a FlutterError and `return`s before presenting whenever `isIpad && hasPopoverPresentationController && (!isCoordinateSpaceOfSourceView || CGRectIsEmpty(origin))`. The error-handling sub-claim is also right: match_viewer_screen.dart:266-278 `_captureAndShare` has no try/catch, the try/catch at :113 and :180 closes at :167/:258 around the sheet construction only, and both invocations (:150, :249) are `onPressed: () => _captureAndShare(...)` — the Future is discarded, so a PlatformException becomes an unhandled async error and the button reads as dead. tournament_page_screen.dart:34 is likewise a bare un-awaited onPressed. SEVERITY CORRECTED medium -> low: the guard is `isIpad`-gated, so this cannot fire on iPhone or on Android — and Android is the only platform with a distribution path today (task #63 shipped an APK; iOS needs a Developer Program membership that oauth-provisioning.md:55 lists as still-needed). All four sites work correctly on the shipped platform. Real, but currently unreachable.

---

### [low] NSPhotoLibraryAddUsageDescription is missing, so 'Save Image' from the app's own share sheet crashes iOS

- **id**: `missing-nsphotolibraryadd-usage-description` | **front**: Build & release config | **category**: platform-configuration | **runs**: 1+2
- **where**: `app/ios/Runner/Info.plist:5`

**Evidence**

```
app/ios/Runner/Info.plist:5-10 declares only the read/camera/location keys:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Pitch needs photo access to attach photos to your posts.</string>
<key>NSCameraUsageDescription</key>...
<key>NSLocationWhenInUseUsageDescription</key>...
```
There is no `NSPhotoLibraryAddUsageDescription`. The app nevertheless presents a `UIActivityViewController` carrying an image file: app/lib/src/features/scoring/presentation/match_viewer_screen.dart:266-278 renders a RepaintBoundary to PNG and shares it as `XFile(file.path)`, and the share sheet's built-in `UIActivityTypeSaveToCameraRoll` runs inside the Runner process.
```

**Failure scenario**  
A user taps Share on a live match or the full scorecard (match_viewer_screen.dart:150 / :249), the iOS share sheet opens with the PNG, and they tap 'Save Image'. The save is performed by the host app, so iOS checks Runner's Info.plist for NSPhotoLibraryAddUsageDescription, finds nothing, and terminates the process with an uncatchable NSException ('This app has crashed because it attempted to access privacy-sensitive data without a usage description'). Since sharing the scorecard image is the headline feature of sweep unit D, 'Save Image' is the most likely tap in that sheet. Not a Dart exception — a hard crash no try/catch can intercept.

**Root fix**  
Add to app/ios/Runner/Info.plist: `<key>NSPhotoLibraryAddUsageDescription</key><string>Pitch saves scorecard images you share to your photo library.</string>`. If saving is genuinely unwanted, instead pass `ShareParams(..., excludedCupertinoActivities: [CupertinoActivityType.saveToCameraRoll])` so the activity never appears.

**Skeptic's note**  
The file-level claim is verified: app/ios/Runner/Info.plist:5-10 declares NSPhotoLibraryUsageDescription, NSCameraUsageDescription and NSLocationWhenInUseUsageDescription, and I read all 76 lines — there is no NSPhotoLibraryAddUsageDescription. The app does present a UIActivityViewController carrying a PNG from its own process: match_viewer_screen.dart:266-278 renders the RepaintBoundary via `boundary.toImage(pixelRatio: 3)`, writes it to `Directory.systemTemp`, and shares it as `XFile(file.path)`. The plugin also does not exclude the save activity (no `excludedCupertinoActivities` anywhere in app/lib). The add-only-authorization crash for a host app missing that key is well-established Apple behavior, so the mechanism is sound. SEVERITY CORRECTED medium -> low, for the same reason as the iPad finding: this is iOS-only, and iOS has no distribution path today (oauth-provisioning.md:55 lists the Apple Developer Program as still-needed; the shipped artifact per task #63 is an Android APK). I also cannot verify the exact iOS-version behavior from this repo — modern iOS routes some share-sheet activities out of process — so the crash is plausible rather than something I confirmed executing. Cheap to fix, low urgency.

---

### [low] No URL scheme or intent-filter is registered on either platform, so password reset, email change, and the Android Apple redirect are dead ends

- **id**: `no-deep-link-scheme-registered` | **front**: Build & release config | **category**: platform-configuration | **runs**: 1+2
- **where**: `app/ios/Runner/Info.plist:5`

**Evidence**

```
app/ios/Runner/Info.plist (all 76 lines) contains no `CFBundleURLTypes` key at all. app/android/app/src/main/AndroidManifest.xml:25-28 has exactly one intent-filter — MAIN/LAUNCHER — and no `<data android:scheme="...">` anywhere in the file. Yet the app mints links that need one:
- app/lib/src/features/auth/data/oauth_sign_in.dart:80-84 `signInWithOAuth(OAuthProvider.apple, redirectTo: 'io.supabase.pitch://login-callback', authScreenLaunchMode: LaunchMode.externalApplication)` — the scheme `io.supabase.pitch` is registered nowhere.
- app/lib/src/features/profile/presentation/settings_screen.dart:34 `await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(email);` with no `redirectTo`, followed at :35-36 by a SnackBar promising 'Password reset link sent to $email'.
- settings_screen.dart:64-68 `updateUser(UserAttributes(email: email))`, which triggers a confirmation email.
The recovery link therefore targets the project Site URL, which backend/supabase/config.toml:159 sets to `http://127.0.0.1:3000`, with `additional_redirect_urls = ["https://127.0.0.1:3000"]` at :163 — no app scheme in either.
```

**Failure scenario**  
A user with an email account taps Settings > reset password. The app confidently reports 'Password reset link sent'. The email arrives; tapping the link opens a browser at 127.0.0.1:3000 (connection refused on a phone), and the recovery token is consumed by that navigation. There is no path back into the app to set a new password, so the account is permanently unrecoverable through the UI. Same for the email-change confirmation at :64. The Android Apple branch at oauth_sign_in.dart:80 would strand the user in an external browser identically — it survives only because sign_in_screen.dart:109 gates the Apple button to iOS.

**Root fix**  
Register the redirect on both platforms and use it. Add `CFBundleURLTypes` to Info.plist with `CFBundleURLSchemes = [io.supabase.pitch]`, and an `<intent-filter>` in AndroidManifest.xml on MainActivity with `<action VIEW/><category DEFAULT/><category BROWSABLE/><data android:scheme="io.supabase.pitch" android:host="login-callback"/>`. Then pass `redirectTo: 'io.supabase.pitch://login-callback'` to `resetPasswordForEmail` and `updateUser`, and add that URL to `additional_redirect_urls` in config.toml and to the hosted project's Auth redirect allow-list. Until that is wired, remove or disable the reset-password and change-email rows rather than promising a link that cannot be used.

**Skeptic's note**  
The core structural claim is verified: `grep -rn 'CFBundleURLTypes|android:scheme' app/ios app/android` returns NOTHING, app/ios/Runner/Info.plist (76 lines) has no CFBundleURLTypes, and app/android/app/src/main/AndroidManifest.xml:25-28 has only the MAIN/LAUNCHER intent-filter. `io.supabase.pitch` appears exactly once in the whole repo — app/lib/src/features/auth/data/oauth_sign_in.dart:82 — registered nowhere. settings_screen.dart:34 calls `resetPasswordForEmail(email)` with no `redirectTo` and :35-36 promises 'Password reset link sent'; :66-71 calls `updateUser(UserAttributes(email: email))` and promises 'open it to finish'. Both rows are rendered unconditionally (settings_screen.dart:133-142) — no gating. TWO CORRECTIONS. (a) The config.toml citation is wrong for the deployment that matters: backend/supabase/config.toml:159/:163 configure the LOCAL stack only; `supabase db push` pushes migrations, not config.toml, so the hosted project's Site URL comes from its dashboard. The conclusion survives (the hosted default is also localhost:3000 and no app scheme is in any allow-list) but the cited mechanism is not the operative one. (b) The 'account permanently unrecoverable' framing is refuted: in a release build the only working sign-in is Google (email/password is `kDebugMode`-gated at sign_in_screen.dart:59), and a Google-federated user has no password to reset — so the reset row is a promise about a credential that does not exist, not a lockout. The genuinely reachable defect is the change-email confirmation at :64-71: a real Android release user can trigger it, gets told to open the link, and the link cannot return to the app. SEVERITY CORRECTED medium -> low: one secondary settings action dead-ends with a misleading snackbar; no data loss, no lockout, no blocked primary flow.

---

### [low] Android launcher label is still the scaffold string 'pitch_app' and the version has never left 1.0.0+1 despite a distributed release APK

- **id**: `scaffold-app-label-and-frozen-version` | **front**: Build & release config | **category**: release-configuration | **runs**: 1+2
- **where**: `app/android/app/src/main/AndroidManifest.xml:5`

**Evidence**

```
app/android/app/src/main/AndroidManifest.xml:5 `android:label="pitch_app"`, against app/ios/Runner/Info.plist:15-16 `<key>CFBundleDisplayName</key><string>Pitch App</string>` and the in-app copy at app/lib/src/features/profile/presentation/settings_screen.dart:168 'Pitch v1.0.0 - find, play and score cricket'. Three different names for one product. app/pubspec.yaml:20 is still `version: 1.0.0+1`, and app/android/app/build.gradle.kts:38-39 derives `versionCode = flutter.versionCode` / `versionName = flutter.versionName` from it — so every build ever produced, including the release APK from completed task #63 that a friend is running against the hosted DB, is versionCode 1 / versionName 1.0.0. app/android/app/build.gradle.kts:32 also still carries the generated `// TODO: Specify your own unique Application ID`.
```

**Failure scenario**  
On Android the home-screen icon reads 'pitch_app', an unmistakable unshipped-scaffold tell that App/Play review flags and that users see before they see anything else. On versioning: because versionCode never changes, there is no way to tell the friend's installed build from a newer one — bug reports cannot be pinned to a build, and the moment a second artifact is uploaded to Play it is rejected ('Version code 1 has already been used'). The frozen version also means an OTA-style reinstall over the existing APK is indistinguishable from a no-op.

**Root fix**  
Set `android:label="Pitch"` in AndroidManifest.xml and `CFBundleDisplayName` to `Pitch` in Info.plist so both platforms match the product name. Bump `version:` in pubspec.yaml on every distributed build (or drive it from CI via `--build-name`/`--build-number`), and delete the stale applicationId TODO comment now that `dev.pitch.pitch_app` is the registered OAuth package name.

**Skeptic's note**  
Every fact verified. app/android/app/src/main/AndroidManifest.xml:5 is `android:label="pitch_app"`; app/ios/Runner/Info.plist:15-16 is CFBundleDisplayName 'Pitch App' (and :23-24 CFBundleName 'pitch_app', a FOURTH spelling the finding missed); settings_screen.dart:167 reads 'Pitch v1.0.0 - find, play and score cricket'. app/pubspec.yaml:19 is `version: 1.0.0+1` (line 19, not 20 as cited), and app/android/app/build.gradle.kts:38-39 derives versionCode/versionName from it, so every artifact ever built — including the release APK from task #63 now running against the hosted DB — is versionCode 1 / versionName 1.0.0. The stale scaffold TODO is at build.gradle.kts:32, immediately above the real `applicationId = "dev.pitch.pitch_app"` at :33. Severity 'low' is already correct and I am confirming it as such, with one deflation: the 'Play rejects Version code 1 has already been used' consequence is hypothetical (nothing has been uploaded to Play, and task #62 store-ready packaging is still pending), so the real present-day harm is the two verifiable ones — a home-screen icon reading 'pitch_app', and the inability to distinguish the friend's installed build from any later one when triaging a bug report.

---

### [low] 11 widget tests never run under iOS, including the onboarding redirect and the whole-app shell smoke test, contradicting the both-platforms claim

- **id**: `eleven-widget-tests-never-run-on-ios` | **front**: Stale Flutter tests | **category**: test-coverage | **runs**: 2
- **where**: `app/test/app_smoke_test.dart:27`

**Evidence**

```
Files under app/test containing `testWidgets` but never setting `debugDefaultTargetPlatformOverride`, i.e. always running as the flutter_test default (android):
- app/test/app_smoke_test.dart - 2 tests (whole `PitchApp` boot + Matches-tab branch switch)
- app/test/identity_test.dart - 3 tests (signed-in ProfileScreen, MyTeamsScreen, CreateTeamScreen form validation)
- app/test/onboarding_redirect_test.dart - 3 tests (no-profile -> create-profile, anonymous -> shell, profile-read-error -> splash retry: the mandatory first-run path for every new user)
- app/test/match_share_card_test.dart - 1 test (MISS-9 MatchShareCard)
- app/test/wagon_field_test.dart - 2 tests

app_smoke_test.dart is also structurally locked to Android:
```
// app/test/app_smoke_test.dart:27
    expect(find.byType(NavigationBar), findsOneWidget); // Android default
```
`NavigationBar` is Material-only; app/test/platform_adaptive_test.dart:27-28 proves iOS renders `CupertinoTabBar` and `findsNothing` for `NavigationBar`, so this test cannot simply be looped over platforms.

This contradicts the project's own verification protocol in CLAUDE.md ("Widget tests pass, run on BOTH platforms ... Android is the test default and masks iOS-only bugs"). Also: the suite is 183 tests, not the claimed 159 - `flutter test` on the unmodified repo prints "00:08 +183: All tests passed!".
```

**Failure scenario**  
An iOS-only regression in the onboarding gate (CreateProfileScreen renders through `AdaptiveScaffold`'s `CupertinoPageScaffold` branch, adaptive_scaffold.dart:26-43, where there is no FAB slot and the nav bar lays out differently) blocks first-run sign-up on iPhone while `flutter test` reports 183 green. Same exposure for CreateTeamScreen's inline validation message and MyTeamsScreen.

**Root fix**  
Wrap these five files' `testWidgets` in the same `for (final platform in [TargetPlatform.iOS, TargetPlatform.android])` loop the rest of the suite uses, and in app_smoke_test assert the platform-appropriate tab bar (`NavigationBar` on android, `CupertinoTabBar` on iOS) instead of hardcoding the Material one.

**Skeptic's note**  
Counts verified exactly: app_smoke_test 2, identity_test 3, onboarding_redirect_test 3, match_share_card_test 1, wagon_field_test 2 = 11 testWidgets, and grep -c debugDefaultTargetPlatformOverride is 0 in all five files, so they all run as the flutter_test android default. app/test/app_smoke_test.dart:27 does hardcode expect(find.byType(NavigationBar), findsOneWidget) with the comment '// Android default', and the 183-test count is right (my phone-viewport run printed +178 -5). CORRECTION: the iOS exposure is narrower than stated — app/test/platform_adaptive_test.dart already boots the whole PitchApp under TargetPlatform.iOS and asserts CupertinoTabBar, and app/test/adaptive_scaffold_test.dart exercises AdaptiveScaffold's Cupertino branch on iOS, so the shell itself is covered on iOS and app_smoke_test's gap is largely duplicative. The genuinely uncovered iOS paths are onboarding_redirect (the first-run gate), identity (ProfileScreen/MyTeams/CreateTeam), wagon_field and match_share_card. Pure coverage gap with partial mitigation: low, not medium.

---

### [low] hosted_smoke_test claims to prove the anon login-free path but asserts on the authenticated client, and it pollutes the hosted production DB every run

- **id**: `hosted-smoke-asserts-claim-it-never-exercises` | **front**: Stale Flutter tests | **category**: correctness | **runs**: 2
- **where**: `app/integration_test/hosted_smoke_test.dart:33`

**Evidence**

```
```
// app/integration_test/hosted_smoke_test.dart:22-34
final c = Supabase.instance.client;
await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
...
final tid = await c.rpc('create_tournament', params: {
  '_name': 'Hosted Smoke', '_overs': 20, '_group_count': 2, '_qualifiers_per_group': 2,
}) as String;
final overview = await c.rpc('tournament_overview', params: {'_tournament_id': tid}) as Map;
expect((overview['tournament'] as Map)['name'], 'Hosted Smoke');

// anon-readable too (login-free path): a fresh anon client can read it
expect(overview['standings'], isNotNull);
```
No anon client is ever created in the file (`grep -n "anon|createClient|signOut" app/integration_test/hosted_smoke_test.dart` finds only that comment). `overview['standings']` is the response of the SAME `c` call two lines above, made as the signed-in dev user. There is also no cleanup - no delete, no tearDown.
```

**Failure scenario**  
Someone revokes `grant execute ... to anon` on tournament_overview (or an RLS policy narrows), the login-free /tournament/:id deep link 403s for every logged-out viewer, and this smoke test - the only gate that claims to cover it - still passes. Separately, because this runs against hosted ref ocejkqihgiinonpyafhl which holds the friend's real data, every execution permanently adds another 'Hosted Smoke' tournament owned by dev@pitch.local, right before 63 pending migrations are pushed onto that data.

**Root fix**  
Create a second client with the anon/publishable key only (`SupabaseClient(SupabaseEnv.url, SupabaseEnv.anonKey)`), call `tournament_overview` on IT and assert the payload; delete the tournament in a tearDown, or point this test at a disposable project rather than the hosted one holding real data.

**Skeptic's note**  
The file says what the finding says: app/integration_test/hosted_smoke_test.dart:23 signs in as dev@pitch.local, :30 fetches the overview on that same authenticated client c, and :33-34 the comment 'a fresh anon client can read it' sits above an expect on that authenticated response; grep confirms no second client, no signOut, and no cleanup/tearDown. MATERIAL CORRECTION TO THE FAILURE SCENARIO: this is NOT 'the only gate that claims to cover it'. backend/supabase/tests/79-tournament-overview.test.sql:62-67 calls tests.clear_authentication() — which sets role='anon' and clears request.jwt.claims (backend/supabase/seed.sql:235-241) — and then asserts tournament_overview returns the name and champion. Revoking 'grant execute ... to anon' or narrowing RLS would fail that pgTAP test, so the login-free read path is genuinely gated; the misleading comment costs a redundant check, not the only one. The remaining real defects are the vacuous/mislabelled assertion and the missing cleanup (each manual run leaves a 'Hosted Smoke' tournament in the hosted project). Both are test hygiene against a manually-invoked, --dart-define-gated test; low, not high.

---

### [low] match_viewer_test's toss / striker / extras assertions match hardcoded labels and survive deletion of the data they claim to verify

- **id**: `match-viewer-assertions-match-static-labels-only` | **front**: Stale Flutter tests | **category**: test-coverage | **runs**: 2
- **where**: `app/test/match_viewer_test.dart:378`

**Evidence**

```
MUTATION RUN on an unmodified copy, `flutter test test/match_viewer_test.dart` -> "16: All tests passed!" with all three applied:

1) app/lib/src/features/scoring/presentation/match_viewer_screen.dart:1053-1054 `final tossWinner = teams[match['toss_winner_id']]; final decision = match['toss_decision'] as String?;` -> both forced to `null`, so the tile at 1076-1082 renders 'Not decided'. Test "Info tab shows venue + toss + format" (match_viewer_test.dart:378-391) still passes because its toss assertion is `expect(find.textContaining('Toss'), findsWidgets)` and `'Toss'` is the hardcoded label at match_viewer_screen.dart:1077. Its format assertion `expect(find.textContaining('20'), findsWidgets)` matches any text containing "20".

2) match_viewer_screen.dart:543 `'${names[id] ?? '-'}${onStrike ? '  *' : ''}'` -> `'${names[id] ?? '-'}'`. Test "Live tab shows score + teams + striker" (line 130-143) still passes; its striker assertion is `expect(find.textContaining('Rahul'), findsWidgets)` under the comment "// current striker is marked".

3) match_viewer_screen.dart:814 the scorecard not-out marker -> `''` and match_viewer_screen.dart:822-825 the extras line hardcoded to `'Extras  0  (wd 0, nb 0, b 0, lb 0)'`. Test "Scorecard tab shows batting + bowling cards" (line 145-169) still passes; its assertions are `find.textContaining('Rahul')` (comment: "striker carries a not-out '*'") and `find.textContaining('Extras')` (comment: "extras line").
```

**Failure scenario**  
A change to matchProvider's select list drops `toss_winner_id`/`toss_decision`, or a fold change stops emitting `extras`/`striker_id`. Every viewer then shows 'Toss: Not decided', 'Extras 0 (wd 0, nb 0, b 0, lb 0)' and no on-strike marker, while match_viewer_test reports 16/16 green. The same weakness is in the integration test: app/integration_test/viewer_walkthrough_test.dart:74-75 and :98 assert only `find.text('Bowling')` (static header at match_viewer_screen.dart:850), `find.textContaining('Extras')` and `find.textContaining('Toss')`.

**Root fix**  
Assert values, not labels: `expect(find.text('Mumbai United won and chose to bat'), findsOneWidget)`, `expect(find.text('Rahul  *'), findsOneWidget)`, `expect(find.textContaining('Extras  4  (wd 2, nb 1, b 0, lb 1)'), findsOneWidget)`, `expect(find.text('20 overs (6 balls/over)'), findsOneWidget)`.

**Skeptic's note**  
The three assertions are label-only as claimed. Verified in app/lib/src/features/scoring/presentation/match_viewer_screen.dart: 'Toss' is the literal tile LABEL (tile('Toss', tossWinner != null && decision != null ? ... : 'Not decided') at :1076-1082), so app/test/match_viewer_test.dart:389 find.textContaining('Toss') passes whether or not the toss data resolves; 'Extras  $extrasTotal  (wd ..., nb ..., b ..., lb ...)' at :822-826 begins with the hardcoded word 'Extras', so find.textContaining('Extras') at :158 is satisfied by the prefix alone; the on-strike marker at :543 ('${names[id] ?? '-'}${onStrike ? '  *' : ''}') and :813 are never asserted — the tests only match find.textContaining('Rahul'). Two small corrections: the cited line numbers drift by a few (tossWinner/decision are at :1048-1049, not :1053-1054; the scorecard not-out marker is at :813, not :814), and the same file is not uniformly blind — it does assert values elsewhere ('45/2', '28', and the 'Did not bat' contents including/excluding Vinod at :161-165). SEVERITY: this is test-assertion quality with no defect behind it today; low, not high.

---

### [low] scoring_test and platform_adaptive_test reset debugDefaultTargetPlatformOverride outside try/finally, so a failing expect leaks the override

- **id**: `platform-override-not-reset-in-try-finally` | **front**: Stale Flutter tests | **category**: test-hygiene | **runs**: 2
- **where**: `app/test/scoring_test.dart:19`

**Evidence**

```
Unlike every other looped file (e.g. app/test/console_sweep_test.dart:72-80, app/test/ball_log_test.dart:60-70), these two set and clear the override with no try/finally:
```
// app/test/scoring_test.dart:19-35 (pattern repeated for all 4 tests; resets at lines 34, 86, 129, 176)
    testWidgets('Start match screen renders on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(...);
      ...
      expect(find.text('Start a match'), findsWidgets);
      debugDefaultTargetPlatformOverride = null;   // never reached on failure
    });
```
Same in app/test/platform_adaptive_test.dart:14/30 and :36/52. CLAUDE.md's verification protocol explicitly requires "Reset the override with try/finally (NOT addTearDown - invariant check runs before tearDowns)". Verified empirically by mutating `'Innings break'` -> `'Innings interval'` in scoring_console_screen.dart:581: the iOS run of "1st innings end..." fails at line 125 and line 129 never executes, leaving the override set.
```

**Failure scenario**  
A failure in the last test of scoring_test.dart (the android "2nd innings end..." case, whose reset is at line 176) leaves debugDefaultTargetPlatformOverride non-null at file teardown, which flutter_test reports as an extra "The value of a foundation debug variable was changed by the test" error that obscures the real assertion failure. If test ordering changes (loop reordered, or a test inserted), a leaked iOS override silently runs a supposedly-Android test under Cupertino.

**Root fix**  
Wrap the bodies in `try { ... } finally { debugDefaultTargetPlatformOverride = null; }`, matching console_sweep_test.dart and the other 23 looped files.

**Skeptic's note**  
Confirmed for both cited files: app/test/scoring_test.dart sets debugDefaultTargetPlatformOverride at the top of each of 4 tests and resets it as the last statement (lines 20/34, and again at 86, 129, 176) with zero 'finally' in the file; app/test/platform_adaptive_test.dart likewise (set :14 reset :30, set :36 reset :52, zero 'finally'). SCOPE CLAIM IS WRONG: it is not 'these two' versus 'every other looped file'. I counted 'finally' occurrences against override counts across app/test and SEVEN files have no try/finally at all — adaptive_scaffold_test.dart, create_tournament_test.dart, join_tournament_test.dart, matches_list_test.dart, platform_adaptive_test.dart, scoring_test.dart, search_test.dart. Any fix should cover all seven, not two. Severity low is correct.

---

### [low] Test 102's 'mid-over the cap never fires' assertion is vacuous - the bowler is at 1 of 6 permitted balls, so it passes whether or not the cap is gated on over starts

- **id**: `cap-mid-over-assertion-vacuous` | **front**: Stale pgTAP tests | **category**: vacuous-test | **runs**: 1+2
- **where**: `backend/supabase/tests/102-record-ball-cap-stale.test.sql:37`

**Evidence**

```
tests/102-record-ball-cap-stale.test.sql:36-39: `-- mid-over the cap never fires (only over starts are gated)` then `select lives_ok(format($$ select public.record_ball(%L, %L, 1) $$, :'_i', :'_b3'), 'the same bowler continues mid-over');`. At that point b3 has bowled exactly 1 legal ball against a cap of 1 over = 6 balls, and total legal balls = 13, so `_bowler_legal (1) >= _cap_overs * _bpo (6)` is false regardless. The guard block in record_ball_cap_stale.sql:73 (`if _legal_count > 0 and (_legal_count % _bpo) = 0`) is not even entered, so the assertion cannot distinguish the intended behaviour from an unconditional cap check.
```

**Failure scenario**  
Move the cap check out of the over-boundary block in record_ball_cap_stale.sql:89-95 so it fires on every ball, and this test still passes - as does the whole suite. The real semantics it claims to pin (a bowler who is AT the cap may finish the over he already started) is never exercised: no test ever has a bowler with >= cap*bpo legal balls attempt a mid-over delivery.

**Root fix**  
Rewrite the case so the bowler is genuinely at the cap mid-over: let a bowler complete his quota except for the final ball of that over via a wide (so _legal_count % _bpo != 0 while _bowler_legal == cap*bpo - 1), then assert lives_ok for his next legal ball and throws_ok for his first ball of the following over.

**Skeptic's note**  
Verified by counting the fixture. At backend/supabase/tests/102-record-ball-cap-stale.test.sql:37-39 the innings holds 13 legal balls (6 in over 1 plus a wide, 6 in over 2, 1 by b3), so 13 % 6 = 1 and the over-boundary block at 20260706110600_record_ball_cap_stale.sql:73 is never entered; b3 also has only 1 legal ball against cap*bpo = 6, so the assertion passes whether or not the cap is gated on over starts. The semantics the comment claims to pin ('a bowler at the cap may finish the over he already started', migration lines 87-88) is exercised by no test in the suite — no test ever has a bowler with >= cap*bpo legal balls attempt a mid-over delivery.

SEVERITY CORRECTED medium -> low: this is a test that proves less than its label claims, with no defect in shipping code behind it. The suggested rewrite (wide-then-final-ball shape) is the right fix.

---

### [low] retire_batter accepts any team_members row as the incoming batter - an opposition player can be put at the crease

- **id**: `retire-batter-incoming-unvalidated` | **front**: Stale pgTAP tests | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260706110400_rpc_retire_batter.sql:30`

**Evidence**

```
rpc_retire_batter.sql:22-32 validates exactly three things: the retiring batter is at the crease (line 22), an incoming batter is supplied unless this is the last wicket (line 27), and the incoming batter is not already at the crease (line 30). There is no check that _incoming_batter_id belongs to the batting team, is in match_squad for this match, or has not already been dismissed. This is inconsistent with the sweep's own new standard: start_innings (20260706111400_start_innings_validation.sql:26-31) does validate that openers are in the batting squad. tests/101-events-retire-swap.test.sql:62-69 exercises only two of the guards and never the squad-membership case.
```

**Failure scenario**  
Reproduced: two teams A (a1,a2,a3) and B (b1). After one ball, `retire_batter(innings, a2, false, b1)` returns a delivery id with no error, and compute_innings_state then reports striker_id = b1 - a player from the FIELDING side is batting. Every downstream consumer follows: cards credits b1's runs, player_career_stats and the tournament leaderboard attribute them to b1, and match_potm can name a fielder as the batting hero. The console's incoming-batter picker is the only thing preventing it, so any direct RPC call or a picker bug writes an unrecoverable event row.

**Root fix**  
In retire_batter, after the crease check, `if _incoming_batter_id is not null and not exists (select 1 from public.match_squad where match_id = _match_id and team_id = (select batting_team_id from public.innings where id = _innings_id) and team_member_id = _incoming_batter_id) then raise exception ...` (skipping when the batting side declared no squad, matching start_innings' shape). Apply the same guard to record_ball's _incoming_batter_id. Add guard tests to 101.

**Skeptic's note**  
The missing guard is real and I reproduced it: backend/supabase/migrations/20260706110400_rpc_retire_batter.sql:24-32 checks only crease membership, incoming-required, and not-already-at-crease. With teams A(a1,a2,a3)/B(b1,b2) and squads declared, retire_batter(i, a2, false, b1) succeeded and compute_innings_state then reported non_striker_id = b1 — a fielding-side player at the crease. record_ball's _incoming_batter_id is equally unvalidated, and the inconsistency with start_innings (20260706111400:27-32) is accurately described.

SEVERITY CORRECTED high -> low, because the finding's threat model does not hold. Only the match's own scorer can call it (is_match_scorer gate at line 14), and that same principal already has unrestricted INSERT/UPDATE/DELETE on deliveries: policy deliveries_write_scorer is 'for all' with only an is_match_scorer check (backend/supabase/migrations/20260616200801_deliveries.sql:37-41, and grant select,insert,update,delete to authenticated at line 34) — several pgTAP fixtures use exactly that raw-insert path. So a scorer can already stamp an opposition player as striker without touching this RPC; the missing check crosses no privilege boundary and adds only defense against a buggy client. The real client is correct: the incoming-batter dropdown is built from batting-team squad members only (app/lib/src/features/scoring/presentation/scoring_console_screen.dart:887-892). Worth adding as a cheap integrity guard, not a high-severity defect.

---

### [low] generate_group_fixtures / generate_playoffs create matches with no rules jsonb, so the SCOR-15 per-bowler over quota is silently unenforced for every tournament match

- **id**: `tournament-fixtures-missing-bowler-cap-rule` | **front**: Dart<->SQL contract | **category**: correctness | **runs**: 1+2
- **where**: `backend/supabase/migrations/20260625150500_rpc_generate_group_fixtures.sql:29`

**Evidence**

```
record_ball reads the cap from the match: `(m.rules->>'max_overs_per_bowler')::int into ... _cap_overs` and only enforces it when `_cap_overs is not null` (20260706110600_record_ball_cap_stale.sql:35 and :86-91). Its own header claims "The app stamps the rule (default ceil(overs/5), T20 -> 4) into every match it creates" (:5-6). That is true only for MatchRepository.createMatch, which sets `'_rules': {'max_overs_per_bowler': (overs + 4) ~/ 5}` (app/lib/src/features/scoring/data/match_repository.dart:25). Tournament fixtures bypass create_match entirely: `insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit, balls_per_over, ball_type, city, status) values (...)` (20260625150500_rpc_generate_group_fixtures.sql:29-32) and the identical inserts for the semifinals (20260625150700_rpc_generate_playoffs.sql:31-32, :36-37) - no `rules` column, so it takes the table default and max_overs_per_bowler is absent. The console reads the same key for its UI gate: `final capOvers = (rules?['max_overs_per_bowler'] as num?)?.toInt();` (app/lib/src/features/scoring/presentation/scoring_console_screen.dart:997-999), used for the 'Max N overs each' subtitle (:1010) and the atCap block (:1019-1022).
```

**Failure scenario**  
An organizer generates group fixtures for a 20-over tournament and scores a fixture. The bowler picker shows no 'Max N overs each' line and never marks anyone 'At over limit', and record_ball's cap branch is skipped, so one bowler can legally bowl all 20 overs of a tournament match - while the identical casual match created through the Start-a-match wizard correctly caps them at 4. The tournament results and the persisted POTM are computed off that illegal innings.

**Root fix**  
Stamp the rule server-side where the fixtures are minted: add `rules` to both inserts, e.g. `jsonb_build_object('max_overs_per_bowler', ceil(_t.overs_limit / 5.0)::int)` in 20260625150500_rpc_generate_group_fixtures.sql:29-32 and 20260625150700_rpc_generate_playoffs.sql:31-37 (and advance_playoffs' final-match insert). Better still, have the fixture generators call create_match so there is exactly one place that decides a new match's rules.

**Skeptic's note**  
The code claim is accurate: generate_group_fixtures inserts matches with no `rules` column (20260625150500_rpc_generate_group_fixtures.sql:29-32), as do both semifinal inserts in generate_playoffs (20260625150700:31-37) and the final in advance_playoffs (20260625150800:22); only create_match takes a _rules argument (20260616200502:9 / 20260701160000:16) and only MatchRepository.createMatch supplies max_overs_per_bowler (match_repository.dart:25). A repo-wide grep for max_overs_per_bowler finds exactly four hits (the record_ball read at 20260706110600:34, one pgTAP test, createMatch, and the console gate at scoring_console_screen.dart:999), confirming nothing else stamps it. record_ball's cap branch is skipped when _cap_overs is null (:86-91), and the migration header's claim that the app stamps the rule into 'every match it creates' (:5-6) is therefore false for fixtures. FAILURE-SCENARIO CORRECTION: the write-up's 'one bowler can legally bowl all 20 overs' is wrong. The consecutive-over guard is independent of rules.max_overs_per_bowler and defaults to enforcing (allow_consecutive_overs coalesces to false, 20260706110600:33, guard at :77-84), so an uncapped bowler is still limited to alternating overs - at most 10 of 20. Severity lowered from medium to low: no data corruption, no error, no security impact; the effect is a missing UI hint ('Max N overs each' / 'At over limit') and an unenforced optional quota in tournament fixtures, which is the same uncapped behaviour every pre-existing match already has.

---

## Empirical findings (test runs)

# Empirical findings (run by Claude directly, not static review) - 2026-07-07

## GROUND TRUTH RUNS

- `flutter analyze` -> **No issues found** (clean).
- `flutter test` -> **183 tests, All tests passed** (the "159" figure in the audit doc is stale; sweep added 24).
- `supabase test db` WITHOUT a preceding `db reset` -> **Result: FAIL**.
  Files=97, Tests=565, **8 files failing, 18 assertions**.

## FINDING E1 (high, test-integrity): the pgTAP suite only passes on a PRISTINE database

Failing files on a DB that merely has other rows in it:

| file | failed/total |
|---|---|
| 27-deliveries.test.sql | 1/7 |
| 38-record-ball.test.sql | 1/4 |
| 54-transfer-scorer.test.sql | 6/11 |
| 59-record-ball-consecutive-over.test.sql | 3/3 |
| 60-set-delivery-wagon.test.sql | 2/2 |
| 83-record-ball-wicket-guard.test.sql | 1/2 |
| 86-add-match-guest.test.sql | 1/4 |
| 87-set-result-validate-winner.test.sql | 3/7 |

**Root cause**: 11 test files address rows with an UNSCOPED
`(select id from public.matches|innings|deliveries limit 1)`
instead of the id the test itself created (`\gset` is already used elsewhere in
the same files, so the id IS available - this is pure sloppiness).

Sample failure modes actually observed:
- `54`: `transfer_scorer((select id from public.matches limit 1), ...)` picks a
  foreign match -> `42501: not authorized to transfer the scorer role`.
- `27`: direct insert into deliveries for a foreign innings ->
  `42501: new row violates row-level security policy` where the test *wanted*
  the CHECK violation `23514` ("cannot be both wide and no-ball").
  **The constraint under test is never actually exercised.**
- `38`: `stumped on a free hit is rejected` caught `P0001: not authorized`
  instead of `illegal dismissal on a no-ball/free-hit`. It "passes" on a clean
  DB but the throws_ok only matched by luck of the errcode class.

**Why it matters beyond hygiene**: `throws_ok` matching on a *different* error
than intended means several guard tests are VACUOUS even when green. They assert
"something threw", not "the guard fired".

Affected files with the pattern (incl. currently-green ones passing by luck):
06-teams-rls, 25-match-squad, 26-innings, 27-deliveries, 38-record-ball,
40-set-result, 54-transfer-scorer, 59-record-ball-consecutive-over,
60-set-delivery-wagon, 83-record-ball-wicket-guard, 86-add-match-guest,
87-set-result-validate-winner, 88-delete-match.

## FINDING E2 (high, fold-v14 interaction): `60-set-delivery-wagon` picks by global seq

`(select id from public.deliveries order by seq desc limit 1)` - after fold v14
introduced non-ball EVENT ROWS into the same `deliveries` stream, "the last
delivery by seq" can now be a `strike_swap` / `retirement` row. Attaching a
wagon-wheel shot to an event row is nonsense and the test would be asserting
against a row that is not a ball at all. Also `set_delivery_wagon` itself should
be checked: does it refuse event rows? (event rows have no bowler/runs).

## FINDING E3 (medium, doc-integrity): audit doc's verification numbers are stale

`2026-07-05-final-done-audit.md` closes with "backend 520 pgTAP green (93 files);
app 159 widget tests green". Actual today: 565 across 97 files, 183 widget tests.
Any future reader uses those numbers as the regression baseline.
