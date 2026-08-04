-- Whole-system review #2 (2026-07-28), findings 65 and 73: two queries whose
-- cost grows with the size of the whole database rather than with the thing
-- being asked about.

-- 65: tournament_leaderboard's `names` CTE was
--   select tmem.id, coalesce(tmem.guest_name, p.display_name, 'Player')
--     from team_members tmem left join profiles p on p.id = tmem.profile_id
-- with no filter, referenced FIVE times. PostgreSQL only inlines a CTE
-- referenced once, so this one is materialised: whenever the leaderboard has
-- any rows at all it builds a temporary relation holding one row per team
-- membership IN THE ENTIRE DATABASE, to attach names to at most 50 rows. The
-- endpoint is anon-callable and the public tournament page has no caching.
--
-- Measured honestly: on an EMPTY tournament the CTE is never scanned, so the
-- finding's "every load" is too strong - 200k decoy memberships left an empty
-- leaderboard at ~0.5ms. The growth term is real the moment the leaderboard has
-- one row, which is every tournament anyone actually shares.
--
-- Scoped to the members who appear in this tournament: at most a few hundred.
create or replace function public.tournament_leaderboard(_tournament_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
with inns as (
  select i.id from public.innings i
  join public.matches m on m.id = i.match_id
  join public.tournament_matches tm on tm.match_id = m.id
  where tm.tournament_id = _tournament_id and m.status = 'complete'
),
cards as (select public.compute_innings_cards(id) as c from inns),
bat as (
  select (e->>'member_id')::uuid mid, (e->>'runs')::int runs, (e->>'fours')::int fours, (e->>'sixes')::int sixes
  from cards, jsonb_array_elements(c->'batting') e
),
bowl as (
  select (e->>'member_id')::uuid mid, (e->>'wickets')::int wkts
  from cards, jsonb_array_elements(c->'bowling') e
),
fld as (
  select (e->>'member_id')::uuid mid,
         ((e->>'catches')::int + (e->>'run_outs')::int + (e->>'stumpings')::int) dis
  from cards, jsonb_array_elements(c->'fielding') e
),
-- every member who actually appears on a card in THIS tournament
appearing as (
  select mid from bat union select mid from bowl union select mid from fld
),
names as (
  select tmem.id mid, tmem.profile_id pid,
         coalesce(tmem.guest_name, p.display_name, 'Player') name
  from public.team_members tmem
  join appearing a on a.mid = tmem.id
  left join public.profiles p on p.id = tmem.profile_id
),
run_agg   as (select mid, sum(runs) runs, sum(fours) fours, sum(sixes) sixes from bat group by mid),
wkt_agg   as (select mid, sum(wkts) wkts from bowl group by mid),
field_agg as (select mid, sum(dis) dis from fld group by mid)
select jsonb_build_object(
  'most_runs', coalesce((select jsonb_agg(jsonb_build_object('member_id',a.mid,'profile_id',n.pid,'name',n.name,'runs',a.runs) order by a.runs desc)
    from (select * from run_agg where runs > 0 order by runs desc limit 10) a join names n on n.mid=a.mid), '[]'::jsonb),
  'most_wickets', coalesce((select jsonb_agg(jsonb_build_object('member_id',a.mid,'profile_id',n.pid,'name',n.name,'wickets',a.wkts) order by a.wkts desc)
    from (select * from wkt_agg where wkts > 0 order by wkts desc limit 10) a join names n on n.mid=a.mid), '[]'::jsonb),
  'most_catches', coalesce((select jsonb_agg(jsonb_build_object('member_id',a.mid,'profile_id',n.pid,'name',n.name,'dismissals',a.dis) order by a.dis desc)
    from (select * from field_agg where dis > 0 order by dis desc limit 10) a join names n on n.mid=a.mid), '[]'::jsonb),
  'most_fours', coalesce((select jsonb_agg(jsonb_build_object('member_id',a.mid,'profile_id',n.pid,'name',n.name,'fours',a.fours) order by a.fours desc)
    from (select * from run_agg where fours > 0 order by fours desc limit 10) a join names n on n.mid=a.mid), '[]'::jsonb),
  'most_sixes', coalesce((select jsonb_agg(jsonb_build_object('member_id',a.mid,'profile_id',n.pid,'name',n.name,'sixes',a.sixes) order by a.sixes desc)
    from (select * from run_agg where sixes > 0 order by sixes desc limit 10) a join names n on n.mid=a.mid), '[]'::jsonb)
);
$function$;

-- 73: the claim inbox queries guest_claim_requests with no team filter, leaving
-- the scoping entirely to RLS. There was no index on status, so the planner
-- seq-scanned the table and, for every pending row anyone on the platform had
-- ever filed, ran a correlated subquery plus a SECURITY DEFINER call. The first
-- branch also used a bare auth.uid(), which - unlike the newer policies here -
-- is re-evaluated per row instead of being hoisted into an InitPlan.
create index if not exists guest_claim_requests_pending_idx
  on public.guest_claim_requests (membership_id)
  where status = 'pending';

create index if not exists guest_claim_requests_requester_idx
  on public.guest_claim_requests (requested_by);

drop policy if exists guest_claims_select_requester_or_admin
  on public.guest_claim_requests;
create policy guest_claims_select_requester_or_admin
  on public.guest_claim_requests for select to authenticated
  using (
    requested_by = (select auth.uid())
    or public.is_team_admin(
         (select tm.team_id from public.team_members tm
           where tm.id = guest_claim_requests.membership_id))
  );
