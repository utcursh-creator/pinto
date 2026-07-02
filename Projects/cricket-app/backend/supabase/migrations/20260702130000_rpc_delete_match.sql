-- MTCH-2: let the match owner delete a casual match they created (a mistaken
-- setup, an abandoned game they don't want in history). FK cascade removes the
-- innings, deliveries and squad. A tournament match is NEVER deletable this way
-- - it is owned by the bracket and removing it would corrupt standings; the
-- organizer manages those through the tournament instead.
create or replace function public.delete_match(_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _owner uuid;
begin
  select owner_id into _owner from public.matches where id = _match_id;
  if not found then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _owner <> (select auth.uid()) then
    raise exception 'only the match owner can delete this match' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.tournament_matches where match_id = _match_id) then
    raise exception 'a tournament match cannot be deleted here' using errcode = 'P0001';
  end if;
  delete from public.matches where id = _match_id;
end; $$;
revoke all on function public.delete_match(uuid) from public;
grant execute on function public.delete_match(uuid) to authenticated;
