-- Per-group standings, re-folded from completed group matches (the scoring
-- engine is the single source of truth, so standings stay correct after any
-- score correction). Points: win 2, tie/no-result 1, loss 0. NRR = runs_for/
-- overs_for - runs_against/overs_against, where a side bowled out counts its
-- FULL over quota (ICC rule), not the overs it actually faced. Tiebreak:
-- points -> NRR -> head-to-head (wins vs a peer on identical points+NRR) ->
-- team name. Returns {groups:[{group_label, rows:[...]}]}. Only teams that have
-- played a completed group match appear (v1).
create or replace function public.tournament_standings(_tournament_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
with gm as (
  select tm.match_id, tm.group_label, m.team_a_id, m.team_b_id, m.overs_limit, m.result
  from public.tournament_matches tm
  join public.matches m on m.id = tm.match_id
  where tm.tournament_id = _tournament_id and tm.stage = 'group' and m.status = 'complete'
),
inn as (
  select g.match_id, g.group_label, g.team_a_id, g.team_b_id, g.overs_limit,
         i.batting_team_id, s.runs, s.legal_balls, s.wkts_rem
  from gm g
  join public.innings i on i.match_id = g.match_id
  cross join lateral (
    select (st->>'runs')::int as runs,
           (st->>'legal_balls')::int as legal_balls,
           (st->>'wickets_remaining')::int as wkts_rem
    from (select public.compute_innings_state(i.id) as st) z
  ) s
),
contrib as (
  select group_label, batting_team_id as team_id,
         runs as rf, (case when wkts_rem = 0 then overs_limit else legal_balls / 6.0 end) as ofv,
         0 as ra, 0::numeric as oav
  from inn
  union all
  select group_label,
         case when batting_team_id = team_a_id then team_b_id else team_a_id end,
         0, 0::numeric,
         runs, (case when wkts_rem = 0 then overs_limit else legal_balls / 6.0 end)
  from inn
),
nrr as (
  select group_label, team_id, sum(rf) rf, sum(ofv) ofv, sum(ra) ra, sum(oav) oav
  from contrib group by group_label, team_id
),
perteam as (
  select g.group_label, t.team_id,
    count(*) as played,
    count(*) filter (where (g.result->>'result_type') in
        ('win_by_runs','win_by_wickets','win_dls','win_vjd','conceded','forfeit','walkover','awarded')
      and (g.result->>'winner_team_id')::uuid = t.team_id) as won,
    count(*) filter (where (g.result->>'result_type') in
        ('win_by_runs','win_by_wickets','win_dls','win_vjd','conceded','forfeit','walkover','awarded')
      and (g.result->>'winner_team_id')::uuid <> t.team_id) as lost,
    count(*) filter (where (g.result->>'result_type') in ('tie','tie_superover')) as tied,
    count(*) filter (where (g.result->>'result_type') in ('no_result','abandoned')) as no_result
  from gm g cross join lateral (values (g.team_a_id),(g.team_b_id)) as t(team_id)
  group by g.group_label, t.team_id
),
rows as (
  select p.group_label, p.team_id, tm.name,
    p.played, p.won, p.lost, p.tied, p.no_result,
    (p.won * 2 + p.tied + p.no_result) as points,
    round(n.rf / nullif(n.ofv, 0) - n.ra / nullif(n.oav, 0), 3) as nrr
  from perteam p
  join nrr n on n.group_label = p.group_label and n.team_id = p.team_id
  join public.teams tm on tm.id = p.team_id
),
h2h as (
  select r.group_label, r.team_id,
    count(*) filter (where (g.result->>'winner_team_id')::uuid = r.team_id) as wins
  from rows r
  join gm g on g.group_label = r.group_label and (g.team_a_id = r.team_id or g.team_b_id = r.team_id)
  join rows r2 on r2.group_label = r.group_label
    and r2.team_id = (case when g.team_a_id = r.team_id then g.team_b_id else g.team_a_id end)
    and r2.team_id <> r.team_id and r2.points = r.points and r2.nrr is not distinct from r.nrr
  group by r.group_label, r.team_id
),
ranked as (
  select r.*, coalesce(h.wins, 0) as h2h from rows r
  left join h2h h on h.group_label = r.group_label and h.team_id = r.team_id
)
select jsonb_build_object('groups', coalesce(jsonb_agg(
    jsonb_build_object('group_label', group_label, 'rows', rows_json) order by group_label), '[]'::jsonb))
from (
  select group_label, jsonb_agg(jsonb_build_object(
      'team_id', team_id, 'name', name, 'played', played, 'won', won, 'lost', lost,
      'tied', tied, 'no_result', no_result, 'points', points, 'nrr', nrr)
      order by points desc, nrr desc nulls last, h2h desc, name asc) as rows_json
  from ranked group by group_label
) z;
$$;
revoke all on function public.tournament_standings(uuid) from public;
grant execute on function public.tournament_standings(uuid) to anon, authenticated;
