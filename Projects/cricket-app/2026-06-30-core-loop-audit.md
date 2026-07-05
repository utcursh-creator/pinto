---
type: audit
date: 2026-06-30
project: cricket-app
status: open
trigger: friend cold-tested the release APK; core loop broke
---

# Pitch - Core Loop Audit (post friend cold-test)

Verified against the working tree by a 9-agent code-grounded audit (workflow wf_6f88519f-796). 38 raw findings -> **20 distinct issues, 4 blockers**. Honest verdict: **the core loop is NOT functional for a fresh user - a convincing skeleton, not a working product.** The backend engine (fold, RLS, RPCs) is largely correct; the recurring failure is **the frontend never calling capabilities the backend already exposes** (unused providers, omitted RPC params, never-invoked repo methods). That means a large share of fixes are frontend wiring -> fast.

## Why it failed in real use (the 3 hard walls)
1. **Can't field two real teams (B3)** - you can only populate a roster for a team you admin, and there's no add-guest inside the match wizard, so the only practical path is creating BOTH teams yourself. That is exactly the "both teams under one user / not Team A vs B" feeling.
2. **Teams aren't even labeled (M1)** - setup + scoring screens print literal "Team A"/"Team B" though a correct name resolver sits unused in the same file.
3. **The match can never finish (B1)** - after innings 1, the run pad keeps taking taps that go nowhere; no 2nd-innings prompt, no result button; `set_match_result` has ZERO callers. Match is stuck `live` forever, no winner recorded. This also blocks ALL of tournaments (playoffs need completed matches) and leaves the public tournament Table/Fixtures blank (M11).

## BLOCKERS
- **B1 - Match never completes.** No 2nd innings (`startInnings` only ever called with `inningsNumber:1`), `setResult` has 0 callers, console never reads `innings_status`, `record_ball` has no innings-end guard. Fix: console branches on `innings_status=='completed'` -> "Start 2nd innings" (target = innings1 runs+1) or "Finish match" -> `setResult` from the fold's result; add a defensive guard to `record_ball`. *(small migration + FE) - highest-leverage fix.*
- **B2 - Tournament fixtures unscorable.** `manage_tournament_screen.dart:178,182` route Score/onTap to `scoreMatch` (dead-ends at "No innings yet"); never enters the squad wizard. Fix: route `setup` fixtures to `matchSquads`, `live` to `scoreMatch`, `complete` to `viewMatch`. *(FE only)*
- **B3 - Opponent side can't get a squad.** Add-guest is gated to team admin + only on the team page. Fix: `add_match_guest(_match_id,_team_id,_guest_name)` RPC gated by `is_match_scorer`; inline add-guest under each picker. *(migration + FE)*
- **B4 - Looking-for posts have no ball_type/contact storage; composer drops fields.** Fix: add `ball_type`+`contact` columns; DROP+CREATE `create_looking_for_post`+`discover_posts`; composer inputs (title/overs/ball/skill/slots/date/contact). *(migration + FE)*

## MAJOR
- **M1** Team names hardcoded "Team A/B" in squads/toss/console (resolver `matchTeamNamesProvider` exists, unused). *FE*
- **M2** No remove/leave/delete-team (RLS allows it; no RPC/UI). *migration + FE*
- **M3** Squad picker validates only combined count -> a side can have 0 bowlers. *FE*
- **M4** Wicket "incoming batter" list includes already-out + at-crease players. *FE (+optional guard)*
- **M5** Match result computed + stored but never displayed (viewer prints raw status). *FE*
- **M6** Abandoned `setup` match strands on the dead console, undeletable. *FE*
- **M7** No set captain / keeper / batting order (RPC accepts them; repo+UI omit). *FE*
- **M8** Location screen exposes raw lat/long text fields. *FE (needs geocoding pkg)*
- **M9** Home-location area label never persisted (backend supports it). *FE*
- **M10** Discover cards omit poster name + team (UUIDs only). *migration + FE*
- **M11** Public tournament Fixtures/Table blank (standings only count completed matches; not seeded from `tournament_teams`). *migration + FE*
- **M12** Organizer can only add their OWN teams (`_addTeam` reads `myTeamsProvider`). *FE*

## MINOR
- Mn1 add `geocoding` package (prereq for M8/M9). Mn2 post-type label rendered twice on card/detail. Mn3 "0 m" distance -> "Nearby". Mn4 cards hide returned fields (place/overs/skill/slots/match_at). Mn5 Matches list has no team names (`myMatchesProvider` no embed). Mn6 DM header hardcoded "Chat". Mn7 Discover->match bridge drops the post (no DM/notify). Mn8 public viewer "Team A/B" fallback for failed anon bootstrap (serve via SECURITY DEFINER `match_team_names`).

## Fix sequence (backend-first within each slice)
- **Slice 1 - real Team-A-vs-B with names:** M1, Mn5, M3, B3(migration). Removes the "Team A/B / one user" perception.
- **Slice 2 - let a match finish (unblocks everything):** B1(small migration+FE), M4, M5, M6.
- **Slice 3 - tournaments run:** M11(migration), B2, M12. (depends on Slice 2)
- **Slice 4 - Discover is real matchmaking:** B4(migration), M10(migration), composer/cards FE, Mn2/Mn3/Mn4.
- **Slice 5 - roster & roles:** M2(migration), M7.
- **Slice 6 - human location:** Mn1(package), M8, M9.
- **Slice 7 - messaging/polish:** Mn6, Mn7, Mn8(small migration).

Migration-bearing (do first within slice): B3, B1, M11, B4, M10, M2, Mn8.

## Acceptance standard (NEW - this is why it slipped)
Seeded-data + provider-override tests gave false confidence. From now, each slice is gated by a **from-scratch playthrough that CREATES every entity through the UI** (scripted via integration_test or a real device pass), ending in: two named teams -> a real A-vs-B match -> a full 2-innings score -> a displayed result. No "verified" claim without that.
