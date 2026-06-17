---
type: plan
category: backend
project: cricket-app
date: 2026-06-17
status: draft
sub_project: 4
related: 2026-06-17-frontend-prep-backend-design.md
---

# Sub-project 4 - Frontend-prep additive backend plan

## Stack reuse

Same as sub-projects 1-3: Supabase CLI 2.106.0 + OrbStack daemon + local Postgres 15 + pgTAP + vendored basejump test helpers (already in `supabase/seed.sql`). Controller-TDD (subagent dispatch still 1M-credit-blocked; Workflow agents work fine for verification). Migrations timestamped manually (the auto-`supabase migration new` truncates). Test files numbered 53-57 (continue from matchmaking 43-52).

Two local gotchas already documented (apply from day 1):
- explicit `grant ... to authenticated/anon` on every new function and any table reference (local doesn't auto-grant; prod does).
- psql does NOT interpolate `:'var'` inside `$$..$$` dollar-quoted strings -> inside throws_ok/lives_ok use subqueries identifying rows, not `:var`s.

## Phase 1 - Flair (Tasks 1-3)

### Task 1: lf_flair enum + flair column
- File: `migrations/20260617120000_lf_flair.sql`
- Test: `tests/53-flair.test.sql` PART A
- Red: pgTAP file asserts type exists + col_not_null + table empty (precondition).
- Green:
  ```
  create type public.lf_flair as enum ('loser_pays', 'practice_match', 'corporate_match');
  alter table public.looking_for_posts add column flair public.lf_flair;
  -- safety: only set NOT NULL if table is empty
  do $$ begin if (select count(*) from public.looking_for_posts) > 0 then raise 'table not empty - migration unsafe'; end if; end $$;
  alter table public.looking_for_posts alter column flair set not null;
  ```
- Verify suite green; commit.

### Task 2: alter create_looking_for_post + discover_posts
- File: `migrations/20260617120500_lf_flair_rpc.sql`
- Test: `tests/53-flair.test.sql` PART B (RPCs)
- Red: tests for happy path with flair arg, invalid flair, discover_posts filter.
- Green: replace both functions with new signatures (keeps SECURITY DEFINER + search_path = ''). Insert flair into looking_for_posts; add `_flair public.lf_flair default null` last param on discover_posts (preserves call-site compatibility) and a where-clause `(_flair is null or flair = _flair)`.
- Update integration test 52 to pass flair.

### Task 3: update 52-integration.test.sql for flair arg
- One-line patch to the existing integration test.

## Phase 2 - Transfer scorer (Tasks 4-5)

### Task 4: transfer_scorer RPC
- File: `migrations/20260617121000_transfer_scorer.sql`
- Test: `tests/54-transfer-scorer.test.sql`
- Red: 7 sub-tests (happy paths for scorer-initiated, admin-initiated; rejection of unauthorized caller; rejection of ineligible new scorer; idempotence; status guards setup/complete).
- Green (advisory lock FIRST, then validate-ALWAYS before the idempotent no-op - both per verifier):
  ```sql
  create or replace function public.transfer_scorer(_match_id uuid, _new_scorer_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = ''
  as $$
  declare _m public.matches%rowtype; _is_caller_admin bool; _is_new_eligible bool;
  begin
    perform extensions.hashtextextended(_match_id::text, 0);            -- placeholder; real call below
    perform pg_advisory_xact_lock(extensions.hashtextextended(_match_id::text, 0));
    select * into _m from public.matches where id = _match_id for update;
    if not found then raise exception 'match not found' using errcode='P0001'; end if;
    -- 2. status guard
    if _m.status not in ('setup','live','innings_break') then
      raise exception 'match status % does not allow scorer transfer', _m.status using errcode='P0001';
    end if;
    -- 3. authorization (42501 = pure authz denial, house style)
    _is_caller_admin := public.is_team_admin(_m.team_a_id) or public.is_team_admin(_m.team_b_id);
    if auth.uid() <> _m.scorer_id and not _is_caller_admin then
      raise exception 'not authorized to transfer scorer' using errcode='42501';
    end if;
    -- 4. eligibility - ALWAYS, even on a same-scorer no-op
    _is_new_eligible := exists (
      select 1 from public.team_members tm
      where tm.profile_id = _new_scorer_id and tm.team_id in (_m.team_a_id, _m.team_b_id)
    );
    if not _is_new_eligible then
      raise exception 'new scorer must be a member of either team' using errcode='P0001';
    end if;
    -- 5. validated no-op, else transfer
    if _m.scorer_id = _new_scorer_id then return; end if;
    update public.matches set scorer_id = _new_scorer_id where id = _match_id;
  end $$;
  grant execute on function public.transfer_scorer(uuid, uuid) to authenticated;
  ```
  Note: `pg_advisory_xact_lock` + `extensions.hashtextextended` mirror the record_ball pattern exactly (verify the exact qualified name used there during build - record_ball uses `hashtextextended`; match its schema-qualification). The lock serialises against a concurrent record_ball.
- Tests: add a sub-test asserting an ineligible no-op still raises (validate-always), plus the asymmetric team_a-admin -> team_b-player accept case.

### Task 5: integration test for transfer mid-match
- File: append to `tests/52-integration.test.sql`
- A short scenario: create match -> start scoring -> transfer to teammate -> teammate records next ball successfully.

## Phase 3 - Anon read (Tasks 6-8)

### Task 6: anon SELECT policies on SIX viewer tables (matches/innings/deliveries/match_squad + team_members + teams)
- File: `migrations/20260617122000_anon_read_viewer.sql`
- Test: `tests/55-anon-read.test.sql`
- Red: anon SELECT returns rows for live match, 0 rows for setup match; team_members visible to anon ONLY when in a public match's squad; teams visible ONLY when participating.
- Green: SIX `create policy ... to anon ... using (status guard)` blocks (matches/innings/deliveries/match_squad/team_members/teams per the design doc) + grants:
  ```
  grant select on public.matches, public.innings, public.deliveries, public.match_squad, public.team_members, public.teams to anon;
  ```
- The team_members + teams policies close the guest-name-resolution BLOCKER (registered players resolved via public_profile_minimal; guests via team_members.guest_name; team names+logos via teams).
- Add `EXPLAIN` line in the test (or a comment) to record the deliveries anon-select plan; add `create index if not exists innings_match_idx on public.innings(match_id)` only if a seq scan shows.
- Note: pgTAP test uses `set local role anon` + clears jwt claims to drop auth context.

### Task 7: public_profile_minimal SECURITY DEFINER function
- File: `migrations/20260617122500_public_profile_minimal.sql`
- Test: `tests/56-public-profile-minimal.test.sql`
- Red: function returns minimal fields; does not expose phone/city/role; 0 rows for unknown id.
- Green (return type is `public.batting_style` - verified against 20260615140201_profiles.sql; this is the profiles column type, distinct from `public.bats_hand` on team_members):
  ```sql
  create or replace function public.public_profile_minimal(_profile_id uuid)
  returns table(id uuid, display_name text, photo_url text, batting_style public.batting_style)
  language sql security definer set search_path = '' stable
  as $$
    select id, display_name, photo_url, batting_style
    from public.profiles where id = _profile_id
  $$;
  grant execute on function public.public_profile_minimal(uuid) to anon, authenticated;
  ```

### Task 8: anon integration test
- File: `tests/55-anon-read.test.sql` PART B
- Authenticate as a scorer, set a match to live, set role to anon, assert anon can SELECT and call public_profile_minimal. Set match back to setup, assert anon cannot SELECT.

## Phase 4 - Wagon applicable (Tasks 9-10)

### Task 9: alter record_ball to return wagon_applicable
- Decision: ADD A NEW PARAMETER vs ADD A NEW FUNCTION vs RETURN JSONB.
- Chose: change return type from `void` to `table(seq integer, wagon_applicable boolean)`. The existing record_ball call sites are: scoring integration test (52), forthcoming Flutter client. Both will be updated to read the return.
- File: `migrations/20260617123000_record_ball_wagon_hint.sql`
- Test: `tests/57-wagon-applicable.test.sql`
- Red: cases per the expanded design test plan (off-bat 4, defended dot, no-ball off bat, caught, run_out off legal -> true; wide, wide+byes, bye, leg-bye, no-ball+bye, bowled, lbw, stumped, hit_wicket, run_out-off-wide, obstructing, hit_ball_twice -> false).
- Green: drop old `record_ball` (so PostgREST reloads), recreate with `returns table(delivery_id uuid, wagon_applicable boolean)`; compute the CORRECTED predicate inline:
  ```sql
  -- after the row is inserted into deliveries as NEW/_d:
  delivery_id := _d.id;
  wagon_applicable :=
        _d.extra_wides = 0 and _d.extra_byes = 0 and _d.extra_leg_byes = 0
    and (_d.noball_secondary_kind is null or _d.noball_secondary_kind = 'off_bat')
    and (_d.wicket_type is null or _d.wicket_type in ('caught','run_out'));
  return next;
  ```
- The predicate uses ONLY real columns/enum values (verified against 20260616200801_deliveries.sql + scoring_enums.sql). NOT gated on is_legal (a no-ball off the bat must still get a wagon).

### Task 10: update integration test
- File: `tests/52-integration.test.sql` to consume the new return.

## Execution order

1. Task 1 -> reset -> test db (full green required at each step).
2. Task 2 -> reset -> test.
3. Task 3 -> test.
4. Task 4 -> reset -> test.
5. Task 5 -> test.
6. Task 6 -> reset -> test.
7. Task 7 -> reset -> test.
8. Task 8 -> test.
9. Task 9 -> reset -> test.
10. Task 10 -> test (full suite, 199 + ~25 new).

After all green: commit per task, push branch, open PR optional. Sub-project #5 (Flutter scaffold) follows.

## Anticipated bugs (preempt fixes)

- Anon RLS test will likely need `set role anon` AND `set request.jwt.claims to '{}'::jsonb` to truly drop authentication context. pgTAP harness already supports this via basejump helpers.
- transfer_scorer + concurrent record_ball: the `for update` lock + the existing per-innings advisory lock in record_ball serialise the writes, so a concurrent ball-record either commits with the old scorer (just-in-time) or sees the new scorer after the transfer commits. No interleaving.
- record_ball return-type change is a breaking signature change for any cached PostgREST schema. Mitigate by dropping the old function definition explicitly in the migration before recreating, so PostgREST picks up the new signature on reload.
- The empty-table guard in Task 1 may not trip in pgTAP because each test runs in its own transaction; the guard runs at migration time so prod is the case to worry about. The DO block is the fence.

## Definition of done

- 224 tests green (199 baseline + ~25 new).
- 5 new migration files + 5 new test files + 2 patches to existing tests.
- Plan + spec live in `Projects/cricket-app/` alongside prior sub-project docs.
- README.md updated with the four new capabilities.
- Branch ready for PR.
