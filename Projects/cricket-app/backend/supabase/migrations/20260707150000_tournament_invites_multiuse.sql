-- MEDIUM (penetration review 2026-07-07): the tournament join link is the exact
-- bug that was already fixed for TEAM invites, left unfixed in its clone.
-- An organizer taps "Invite a team" once and drops the link in a WhatsApp group
-- of six clubs. Club 1 redeems it; clubs 2-6 all get "already used or no longer
-- valid" and the organizer gets no signal that anything went wrong. The token
-- also never expired, and it was read WITHOUT a row lock, so two admins tapping
-- at the same moment could both redeem a single-use token.
alter table public.tournament_invites
  add column expires_at timestamptz not null default (now() + interval '7 days');
alter table public.tournament_invites add column max_uses int;
alter table public.tournament_invites add column uses int not null default 0;

-- Multi-use, expiring, and row-locked. Returns the tournament id (unchanged
-- contract). Re-redeeming for a team already entered burns no use.
create or replace function public.join_tournament_with_token(
  _invite_token text, _team_id uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  _tid uuid; _status public.invite_status; _exp timestamptz; _uses int; _max int;
  _existed boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- the redeeming admin's own team-admin right IS the consent (SEC-8)
  if not public.is_team_admin(_team_id) then
    raise exception 'you must be an admin of this team to enter it' using errcode = 'P0001';
  end if;

  -- FOR UPDATE: without the lock two admins could both redeem one token
  select tournament_id, status, expires_at, uses, max_uses
    into _tid, _status, _exp, _uses, _max
  from public.tournament_invites
   where invite_token = _invite_token
   for update;

  if _tid is null or _status <> 'pending' then
    raise exception 'invite not found or already used' using errcode = 'P0001';
  end if;
  if _exp <= now() then
    raise exception 'invite expired' using errcode = 'P0001';
  end if;
  if _max is not null and _uses >= _max then
    raise exception 'invite fully used' using errcode = 'P0001';
  end if;
  if (select status from public.tournaments where id = _tid) <> 'setup' then
    raise exception 'tournament is not in setup' using errcode = 'P0001';
  end if;

  select exists (
    select 1 from public.tournament_teams
     where tournament_id = _tid and team_id = _team_id
  ) into _existed;

  insert into public.tournament_teams(tournament_id, team_id, group_label, added_via)
  values (_tid, _team_id, 'A', 'invite')
  on conflict (tournament_id, team_id) do nothing;

  -- only a genuinely NEW entrant consumes a use; the link stays live for the
  -- rest of the group so one share reaches every club
  if not _existed then
    update public.tournament_invites
       set uses = uses + 1,
           redeemed_by = (select auth.uid()),
           redeemed_team_id = _team_id
     where invite_token = _invite_token;
  end if;

  return _tid;
end; $$;
revoke all on function public.join_tournament_with_token(text, uuid) from public;
grant execute on function public.join_tournament_with_token(text, uuid) to authenticated;
