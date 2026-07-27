-- CRITICAL (penetration review 2026-07-07, completeness critic):
-- Every invite-joined team is stranded in group 'A' and the organizer cannot move
-- it, so a tournament assembled the SANCTIONED (SEC-8 consent) way can never be
-- split into groups - and with every team in one group, the whole multi-group
-- format is unreachable.
--
-- Mechanism: join_tournament_with_token defaults `_group_label` to 'A'
-- (20260702160300:7). The organizer's group chips in Manage tournament call
-- add_tournament_team, which carries the SEC-8 gate `is_team_admin(_team_id)`
-- (20260702150000:14). The organizer is NOT an admin of an invited club's team, so
-- every chip tap raises 'you must be an admin of this team to enter it' - and
-- _setGroup has no catch, so the tap silently does nothing, forever.
--
-- The SEC-8 gate is correct for ENTERING a team (consent to participate). It is
-- wrong for PLACING a team that is already in the tournament: placement is the
-- organizer's job in the CricHeroes model we reverse-engineered, and consent was
-- already given when the team redeemed the invite. Splitting the two operations is
-- the root fix - not weakening add_tournament_team.
create or replace function public.set_tournament_team_group(
  _tournament_id uuid, _team_id uuid, _group_label text
) returns void language plpgsql security definer set search_path = public as $$
declare _label text := upper(nullif(trim(_group_label), ''));
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if _label is null or _label !~ '^[A-Z]$' then
    raise exception 'a group label must be a single letter' using errcode = 'P0001';
  end if;
  if (select status from public.tournaments where id = _tournament_id) <> 'setup' then
    raise exception 'groups are fixed once the tournament starts' using errcode = 'P0001';
  end if;
  -- placement only: the team must ALREADY be in the tournament (consent given by
  -- redeeming an invite, or by an admin entering it). This RPC can never enrol.
  update public.tournament_teams set group_label = _label
   where tournament_id = _tournament_id and team_id = _team_id;
  if not found then
    raise exception 'that team is not in this tournament' using errcode = 'P0001';
  end if;
end; $$;
revoke all on function public.set_tournament_team_group(uuid, uuid, text) from public;
grant execute on function public.set_tournament_team_group(uuid, uuid, text) to authenticated;
