-- Round-robin within each group: one matches row (+ tournament_matches link) per
-- pairing. Runs as the organizer (SECURITY DEFINER), inserting matches directly
-- with scorer = organizer so the fixture is immediately scoreable via the normal
-- engine. Idempotent: refuses if any fixture already exists for the tournament.
create or replace function public.generate_group_fixtures(_tournament_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _t public.tournaments; _pair record; _mid uuid;
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  select * into _t from public.tournaments where id = _tournament_id;
  if _t.status <> 'setup' then
    raise exception 'tournament is not in setup' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.tournament_matches where tournament_id = _tournament_id) then
    raise exception 'fixtures already generated' using errcode = 'P0001';
  end if;

  for _pair in
    select a.team_id as team_a, b.team_id as team_b, a.group_label
    from public.tournament_teams a
    join public.tournament_teams b
      on a.tournament_id = b.tournament_id
     and a.group_label = b.group_label
     and a.team_id < b.team_id
    where a.tournament_id = _tournament_id
  loop
    insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id,
                               overs_limit, balls_per_over, ball_type, city, status)
    values (_pair.team_a, _pair.team_b, _t.organizer_id, _t.organizer_id,
            _t.overs_limit, _t.balls_per_over, _t.ball_type, _t.city, 'setup')
    returning id into _mid;
    insert into public.tournament_matches(match_id, tournament_id, stage, group_label)
    values (_mid, _tournament_id, 'group', _pair.group_label);
  end loop;

  update public.tournaments set status = 'group_stage' where id = _tournament_id;
end; $$;
revoke all on function public.generate_group_fixtures(uuid) from public;
grant execute on function public.generate_group_fixtures(uuid) to authenticated;
