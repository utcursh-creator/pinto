-- MISS-3: find a player or team by name. Case-insensitive substring match over
-- profiles.display_name + teams.name. SECURITY DEFINER + returns only public-safe
-- columns (display_name/photo for players - like public_profile_minimal; never
-- phone/city/role; name/city/logo for teams). Requires >= 2 query chars.
create or replace function public.search_players_and_teams(_query text)
returns table(kind text, id uuid, name text, subtitle text, photo_url text)
language sql security definer set search_path = public stable as $$
  (select 'player'::text, p.id, p.display_name, null::text, p.photo_url
   from public.profiles p
   where length(coalesce(trim(_query), '')) >= 2
     and p.display_name ilike '%' || trim(_query) || '%'
   order by p.display_name
   limit 15)
  union all
  (select 'team'::text, t.id, t.name, t.city, t.logo_url
   from public.teams t
   where length(coalesce(trim(_query), '')) >= 2
     and t.name ilike '%' || trim(_query) || '%'
   order by t.name
   limit 15);
$$;
revoke all on function public.search_players_and_teams(text) from public;
grant execute on function public.search_players_and_teams(text) to authenticated;
