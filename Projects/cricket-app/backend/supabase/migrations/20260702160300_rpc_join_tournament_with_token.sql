-- Redeem a tournament join token: a team admin drops THEIR team into the
-- tournament. The is_team_admin(_team_id) check IS the entire consent boundary -
-- a signed-in user can only enter a team they administer, never a stranger's, so
-- a leaked token can at worst let someone add their OWN team (which the organizer
-- sees in setup and can remove). The tournament analogue of accept_invite.
create or replace function public.join_tournament_with_token(
  _invite_token text, _team_id uuid, _group_label text default 'A'
) returns void language plpgsql security definer set search_path = public as $$
declare _tid uuid; _tstatus public.tournament_status;
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- consent: only a team's own admin may enter that team (never derive the team
  -- from the token - the caller names it and must own it).
  if not public.is_team_admin(_team_id) then
    raise exception 'you must be an admin of the team you are entering' using errcode = 'P0001';
  end if;

  select tournament_id into _tid from public.tournament_invites
    where invite_token = _invite_token and status = 'pending';
  if _tid is null then
    raise exception 'invite not found or already used' using errcode = 'P0001';
  end if;

  select status into _tstatus from public.tournaments where id = _tid;
  if _tstatus <> 'setup' then
    raise exception 'registration is closed for this tournament' using errcode = 'P0001';
  end if;

  insert into public.tournament_teams(tournament_id, team_id, group_label, added_via)
  values (_tid, _team_id, _group_label, 'invite')
  on conflict (tournament_id, team_id) do update set group_label = excluded.group_label;

  update public.tournament_invites
    set status = 'accepted', redeemed_by = (select auth.uid()), redeemed_team_id = _team_id
    where invite_token = _invite_token;
end; $$;
revoke all on function public.join_tournament_with_token(text, uuid, text) from public;
grant execute on function public.join_tournament_with_token(text, uuid, text) to authenticated;
