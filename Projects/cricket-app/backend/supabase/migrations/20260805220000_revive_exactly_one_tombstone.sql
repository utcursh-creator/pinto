-- Code review (2026-08-05): the revive block in add_match_guest (20260804260000)
-- and add_guest_member (20260805190000) updates EVERY tombstoned row of that
-- name on the team. plpgsql's `RETURNING ... INTO` is STRICT for multiple rows,
-- so with two tombstones the call raises `query returned more than one row` and
-- the transaction aborts: "Add guest player" is permanently broken for that
-- team + name, showing a raw Postgres error, with no way round it in the app.
--
-- The reviewer predicted a silent two-active-rows split. It is louder than
-- that, and worse for the captain, who simply cannot add the player back.
--
-- Reachable from legacy data only: the OLD add_guest_member INSERTED a
-- duplicate instead of reviving - the very bug 20260805190000 fixed - so a team
-- that collected two same-named guests before that migration, and lost both, is
-- now stuck. Hosted has 0 teams in this shape today (checked); this closes it
-- before it can happen.
--
-- Most recently departed wins: that is the guest the captain means.
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
  -- EXACTLY ONE row. The unscoped form updated every tombstone of that name,
  -- and plpgsql's `RETURNING ... INTO` is STRICT for multiple rows, so the call
  -- died with `query returned more than one row` and the whole transaction
  -- aborted - "Add guest player" permanently broken for that team + name, with
  -- a raw Postgres error on screen. Reachable from legacy data, because the OLD
  -- add_guest_member inserted duplicates instead of reviving.
  -- Most recently departed wins: that is the one the captain means.
  update public.team_members
     set left_at = null
   where id = (
     select id from public.team_members
      where team_id = _team_id and lower(guest_name) = lower(_name)
     and left_at is not null
     and profile_id is null
     and claimable
        order by left_at desc nulls last, id
        limit 1)
   returning id into _id;
  if _id is not null then return _id; end if;

  insert into public.team_members (team_id, guest_name)
  values (_team_id, _name)
  returning id into _id;
  return _id;
end; $function$


;
CREATE OR REPLACE FUNCTION public.add_guest_member(_team_id uuid, _guest_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  _id uuid; _name text := trim(coalesce(_guest_name, ''));
begin
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if length(_name) < 1 then
    raise exception 'a guest needs a name' using errcode = 'P0001';
  end if;
  -- Only an ACTIVE member of this name is a clash.
  if exists (
    select 1 from public.team_members
    where team_id = _team_id and lower(guest_name) = lower(_name)
      and left_at is null
  ) then
    raise exception 'a guest with this name is already on the team' using errcode = 'P0001';
  end if;

  -- REVIVE the tombstone rather than making a second row of the same name -
  -- identical to add_match_guest, deliberately, because they are two buttons
  -- for one act. For a guest the app already treats the name as the identity
  -- (that is exactly what the duplicate check above is), so a second "Ravi" on
  -- one team both contradicts that and splits their record in half.
  --
  -- The trade, stated plainly: two DIFFERENT guests of the same name on one
  -- team will be merged. That is the same assumption the duplicate check has
  -- always made, and splitting one person's career is the more likely harm in a
  -- club where the same eleven names recur.
  -- EXACTLY ONE row. The unscoped form updated every tombstone of that name,
  -- and plpgsql's `RETURNING ... INTO` is STRICT for multiple rows, so the call
  -- died with `query returned more than one row` and the whole transaction
  -- aborted - "Add guest player" permanently broken for that team + name, with
  -- a raw Postgres error on screen. Reachable from legacy data, because the OLD
  -- add_guest_member inserted duplicates instead of reviving.
  -- Most recently departed wins: that is the one the captain means.
  update public.team_members
     set left_at = null
   where id = (
     select id from public.team_members
      where team_id = _team_id and lower(guest_name) = lower(_name)
     and left_at is not null
     and profile_id is null
     and claimable
        order by left_at desc nulls last, id
        limit 1)
   returning id into _id;
  if _id is not null then return _id; end if;

  insert into public.team_members (team_id, guest_name)
  values (_team_id, _name)
  returning id into _id;

  return _id;
end;
$function$


;
