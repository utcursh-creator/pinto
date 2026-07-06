-- MISS-5 (handle payoff): search finds players by @handle too, and returns the
-- handle so results can show it. New return column -> drop + recreate.
drop function public.search_players_and_teams(text);

create function public.search_players_and_teams(_query text)
returns table(kind text, id uuid, name text, subtitle text, photo_url text, handle text)
language sql security definer set search_path = public stable as $$
  (select 'player'::text, p.id, p.display_name, null::text, p.photo_url, p.handle
   from public.profiles p
   where length(coalesce(trim(_query), '')) >= 2
     and (p.display_name ilike '%' || trim(_query) || '%'
          or p.handle ilike '%' || ltrim(trim(_query), '@') || '%')
   order by (p.handle ilike ltrim(trim(_query), '@') || '%') desc, p.display_name
   limit 15)
  union all
  (select 'team'::text, t.id, t.name, t.city, t.logo_url, null::text
   from public.teams t
   where length(coalesce(trim(_query), '')) >= 2
     and t.name ilike '%' || trim(_query) || '%'
   order by t.name
   limit 15);
$$;
revoke all on function public.search_players_and_teams(text) from public;
grant execute on function public.search_players_and_teams(text) to authenticated;
