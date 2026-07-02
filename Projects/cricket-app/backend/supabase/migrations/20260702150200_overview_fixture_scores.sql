-- TOUR-6: the public fixture/bracket tiles could not show who won or the
-- scoreline - overview returned the result jsonb (winner + margin note) but not
-- the two innings scores. Add an `innings` array per fixture (innings_number,
-- batting_team_id, runs, wickets from the fold) so the UI can render
-- "A 152/6 beat B 134 by 18 runs". Everything else is unchanged.
create or replace function public.tournament_overview(_tournament_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'tournament', (select to_jsonb(t) from (
        select id, name, status, overs_limit, balls_per_over, ball_type,
               group_count, qualifiers_per_group, champion_team_id, city, venue, starts_on, ends_on
        from public.tournaments where id = _tournament_id) t),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'team_id', tt.team_id, 'name', tm.name, 'group_label', tt.group_label)
        order by tt.group_label, tm.name)
      from public.tournament_teams tt join public.teams tm on tm.id = tt.team_id
      where tt.tournament_id = _tournament_id), '[]'::jsonb),
    'standings', public.tournament_standings(_tournament_id),
    'fixtures', coalesce((select jsonb_agg(jsonb_build_object(
        'match_id', x.match_id, 'stage', x.stage, 'group_label', x.group_label,
        'bracket_slot', x.bracket_slot, 'team_a', x.ta, 'team_b', x.tb,
        'team_a_id', x.team_a_id, 'team_b_id', x.team_b_id,
        'status', x.status, 'scheduled_at', x.scheduled_at, 'venue', x.venue, 'result', x.result,
        'innings', coalesce((
          select jsonb_agg(jsonb_build_object(
              'innings_number', i.innings_number,
              'batting_team_id', i.batting_team_id,
              'runs', (st->>'runs')::int,
              'wickets', (st->>'wickets')::int)
            order by i.innings_number)
          from public.innings i
          cross join lateral (select public.compute_innings_state(i.id) as st) z
          where i.match_id = x.match_id), '[]'::jsonb))
        order by x.stage, x.group_label nulls last, x.bracket_slot nulls last)
      from (
        select tm.match_id, tm.stage, tm.group_label, tm.bracket_slot,
               m.status, m.scheduled_at, m.venue, m.result,
               m.team_a_id, m.team_b_id, ta.name ta, tb.name tb
        from public.tournament_matches tm
        join public.matches m on m.id = tm.match_id
        join public.teams ta on ta.id = m.team_a_id
        join public.teams tb on tb.id = m.team_b_id
        where tm.tournament_id = _tournament_id) x), '[]'::jsonb),
    'leaderboard', public.tournament_leaderboard(_tournament_id),
    'champion_team_id', (select champion_team_id from public.tournaments where id = _tournament_id)
  );
$$;
revoke all on function public.tournament_overview(uuid) from public;
grant execute on function public.tournament_overview(uuid) to anon, authenticated;
