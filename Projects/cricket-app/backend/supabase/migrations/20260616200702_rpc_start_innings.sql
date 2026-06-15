create or replace function public.start_innings(
  _match_id uuid, _innings_number int, _batting_team uuid, _bowling_team uuid,
  _opening_striker uuid, _opening_non_striker uuid, _target int default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  insert into public.innings(match_id,innings_number,batting_team_id,bowling_team_id,opening_striker_id,opening_non_striker_id,target)
  values (_match_id,_innings_number,_batting_team,_bowling_team,_opening_striker,_opening_non_striker,_target)
  returning id into _id;
  update public.matches set status = 'live' where id = _match_id and status = 'setup';
  return _id;
end; $$;
revoke all on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) from public;
grant execute on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) to authenticated;
