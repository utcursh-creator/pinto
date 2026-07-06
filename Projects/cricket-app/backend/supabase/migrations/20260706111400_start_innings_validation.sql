-- SCOR-10/14 residue: start_innings validates server-side instead of trusting
-- the wizard. Distinct openers always; when the match declared squads for BOTH
-- sides (the wizard path always does), the openers must be IN the batting squad
-- and both sides need >= 2 players. Single-sided/absent squads skip the checks:
-- quick matches and the stats fixtures legitimately track only one roster.
-- Also accepts the 'innings_break' -> 'live' transition for the second innings
-- (SCOR-1 residue).
create or replace function public.start_innings(
  _match_id uuid, _innings_number int, _batting_team uuid, _bowling_team uuid,
  _opening_striker uuid, _opening_non_striker uuid, _target int default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _bat_n int; _bowl_n int;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  if _opening_striker = _opening_non_striker then
    raise exception 'the two openers must be different batters' using errcode = 'P0001';
  end if;

  select count(*) filter (where team_id = _batting_team),
         count(*) filter (where team_id = _bowling_team)
    into _bat_n, _bowl_n
  from public.match_squad where match_id = _match_id;
  if _bat_n > 0 and _bowl_n > 0 then
    if _bat_n < 2 or _bowl_n < 2 then
      raise exception 'both squads need at least 2 players' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.match_squad where match_id = _match_id
                     and team_id = _batting_team and team_member_id = _opening_striker)
       or not exists (select 1 from public.match_squad where match_id = _match_id
                     and team_id = _batting_team and team_member_id = _opening_non_striker) then
      raise exception 'both openers must be in the batting squad' using errcode = 'P0001';
    end if;
  end if;

  insert into public.innings(match_id,innings_number,batting_team_id,bowling_team_id,opening_striker_id,opening_non_striker_id,target)
  values (_match_id,_innings_number,_batting_team,_bowling_team,_opening_striker,_opening_non_striker,_target)
  returning id into _id;
  update public.matches set status = 'live' where id = _match_id and status in ('setup','innings_break');
  return _id;
end; $$;
revoke all on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) from public;
grant execute on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) to authenticated;
