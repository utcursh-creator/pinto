-- Found while reading the match-setup path (fix run 2026-07-07):
-- `matches.overs_limit` is `int not null` with NO check constraint, and
-- create_match passes whatever it is handed straight into the insert. The Overs
-- box on Start-a-match is a plain numeric TextField, so a scorer who types 0
-- (or leans on the minus key) gets a match whose innings is already over:
-- `max_legal` is 0, so the fold closes the innings on the first delivery, and
-- there is no route out of a started match. Negative overs are worse - every
-- comparison in the fold is then against a negative bound.
--
-- The guard belongs on the server, in two layers:
--   * a readable P0001 from the RPC, so the app can show the reason
--   * a check constraint, so a direct PostgREST insert cannot go around the RPC
--
-- Bounds: 1..100 overs (a 90-over red-ball innings is legitimate; nothing
-- beyond 100 is a real fixture) and 1..12 balls per over (six is standard,
-- eight was historically used, anything past a dozen is a typo).

-- Nothing should violate these, but clamp first so the constraint cannot fail
-- to apply on an existing database.
update public.matches set overs_limit = 1 where overs_limit < 1;
update public.matches set overs_limit = 100 where overs_limit > 100;
update public.matches set balls_per_over = 6
 where balls_per_over is null or balls_per_over < 1 or balls_per_over > 12;

alter table public.matches
  add constraint matches_overs_limit_sane check (overs_limit between 1 and 100),
  add constraint matches_balls_per_over_sane check (balls_per_over between 1 and 12);

create or replace function public.create_match(
  _team_a uuid, _team_b uuid, _overs int,
  _balls_per_over int default 6, _rules jsonb default '{}'::jsonb,
  _venue text default null, _city text default null, _ball_type public.ball_type default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  -- SEC-5: the caller must be an admin of one of the participating teams.
  if not (public.is_team_admin(_team_a) or public.is_team_admin(_team_b)) then
    raise exception 'must be an admin of one of the participating teams' using errcode = 'P0001';
  end if;
  if _overs is null or _overs < 1 or _overs > 100 then
    raise exception 'overs must be between 1 and 100' using errcode = 'P0001';
  end if;
  if _balls_per_over is null or _balls_per_over < 1 or _balls_per_over > 12 then
    raise exception 'balls per over must be between 1 and 12' using errcode = 'P0001';
  end if;
  insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,rules,venue,city,ball_type)
  values (_team_a,_team_b,_uid,_uid,_overs,_balls_per_over,_rules,_venue,_city,_ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) from public;
grant execute on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) to authenticated;
