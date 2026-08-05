-- Review #3 (MEDIUM), finding 12: the team page's "Add guest" splits a
-- returning guest's career where the match squads screen's identically-labelled
-- button revives them.
--
-- 20260804260000 fixed this shape for add_match_guest. add_guest_member had
-- already been given the OTHER half of the same fix - 20260707200000 added
-- `and left_at is null` to its duplicate check - and never got the revive. On
-- its own that filter is worse than nothing: it turns a hard, visible block
-- ("already on the team") into a SILENT SPLIT. The check no longer sees the
-- tombstone, so it inserts a second row of the same name.
--
-- The guest career page is keyed on team_members.id and teamRosterProvider
-- filters `left_at is null`, so the returning player reads as a debutant with
-- zero matches while every innings they actually played hangs off a row nothing
-- in the app can reach. And it is PERMANENT: with an active row of that name
-- present, add_match_guest - the path that WOULD have merged them - starts
-- raising 'a guest with this name is already on the team'. There is no
-- un-tombstone verb anywhere.
--
-- Two live buttons with the same label and opposite irreversible outcomes. This
-- is the third time one reader has filtered left_at while its sibling did not.
create or replace function public.add_guest_member(_team_id uuid, _guest_name text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
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
end;
$function$;
