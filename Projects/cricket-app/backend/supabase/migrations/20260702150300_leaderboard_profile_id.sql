-- TOUR-7 / STAT-1: expose profile_id on every leaderboard row so the UI can link
-- a claimed player to /player/:profileId (guests have a null profile_id and stay
-- non-tappable). Keyed by team_members.id as before; only adds profile_id.
create or replace function public.tournament_leaderboard(_tournament_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
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
names as (
  select tmem.id mid, tmem.profile_id pid, coalesce(tmem.guest_name, p.display_name, 'Player') name
  from public.team_members tmem left join public.profiles p on p.id = tmem.profile_id
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
$$;
revoke all on function public.tournament_leaderboard(uuid) from public;
grant execute on function public.tournament_leaderboard(uuid) to anon, authenticated;
