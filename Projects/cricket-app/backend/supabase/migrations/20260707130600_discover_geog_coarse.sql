-- HIGH (penetration review 2026-07-07, discover-posts-location-oracle):
-- discover_posts was a sub-metre location oracle. The 100 m rounding of
-- `approx_m` coarsens only the DISPLAYED number - the caller also chooses the
-- probe origin and an unclamped _radius_m, and the function filters and orders
-- against the RAW geog. Binary-searching _radius_m from three probe points
-- recovers a poster's exact coordinates, which for most users is their home.
-- The hosted database has real users with real saved GPS.
--
-- Narrowing the ladder is not enough: as long as an exact-distance predicate
-- over the raw point is reachable with a caller-chosen origin, the oracle
-- exists. The fix is to quantise AT WRITE TIME and never expose the true point
-- to the query path at all.
alter table public.looking_for_posts
  add column geog_coarse extensions.geography(Point,4326);

-- ~500 m grid. 0.005 degrees of latitude is ~555 m; longitude cells narrow with
-- latitude, which is acceptable - the cell only ever gets smaller in the
-- east-west direction, never below the privacy floor in the north-south one.
create or replace function public._snap_geog(_lat float, _lng float)
returns extensions.geography language sql immutable set search_path = '' as $$
  select extensions.st_setsrid(extensions.st_makepoint(
           round((_lng / 0.005)::numeric)::float * 0.005,
           round((_lat / 0.005)::numeric)::float * 0.005), 4326)::extensions.geography;
$$;

update public.looking_for_posts
   set geog_coarse = public._snap_geog(
         extensions.st_y(geog::extensions.geometry),
         extensions.st_x(geog::extensions.geometry))
 where geog is not null;

create index looking_for_posts_geog_coarse_idx
  on public.looking_for_posts using gist (geog_coarse);

-- write path stamps it
create or replace function public.create_looking_for_post(
  _mode public.lf_mode, _flair public.lf_flair, _lat float, _lng float, _description text default null,
  _team_id uuid default null, _title text default null, _match_at timestamptz default null,
  _overs int default null, _skill public.skill_level default null, _slots_needed int default null,
  _place_label text default null, _expires_at timestamptz default null,
  _image_urls text[] default null, _link_url text default null, _ball_type public.ball_type default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid()); _id uuid;
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _team_id is not null and not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.looking_for_posts(author_id, team_id, mode, flair, title, description, geog, geog_coarse, place_label, match_at, overs, skill, slots_needed, expires_at, image_urls, link_url, ball_type)
  values (_uid, _team_id, _mode, _flair, _title, _description,
          extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography,
          public._snap_geog(_lat, _lng),
          _place_label, _match_at, _overs, _skill, _slots_needed, _expires_at,
          coalesce(_image_urls, '{}'), _link_url, _ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) to authenticated;

-- read path never touches the true point, and the caller's probe + radius are
-- both quantised so repeated probing cannot narrow anything below the grid.
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
  with probe as (
    select public._snap_geog(_lat, _lng) g,
           -- clamp + quantise the radius to a 1 km ladder between 2 km and 50 km
           greatest(least(round(coalesce(_radius_m, 25000) / 1000.0) * 1000.0, 50000), 2000) r
  )
  select p.id, p.author_id, p.team_id, p.mode, p.flair, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at, p.image_urls, p.link_url,
         round(extensions.st_distance(p.geog_coarse, probe.g) / 100.0) * 100 as approx_m,
         pr.display_name as author_name, t.name as team_name, p.ball_type
  from public.looking_for_posts p
  cross join probe
  left join public.profiles pr on pr.id = p.author_id
  left join public.teams t on t.id = p.team_id
  where p.status = 'open'
    and (p.expires_at is null or p.expires_at > now())
    and (_mode is null or p.mode = _mode)
    and (_max_overs is null or p.overs is null or p.overs <= _max_overs)
    and (_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)
    and (_skill is null or p.skill = _skill)
    and (_flair is null or p.flair = _flair)
    and extensions.st_dwithin(p.geog_coarse, probe.g, probe.r)
  order by p.geog_coarse operator(extensions.<->) (select g from probe);
$$;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) to authenticated;
