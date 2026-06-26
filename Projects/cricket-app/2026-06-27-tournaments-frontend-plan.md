---
type: plan
date: 2026-06-27
project: cricket-app
subproject: tournaments
status: ready
---

# Tournaments frontend - implementation plan

Frontend for the completed Tournaments backend (9 RPCs, 396 pgTAP green).
CricHeroes-reverse-engineered, scoped to our v1. Flutter, Riverpod (manual
providers), go_router, platform-adaptive. A tournament fixture is a normal
matches row, so scoring reuses the existing setup wizard + console. Verification
protocol per slice: `flutter analyze` clean; widget tests on BOTH platforms;
run on the iOS sim via integration_test vs live Supabase; commit per slice.

Feature dir: `app/lib/src/features/tournaments/` (data + presentation).

## Slice 1 - data layer
- `data/tournament_repository.dart`: `TournamentRepository(client)` +
  `tournamentRepositoryProvider`. Methods: createTournament(name, overs, ballType?,
  city?, venue?, startsOn?, endsOn?) [group_count=2, qualifiers=2 baked], 
  addTournamentTeam(tid, teamId, group), generateGroupFixtures(tid),
  generatePlayoffs(tid), advancePlayoffs(tid). Each `_c.rpc(...)`.
- `data/tournament_providers.dart`:
  - `tournamentsListProvider` (FutureProvider) -> `from('tournaments').select('id,name,status,city,starts_on,champion_team_id').order('created_at', desc)`.
  - `tournamentOverviewProvider` (FutureProvider.family<Map,String>) -> rpc('tournament_overview', {'_tournament_id': id}) (login-free).
  - `matchPotmProvider` (FutureProvider.family<Map?,String>) -> rpc('match_potm', {'_match_id': id}).
- `data/tournament_models.dart`: typed parse of the overview jsonb (Tournament,
  StandingsGroup+Row, Fixture, BracketSlot, LeaderEntry) with the formatting
  (NRR sign, qualified marker from qualifiers_per_group, status label).
- Tests: model parse unit tests (overview jsonb -> typed; NRR '+1.82'/'-0.41';
  status labels; qualified top-N).

## Slice 2 - tournaments list + create (Matches tab)
- `presentation/tournaments_list_screen.dart`: cards (name, status chip, city,
  champion badge). "+ Create tournament" -> create screen. Reached from a
  "Tournaments" entry on the Matches screen (a list tile / segment).
- `presentation/create_tournament_screen.dart`: form (name, overs segmented,
  ball type segmented, city, dates) -> createTournament -> push manage.
- Routes: `/matches/tournaments`, `/matches/tournaments/new`,
  `/matches/tournaments/:id/manage`. Matches-tab entry tile.
- Tests (both platforms): list renders cards + status chips; create form
  validates name + calls repo (fake repo override).

## Slice 3 - manage (organizer)
- `presentation/manage_tournament_screen.dart`: status-driven.
  - setup: team list with A/B group toggles (add team via the team picker -> 
    addTournamentTeam); "Generate group fixtures" (enabled when >=2 teams/group).
  - group_stage: fixtures grouped (tap an incomplete one -> scoreMatch route; a
    completed one -> viewMatch); "Generate playoffs" (enabled when all group
    matches complete).
  - playoffs: semis (Score / result); "Advance to final" (advancePlayoffs); then
    the final; final done -> "Crown champion" (advancePlayoffs) -> complete.
- Reuses `tournamentOverviewProvider` (invalidate after each mutation).
- Tests (both platforms): each state renders the right controls; generate/advance
  buttons gate correctly; mutations call the repo (fake).

## Slice 4 - public tournament page (4 tabs)
- `presentation/tournament_page_screen.dart`: top-level public route
  `/tournament/:id` (gate-bypassed like /watch). One overview call. AdaptiveScaffold
  + a 4-tab control: Table (per-group standings + NRR + qualified markers),
  Fixtures (grouped by stage; upcoming/live/past; tap -> viewMatch), Bracket
  (semis -> final -> champion), Leaders (most runs/wickets/catches/4s/6s with a
  category switch). Champion banner when complete. Share action (share_plus link).
- Router: add `/tournament/:id` top-level + `/tournament/` to onboardingRedirect bypass.
- Nav: tournament list card -> tournament page; manage screen has a "View public page".
- Tests (both platforms): each tab renders from a fake overview (Table NRR +
  qualified marker; Fixtures stages + live dot; Bracket champion; Leaders #1);
  empty/setup state.

## Slice 5 - POTM on the match viewer
- In `match_viewer_screen.dart` Info/Scorecard tab (finished match): a "Player of
  the match" line from `matchPotmProvider(matchId)` (name + impact). Reused for
  tournament + non-tournament matches.
- Tests: viewer shows the POTM line when match_potm returns a player; hidden when null.

## Slice 6 - verify on sim + integration
- integration_test/tournaments_walkthrough_test.dart: seed a small tournament via
  the RPCs (or reuse a seeded one), open `/tournament/:id`, tab through Table/
  Fixtures/Bracket/Leaders, screenshot each. Confirm real data renders.
- Recreate /tmp reseed for the app demo if needed.

## Gotchas (carried)
- Riverpod 3.x: `.value` not `.valueOrNull`; never `ref.read` in dispose; manual providers.
- AdaptiveScaffold wraps Cupertino body in Material(transparency).
- go_router top-level route for the public page (StatefulShellRoute branches do not cold-start deep) - same pattern as /watch + /player.
- The tab control: no real tabs that lazily-build offstage issues in tests -> use a simple SegmentedButton + an IndexedStack or conditional, and scrollUntilVisible in tests if needed.
- Override providers (not the repo's SupabaseClient) in widget tests; read the repo lazily before a mutation (see ball_log_screen) so tests don't touch Supabase.instance.
