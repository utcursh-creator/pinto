create or replace function public.discover_posts(
  _lat float, _lng float, _radius_m float default 25000,
  _mode public.lf_mode default null, _max_overs int default null,
  _on_or_after timestamptz default null, _skill public.skill_level default null
) returns table (
  post_id uuid, author_id uuid, team_id uuid, mode public.lf_mode,
  title text, description text, place_label text, match_at timestamptz,
  overs int, skill public.skill_level, slots_needed int, created_at timestamptz, approx_m float
) language sql security definer set search_path = '' stable as $$
  select p.id, p.author_id, p.team_id, p.mode, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at,
         round(extensions.st_distance(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography) / 100.0) * 100 as approx_m
  from public.looking_for_posts p
  where p.status = 'open'
    and (p.expires_at is null or p.expires_at > now())
    and (_mode is null or p.mode = _mode)
    and (_max_overs is null or p.overs is null or p.overs <= _max_overs)
    and (_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)
    and (_skill is null or p.skill = _skill)
    and extensions.st_dwithin(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _radius_m)
  order by p.geog operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography;
$$;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level) to authenticated;
