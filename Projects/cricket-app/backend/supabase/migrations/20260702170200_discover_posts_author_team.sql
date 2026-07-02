-- DISC-5: the feed cards showed neither the poster's name nor their team.
-- discover_posts now joins profiles.display_name + teams.name so the card can
-- render "Posted by X (Team Y)". Still SECURITY DEFINER + returns only the
-- coarsened approx_m, never geog (SEC-2). DROP+CREATE for the new return shape.
drop function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair);

create function public.discover_posts(
  _lat float, _lng float, _radius_m float default 25000,
  _mode public.lf_mode default null, _max_overs int default null,
  _on_or_after timestamptz default null, _skill public.skill_level default null,
  _flair public.lf_flair default null
) returns table (
  post_id uuid, author_id uuid, team_id uuid, mode public.lf_mode, flair public.lf_flair,
  title text, description text, place_label text, match_at timestamptz,
  overs int, skill public.skill_level, slots_needed int, created_at timestamptz,
  image_urls text[], link_url text, approx_m float,
  author_name text, team_name text
) language sql security definer set search_path = '' stable as $$
  select p.id, p.author_id, p.team_id, p.mode, p.flair, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at, p.image_urls, p.link_url,
         round(extensions.st_distance(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography) / 100.0) * 100 as approx_m,
         pr.display_name as author_name, t.name as team_name
  from public.looking_for_posts p
  left join public.profiles pr on pr.id = p.author_id
  left join public.teams t on t.id = p.team_id
  where p.status = 'open'
    and (p.expires_at is null or p.expires_at > now())
    and (_mode is null or p.mode = _mode)
    and (_max_overs is null or p.overs is null or p.overs <= _max_overs)
    and (_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)
    and (_skill is null or p.skill = _skill)
    and (_flair is null or p.flair = _flair)
    and extensions.st_dwithin(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _radius_m)
  order by p.geog operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography;
$$;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) to authenticated;
