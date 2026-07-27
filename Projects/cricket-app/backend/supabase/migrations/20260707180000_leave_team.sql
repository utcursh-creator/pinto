-- MEDIUM (penetration review 2026-07-07, team-member-delete-fk-restrict):
-- "Leave this team" and "Remove this player" were a raw
--   delete from team_members where id = ...
-- Nine foreign keys point at that table with NO ACTION - match_squad, both
-- innings openers, and six delivery columns - so the moment a player has
-- appeared in a single match the delete raises 23503 and the button shows a raw
-- Postgres error, permanently. The people most likely to leave a team are
-- exactly the ones who have played for it, so in practice the feature never
-- worked for anyone it mattered to.
--
-- Deleting is also the wrong thing to want. Their innings, wickets and catches
-- are real, and the scorecard has to keep naming them. So leaving becomes a
-- STATE rather than an erasure, and the row is only truly deleted when there is
-- no history to protect.

alter table public.team_members
  add column if not exists left_at timestamptz;

comment on column public.team_members.left_at is
  'When this person left the team. Non-null rows are kept only so historical '
  'scorecards can still name them; they are not on the roster and hold no '
  'membership rights.';

-- A departure that leaves the row in place must also end the access the row
-- granted, or "leaving" is cosmetic - every policy in the schema reads these
-- two helpers.
create or replace function public.is_team_member(_team_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.team_members
    where team_id = _team_id and profile_id = auth.uid()
      and left_at is null
  );
$$;

create or replace function public.is_team_admin(_team_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.team_members
    where team_id = _team_id
      and profile_id = auth.uid()
      and role in ('captain', 'admin')
      and left_at is null
  );
$$;

-- Leave a team, or remove someone from it. Deletes outright when the person has
-- no history at all (no tombstone for someone who never played), otherwise
-- records the departure.
create or replace function public.leave_team(_membership_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  _uid uuid := (select auth.uid());
  _row public.team_members%rowtype;
  _has_history boolean;
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  select * into _row from public.team_members where id = _membership_id;
  if _row.id is null then
    raise exception 'that membership does not exist' using errcode = 'P0001';
  end if;
  if _row.left_at is not null then
    return; -- already gone; leaving twice is not an error
  end if;

  -- A team admin may remove anyone; anyone may remove themselves.
  -- coalesce, NOT a bare `not (...)`: a GUEST row has profile_id null, so the
  -- comparison yields NULL, `not NULL` is NULL, and the branch never fires -
  -- which would have let any authenticated user delete any guest from any team.
  if not coalesce(
       public.is_team_admin(_row.team_id) or _row.profile_id = _uid, false) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  -- A team with no captain has nobody who can add players, start a match or
  -- accept an invite - it is unusable and unrecoverable from inside the app.
  if _row.role = 'captain' and (
       select count(*) from public.team_members
        where team_id = _row.team_id and role = 'captain' and left_at is null
     ) <= 1 then
    raise exception 'hand the captaincy to someone else before leaving'
      using errcode = 'P0001';
  end if;

  select exists (
    select 1 from public.match_squad where team_member_id = _membership_id
    union all
    select 1 from public.innings
     where opening_striker_id = _membership_id
        or opening_non_striker_id = _membership_id
    union all
    select 1 from public.deliveries
     where bowler_id = _membership_id or striker_id = _membership_id
        or non_striker_id = _membership_id or dismissed_player_id = _membership_id
        or incoming_batter_id = _membership_id or fielder_id = _membership_id
  ) into _has_history;

  if _has_history then
    update public.team_members set left_at = now() where id = _membership_id;
  else
    delete from public.team_members where id = _membership_id;
  end if;
end; $$;
revoke all on function public.leave_team(uuid) from public;
grant execute on function public.leave_team(uuid) to authenticated;
