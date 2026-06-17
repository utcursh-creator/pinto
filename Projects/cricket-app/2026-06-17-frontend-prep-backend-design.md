---
type: design
category: backend
project: cricket-app
date: 2026-06-17
status: draft
sub_project: 4
---

# Frontend-prep additive backend changes

## Context

Three Supabase backends are live and green (199 pgTAP tests): Identity & Teams, Scoring Core, Matchmaking & Discovery. The full app navigation map + wireframes (iOS HIG + Android Material 3) are done. An audit of the wireframes against the actual migrations found 6 frontend gaps + 2 hard backend mismatches that must close before the Flutter scaffold so the headline loop ("find a game -> form a match -> score -> watch") works end to end.

This sub-project is the additive backend changes ONLY. The frontend that consumes them comes in sub-project #5 (Flutter scaffold).

## Sub-project scope

Four small additive changes. Each gets its own timestamped migration + a single pgTAP test file. No schema deletions, no breaking changes, no data backfills (looking_for_posts is empty in dev/prod).

### Change 1 - post flair (required field)

Every looking-for post must declare its social intent: loser-pays competitive vs casual practice vs corporate. Today the post composer wireframe shows a required flair picker but the backend has no field.

Schema:
- `create type public.lf_flair as enum ('loser_pays', 'practice_match', 'corporate_match');` (lower_snake, matching existing lf_mode / lf_status convention; the Flutter composer maps its three chips to exactly these values).
- `alter table public.looking_for_posts add column flair public.lf_flair not null;` (table empty -> NOT NULL without default is safe; Task 1 includes a DO-block fence that aborts the migration if the table is non-empty).
- update create_looking_for_post: new **required** param `_flair public.lf_flair` placed **immediately after `_mode`** (required params must precede the existing optional/defaulted params, else the call site breaks). Update BOTH the INSERT column list AND the VALUES tuple to include `flair`.
- update discover_posts: new optional param `_flair public.lf_flair default null` appended LAST (preserves positional call compatibility), filters with `(_flair is null or flair = _flair)`.

### Change 2 - transfer_scorer RPC (mid-match scorer reassignment)

`matches.scorer_id` is fixed at create_match. If the scorer's phone dies mid-match, the match becomes unscoreable. The audit flagged "Score (admin)" viewer edge as misleading because there is no transfer mechanism.

RPC:
```
create or replace function public.transfer_scorer(_match_id uuid, _new_scorer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
```

Concurrency (verifier blocker): take `pg_advisory_xact_lock(extensions.hashtextextended(_match_id::text, 0))` FIRST, then `select ... for update`, mirroring record_ball's per-match serialisation. Without it a concurrent record_ball can pass `is_match_scorer` against the stale scorer_id and insert under a race.

Order of checks (the idempotent no-op must NOT skip validation - verifier blocker):
1. advisory lock + `select scorer_id, status, team_a_id, team_b_id into ... for update`; raise P0001 if not found.
2. status guard: `status in ('setup','live','innings_break')` else raise P0001.
3. authorization: caller is current `scorer_id` OR `public.is_team_admin(team_a_id)` OR `public.is_team_admin(team_b_id)`, else raise 42501.
4. eligibility: `_new_scorer_id` is a member (`team_members.profile_id`) of team_a or team_b, else raise P0001. (ALWAYS run, even when `_new_scorer_id = scorer_id`.)
5. only AFTER 1-4 pass: if `scorer_id = _new_scorer_id` return (validated no-op); else `update matches set scorer_id = _new_scorer_id`.

Authorization decision (DOCUMENTED): a team admin of EITHER side may assign ANY member of EITHER team as scorer (asymmetric transfer allowed). Rationale: a match is one cooperative event run by two teams; the scorer role is operational, not partisan; the amateur reality is "whoever holds the working phone scores." No cross-team consent flow in v1.

Error codes (house style, matches the 199 existing tests): 42501 for pure authorization denial (caller not scorer/admin), P0001 for business-rule guards (not found, bad status, ineligible new scorer).

### Change 3 - anonymous read policies (login-free viewing)

The realtime broadcast `realtime.messages` receive policy is `to authenticated, anon` for `match:%` topics. But the base SELECT policies on `matches`, `innings`, `deliveries`, `match_squad` are `to authenticated` only. A logged-out viewer opening a shared link receives the live ball stream but cannot fetch the base scorecard snapshot - blank UI. This is the load-bearing virality bug.

