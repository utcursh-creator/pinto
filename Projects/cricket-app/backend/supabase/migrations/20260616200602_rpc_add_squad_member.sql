create or replace function public.add_squad_member(
  _match_id uuid, _team_id uuid, _team_member_id uuid,
  _batting_order int default null, _is_captain boolean default false, _is_keeper boolean default false
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  insert into public.match_squad(match_id,team_id,team_member_id,batting_order,is_captain,is_wicket_keeper)
  values (_match_id,_team_id,_team_member_id,_batting_order,_is_captain,_is_keeper)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) from public;
grant execute on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) to authenticated;
