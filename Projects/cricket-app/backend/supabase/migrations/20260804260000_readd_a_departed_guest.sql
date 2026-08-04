-- Whole-system review #2 (2026-07-28), finding 54: add_match_guest's
-- duplicate-name check ignores left_at, so a guest who has played for the club
-- and been removed can never be added to a match again.
--
-- leave_team tombstones rather than deletes a member with match history, and
-- the squad picker filters `left_at is null` - so the old row is invisible to
-- the picker while still blocking the name. The player is unaddable by either
-- route.

CREATE OR REPLACE FUNCTION public.add_match_guest(_match_id uuid, _team_id uuid, _guest_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _id uuid; _name text := trim(coalesce(_guest_name, ''));
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.matches
    where id = _match_id and _team_id in (team_a_id, team_b_id)
  ) then
    raise exception 'team is not in this match' using errcode = 'P0001';
  end if;
  if length(_name) < 1 then
    raise exception 'a guest needs a name' using errcode = 'P0001';
  end if;
  -- Only an ACTIVE member of this name is a clash. The check used to ignore
  -- left_at, so a guest who had played and then been removed - which leaves a
  -- TOMBSTONE, because match_squad and deliveries reference the membership -
  -- blocked their own re-adding forever. And the squad picker filters
  -- `left_at is null`, so the captain could not select the old row either: that
  -- player simply could not be put in a match for their own club again
  -- (whole-system review #2, finding 54).
  if exists (
    select 1 from public.team_members
    where team_id = _team_id and lower(guest_name) = lower(_name)
      and left_at is null
  ) then
    raise exception 'a guest with this name is already on the team' using errcode = 'P0001';
  end if;

  -- REVIVE the tombstone rather than making a second row of the same name.
  -- For a guest the app already treats the name as the identity - that is what
  -- the duplicate check above is - so a second "Ravi" on one team would both
  -- contradict that and split their record in half. Reviving keeps every
  -- innings they have played attached to them, exactly as accept_invite and
  -- respond_join_request do for a registered member.
  --
  -- The trade, stated plainly: two DIFFERENT guests of the same name on one
  -- team will be merged. That is the same assumption the duplicate check has
  -- always made, and splitting one person's career is the more likely harm in a
  -- club where the same eleven names recur.
  update public.team_members
     set left_at = null
   where team_id = _team_id and lower(guest_name) = lower(_name)
     and left_at is not null
     and profile_id is null
     and claimable
   returning id into _id;
  if _id is not null then return _id; end if;

  insert into public.team_members (team_id, guest_name)
  values (_team_id, _name)
  returning id into _id;
  return _id;
end; $function$;
