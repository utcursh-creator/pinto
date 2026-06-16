create or replace function public.set_my_location(_lat float, _lng float, _label text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  insert into public.profile_locations(profile_id, geog, place_label, updated_at)
  values (_uid, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _label, now())
  on conflict (profile_id) do update set geog = excluded.geog, place_label = excluded.place_label, updated_at = now();
end; $$;

create or replace function public.set_team_location(_team_id uuid, _lat float, _lng float, _label text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.team_locations(team_id, geog, place_label, updated_at)
  values (_team_id, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _label, now())
  on conflict (team_id) do update set geog = excluded.geog, place_label = excluded.place_label, updated_at = now();
end; $$;

revoke all on function public.set_my_location(float,float,text) from public;
revoke all on function public.set_team_location(uuid,float,float,text) from public;
grant execute on function public.set_my_location(float,float,text) to authenticated;
grant execute on function public.set_team_location(uuid,float,float,text) to authenticated;
