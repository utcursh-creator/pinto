-- TEAM-13: a team page had no record - no W/L, no match history. One anon-safe
-- RPC returns the team's career line from completed matches (result jsonb is
-- the source of truth, same read as tournament standings).
create or replace function public.team_career_stats(_team_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  with played as (
    select result from public.matches
    where status = 'complete' and _team_id in (team_a_id, team_b_id)
  )
  select jsonb_build_object(
    'played', count(*),
    'won', count(*) filter (where (result->>'result_type') in
        ('win_by_runs','win_by_wickets','win_dls','win_vjd','conceded','forfeit','walkover','awarded')
      and (result->>'winner_team_id')::uuid = _team_id),
    'lost', count(*) filter (where (result->>'result_type') in
        ('win_by_runs','win_by_wickets','win_dls','win_vjd','conceded','forfeit','walkover','awarded')
      and (result->>'winner_team_id')::uuid <> _team_id),
    'tied', count(*) filter (where (result->>'result_type') in ('tie','tie_superover')),
    'no_result', count(*) filter (where (result->>'result_type') in ('no_result','abandoned')))
  from played;
$$;
revoke all on function public.team_career_stats(uuid) from public;
grant execute on function public.team_career_stats(uuid) to anon, authenticated;
