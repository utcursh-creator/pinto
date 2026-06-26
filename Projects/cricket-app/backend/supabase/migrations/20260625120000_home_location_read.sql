-- Self-readable home location. The location tables are never broadly client-
-- readable (privacy: no player-to-player trilateration), but a user reading
-- their OWN home base, and a member reading their team's ground, is safe and
-- needed by the client (to default the discover anchor + show the saved point).
-- The geog column is PostGIS binary, so these return decoded lat/lng.
create or replace function public.my_home_location()
returns table(lat float, lng float, label text)
language sql security definer set search_path = '' stable as $$
  select extensions.st_y(geog::extensions.geometry),
         extensions.st_x(geog::extensions.geometry),
         place_label
  from public.profile_locations
  where profile_id = (select auth.uid());
$$;

create or replace function public.team_home_location(_team_id uuid)
returns table(lat float, lng float, label text)
language plpgsql security definer set search_path = '' stable as $$
begin
  if not public.is_team_member(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  return query
    select extensions.st_y(geog::extensions.geometry),
           extensions.st_x(geog::extensions.geometry),
           place_label
    from public.team_locations
    where team_id = _team_id;
end; $$;

revoke all on function public.my_home_location() from public;
revoke all on function public.team_home_location(uuid) from public;
grant execute on function public.my_home_location() to authenticated;
grant execute on function public.team_home_location(uuid) to authenticated;
