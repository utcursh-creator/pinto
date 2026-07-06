-- DISC-1 (last field, read paths): feed + detail surface the post's ball_type.
-- discover_posts gains a return column -> drop + recreate; post_detail is jsonb
-- so create or replace suffices.
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
  author_name text, team_name text, ball_type public.ball_type
) language sql security definer set search_path = '' stable as $$
  select p.id, p.author_id, p.team_id, p.mode, p.flair, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at, p.image_urls, p.link_url,
         round(extensions.st_distance(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography) / 100.0) * 100 as approx_m,
         pr.display_name as author_name, t.name as team_name, p.ball_type
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

create or replace function public.post_detail(_post_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'id', p.id, 'author_id', p.author_id, 'team_id', p.team_id,
    'mode', p.mode, 'flair', p.flair, 'title', p.title, 'description', p.description,
    'place_label', p.place_label, 'match_at', p.match_at, 'overs', p.overs,
    'skill', p.skill, 'slots_needed', p.slots_needed, 'status', p.status,
    'image_urls', p.image_urls, 'link_url', p.link_url, 'ball_type', p.ball_type,
    'author_name', pr.display_name, 'team_name', t.name)
  from public.looking_for_posts p
  left join public.profiles pr on pr.id = p.author_id
  left join public.teams t on t.id = p.team_id
  where p.id = _post_id;
$$;
revoke all on function public.post_detail(uuid) from public;
grant execute on function public.post_detail(uuid) to authenticated;
