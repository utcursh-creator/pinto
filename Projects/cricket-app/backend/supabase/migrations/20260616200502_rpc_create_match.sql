create or replace function public.create_match(
  _team_a uuid, _team_b uuid, _overs int,
  _balls_per_over int default 6, _rules jsonb default '{}'::jsonb,
  _venue text default null, _city text default null, _ball_type public.ball_type default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,rules,venue,city,ball_type)
  values (_team_a,_team_b,_uid,_uid,_overs,_balls_per_over,_rules,_venue,_city,_ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) from public;
grant execute on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) to authenticated;
