-- MEDIUM (penetration review 2026-07-07, discover-posts-never-expire):
-- `looking_for_posts.expires_at` was nullable with no default and NO CLIENT PATH
-- ever wrote it, so in practice every post lived forever. Combined with the feed
-- having no match-date floor, Discover accumulates dead ads indefinitely: "Need
-- 2 players, Sat 3pm" from last year still shows to everyone within 25 km, and
-- because the ordering is purely by distance a stale nearby post outranks a
-- fresh one further away. The headline feature silts up on its own.
--
-- Three cheap changes, all server-side so no app update is needed:
--   1. a real default - a dated post dies the day after the match, an undated one
--      after 14 days
--   2. a match-date floor in the feed, independent of the caller
--   3. recency in the ordering, so anything already played sinks

alter table public.looking_for_posts
  alter column expires_at set default (now() + interval '14 days');

-- backfill the posts that were created with no expiry at all
update public.looking_for_posts
   set expires_at = coalesce(match_at + interval '1 day', created_at + interval '14 days')
 where expires_at is null;

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
          _place_label, _match_at, _overs, _skill, _slots_needed,
          -- an explicit expiry wins; otherwise a dated post dies the day after
          -- the match and an undated one after 14 days
          coalesce(_expires_at, _match_at + interval '1 day', now() + interval '14 days'),
          coalesce(_image_urls, '{}'), _link_url, _ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) to authenticated;

-- feed: hide matches that have already happened, and sink anything past its date
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
    -- a match that already happened is not something to answer, whatever the
    -- caller asked for
    and (p.match_at is null or p.match_at >= now() - interval '6 hours')
    and (_mode is null or p.mode = _mode)
    and (_max_overs is null or p.overs is null or p.overs <= _max_overs)
    and (_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)
    and (_skill is null or p.skill = _skill)
    and (_flair is null or p.flair = _flair)
    and extensions.st_dwithin(p.geog_coarse, probe.g, probe.r)
  -- nearest first, but anything already in the past sinks below everything live
  order by (p.match_at is not null and p.match_at < now()),
           p.geog_coarse operator(extensions.<->) (select g from probe);
$$;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) to authenticated;