New policies (gated by match status so pre-match setup stays private):

```sql
create policy matches_select_anon on public.matches
  for select to anon using (status in ('live', 'innings_break', 'complete', 'abandoned'));

create policy innings_select_anon on public.innings
  for select to anon using (
    exists (select 1 from public.matches m
            where m.id = innings.match_id
              and m.status in ('live', 'innings_break', 'complete', 'abandoned')));

create policy deliveries_select_anon on public.deliveries
  for select to anon using (
    exists (select 1 from public.innings i
            join public.matches m on m.id = i.match_id
            where i.id = deliveries.innings_id
              and m.status in ('live', 'innings_break', 'complete', 'abandoned')));

create policy match_squad_select_anon on public.match_squad
  for select to anon using (
    exists (select 1 from public.matches m
            where m.id = match_squad.match_id
              and m.status in ('live', 'innings_break', 'complete', 'abandoned')));
```

**Player + team name resolution (verifier BLOCKER - the original spec left this broken).** A viewer reads `deliveries` (FKs to team_members) and `match_squad` (FK to team_members) but gets only UUIDs. RLS is ROW-level, not column-level, so we cannot "expose only some columns" of a table via policy. Two resolution paths, by player kind:

- Registered players (team_members.profile_id not null): resolved via a SECURITY DEFINER function that returns only safe fields. Phone / city / playing_role stay authenticated-only because they live on `profiles`, which is never opened to anon.
  ```sql
  create or replace function public.public_profile_minimal(_profile_id uuid)
  returns table(id uuid, display_name text, photo_url text, batting_style public.batting_style)
  language sql security definer set search_path = '' stable
  as $$ select id, display_name, photo_url, batting_style from public.profiles where id = _profile_id $$;
  grant execute on function public.public_profile_minimal(uuid) to anon, authenticated;
  ```
  Note on `search_path = ''`: the body fully-qualifies `public.profiles`, so the empty search_path is correct and maximally safe (the verifier's "only pg_catalog" concern applies only to UNqualified references, which we have none of). The return type is `public.batting_style` (the actual column type on profiles, verified against 20260615140201_profiles.sql - distinct from `public.bats_hand` which is the team_members orientation enum). Returns 0 rows for an unknown id (no row-existence oracle beyond what match_squad already reveals).

- Guests (team_members.guest_name not null, profile_id null): there is no profiles row. Their name lives in `team_members.guest_name`, so anon must be able to read the team_members rows that belong to a public match's squad. team_members has NO sensitive columns (no phone/email - phone is on profiles), so a row-gated anon policy is safe.

Anon read policies (all gated by `matches.status in ('live','innings_break','complete','abandoned')` so pre-match setup stays private; team_members + teams gated by participation in such a match):

```sql
create policy matches_select_anon on public.matches
  for select to anon using (status in ('live','innings_break','complete','abandoned'));

create policy innings_select_anon on public.innings
  for select to anon using (exists (
    select 1 from public.matches m where m.id = innings.match_id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy deliveries_select_anon on public.deliveries
  for select to anon using (exists (
    select 1 from public.innings i join public.matches m on m.id = i.match_id
      where i.id = deliveries.innings_id
        and m.status in ('live','innings_break','complete','abandoned')));

create policy match_squad_select_anon on public.match_squad
  for select to anon using (exists (
    select 1 from public.matches m where m.id = match_squad.match_id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy team_members_select_anon on public.team_members
  for select to anon using (exists (
    select 1 from public.match_squad ms join public.matches m on m.id = ms.match_id
      where ms.team_member_id = team_members.id
        and m.status in ('live','innings_break','complete','abandoned')));

create policy teams_select_anon on public.teams
  for select to anon using (exists (
    select 1 from public.matches m
      where (m.team_a_id = teams.id or m.team_b_id = teams.id)
        and m.status in ('live','innings_break','complete','abandoned')));
```

Grants:
- `grant select on public.matches, public.innings, public.deliveries, public.match_squad, public.team_members, public.teams to anon;`
- `grant execute on function public.public_profile_minimal(uuid) to anon;`

**Client requirement (verifier MAJOR - affects sub-project #5).** Supabase Realtime needs a session token for the WebSocket handshake even for the `anon` role. The Flutter client MUST call `supabase.auth.signInAnonymously()` on first launch when there is no session, before subscribing to `match:<id>`. Without it the broadcast receive 401s despite the `to anon` receive policy. This is a client note, not a migration; recorded here so SP5 implements it.

**Performance note.** The anon policies on deliveries/innings do an `exists` subquery per row. For a 50-over innings (~300 deliveries) each row does two PK-indexed lookups (innings PK, matches PK) - cheap, not a 300-way join. Task 6 records an `EXPLAIN` baseline; if a seq scan appears, add `create index if not exists innings_match_idx on public.innings(match_id)`.

### Change 4 - wagon-wheel applicable hint in record_ball

For wides, byes, leg-byes, clean-bowled, LBW the bat made no directional contact -> the client should not open the wagon-wheel sheet. Instead of duplicating this rule across iOS + Android clients we move the policy server-side: `record_ball` returns `wagon_applicable boolean` alongside the inserted delivery id.

**Corrected predicate (verifier found the original had a non-existent enum value `caught_behind` and mishandled wides + no-balls).** Grounded in the real `deliveries` schema (`extra_wides`, `extra_no_ball_penalty`, `extra_byes`, `extra_leg_byes`, `noball_secondary_kind` enum `off_bat|bye|leg_bye`) and the real `wicket_type` enum (`bowled, caught, lbw, run_out, stumped, hit_wicket, retired_out, retired_not_out, obstructing, timed_out, hit_ball_twice` - there is NO `caught_behind`):

```sql
wagon_applicable :=
      extra_wides   = 0                                              -- a wide is, by definition, not hit
  and extra_byes    = 0                                              -- byes = missed entirely
  and extra_leg_byes = 0                                             -- leg-byes = off the body, not the bat
  and (noball_secondary_kind is null
       or noball_secondary_kind = 'off_bat')                         -- a no-ball gets a wagon ONLY if hit off the bat
  and (wicket_type is null
       or wicket_type in ('caught','run_out'));                      -- only these dismissals imply a directional bat shot
```

Why this shape:
- Note it does NOT gate on `is_legal`. A no-ball is `is_legal = false`, but a no-ball struck off the bat (`noball_secondary_kind = 'off_bat'`) IS a real directional shot and should get a wagon. The wide/bye/leg-bye/secondary-kind conditions do the work instead.
- `run_out` is included but the extras conditions gate it by context: a run_out off a legal off-bat ball -> true; a run_out off a wide or a bye -> the `extra_wides`/`extra_byes` conditions force false. This fixes the verifier's "run-out off a wide" case.
- `caught` and `run_out` are the only dismissals that imply the striker hit the ball in a direction. `bowled` / `lbw` / `stumped` / `hit_wicket` / `obstructing` / `hit_ball_twice` / `timed_out` / `retired_*` -> false (no directional shot, or ambiguous; default false). This drops `obstructing` and `hit_ball_twice` from the original (over-permissive) set.
- A legal defended dot (no runs, no extras, no wicket) -> true: the striker did make bat contact, the prompt is offered, and the client's Quick-mode can still skip it. "Per-delivery directional opportunity," not "per-run."

Representation: `record_ball` return type changes from its current `uuid` to `table(delivery_id uuid, wagon_applicable boolean)` - preserves the inserted id that callers already use AND adds the hint. This is a breaking signature change (see Decisions log); the only current caller is the integration + record_ball pgTAP tests, updated in Tasks 9-10. The migration DROPs the old function before recreating so PostgREST reloads the new signature.

No data validation tightening - wagon_x/y/zone columns remain nullable; the hint just helps the client decide whether to prompt.

## Conventions

- All custom RPC business-rule violations raise with `errcode = 'P0001'`. Pure authorization denials raise `42501` (consistent with the existing identity/scoring RPCs and their 199 passing tests). SQLSTATE 42501 is also what RLS denials surface as.
- New SECURITY DEFINER functions use `set search_path = ''` and fully-qualify every reference (`public.*`, `extensions.*`).

## Out of scope (with rationale for the deferred verifier suggestions)

- Frontend UI screens (Flutter scaffold = sub-project #5).
- Client-side quick-mode toggle for wagon (client preference; not backend).
- Shot-type capture (deferred - user previously confirmed keeping the v1 schema).
- Multi-scorer cooperative scoring.
- **`recorded_by_scorer_id` audit column on deliveries (verifier suggested).** DEFERRED. Corrections are already gated on the CURRENT scorer via `is_match_scorer`, which is acceptable for amateur cricket where the authoritative scorer is simply whoever holds the role now. Adding the column touches deliveries + record_ball + the fold + every scoring test - disproportionate to the risk. Revisit if attribution disputes surface.
- **team_members-delete-orphans-scorer trigger (verifier suggested).** DEFERRED. A player who is the active scorer being removed mid-match is rare; the remedy is a re-transfer. A hard guard (block delete, or null + pause) can be added later without rework.
- **`matches.is_public` flag (verifier suggested).** DEFERRED. Status-gating (`live/innings_break/complete/abandoned`) is sufficient for v1's public-by-default live viewing. Adding `is_public boolean default true` later is itself an additive change; no private-match or tournament feature exists yet to need it.
- Sub-project #6 Stats & Rankings.
- Sub-project #7 Tournaments.

## Decisions log

- **Anon read gated by `matches.status` (vs blanket anon read)**: protects pre-match team selection, draft squads, and admin-only internals from being scraped. Only matches that are visibly in flight or finished are public.
- **`public_profile_minimal` SECURITY DEFINER function (vs anon SELECT on profiles)**: exposes only display_name / photo / batting_style to anon. Phone, city, role stay authenticated. This keeps the principle from sub-project #3 ("locations never leave their definer fences").
- **transfer_scorer allowed in `setup` status too**: scorer can hand off the match before it starts; common case when the creator delegates scoring to a teammate.
- **record_ball returns `wagon_applicable` hint (vs duplicating rule on each client)**: single source of truth for the wagon-skip logic.
- **flair = NOT NULL with no default**: forces the new param in create_looking_for_post; safe because the table is empty.

## Test plan (pgTAP, files 53-57)

53-flair.test.sql:
- `has_type('public','lf_flair',...)`, `col_not_null('public','looking_for_posts','flair')`
- create_looking_for_post happy path inserts with flair value
- create_looking_for_post rejects when flair invalid
- discover_posts returns post when _flair = post's flair
- discover_posts filters out post when _flair = different flair
- discover_posts returns post when _flair = null (no filter)

54-transfer-scorer.test.sql:
- transfer_scorer succeeds when caller = current scorer + new scorer = team member
- transfer_scorer succeeds when caller = team admin + new scorer = team admin
- transfer_scorer rejects (42501) when caller is neither scorer nor team admin
- transfer_scorer rejects (P0001) when new scorer is not a team member nor admin
- transfer_scorer is idempotent (no-op when new scorer == current scorer)
- transfer_scorer rejects (P0001) when status = 'complete'
- transfer_scorer succeeds when status = 'setup'

55-anon-read.test.sql:
- anon SELECT on matches returns row when status = 'live'; empty when status = 'setup'
- anon SELECT on innings + deliveries + match_squad gated by parent match status
- anon SELECT on team_members returns ONLY rows that are in a public match's squad (guest names resolvable); a team_member NOT in any public match is invisible to anon
- anon SELECT on teams returns the two participating teams of a live match; an unrelated team is invisible
- (test harness: `set local role anon` + clear jwt claims to truly drop auth context)

56-public-profile-minimal.test.sql:
- public_profile_minimal returns id, display_name, photo_url, batting_style for a valid id
- returns 0 rows for an unknown id
- does NOT expose phone, city, playing_role (assert the result has no such columns)
- callable by both anon and authenticated

57-wagon-applicable.test.sql (expanded per verifier):
- off-bat 4 (no extras, no wkt) -> true
- legal defended dot (0 runs, no extras) -> true
- wide -> false
- wide that ran byes -> false
- bye (extra_byes > 0) -> false
- leg-bye -> false
- no-ball off bat -> true
- no-ball + bye (noball_secondary_kind='bye') -> false
- bowled -> false; lbw -> false; stumped -> false; hit_wicket -> false
- caught (legal) -> true
- run_out off legal off-bat -> true
- run_out off a wide -> false
- obstructing -> false; hit_ball_twice -> false

All previous 199 tests must still pass (target ~224 total).
