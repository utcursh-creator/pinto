-- Whole-system review #2 (2026-07-28), finding 58: discover_posts returns every
-- open post inside the radius with no LIMIT, and the feed has no pagination.
--
-- The radius is already clamped (2 km to 50 km), but 50 km around a dense city
-- is thousands of live ads - all serialised, sent and parsed on a phone, on
-- every feed open and every pull-to-refresh. The client-side cap added earlier
-- in this review bounded the OTHER list queries; this RPC returns a set, so a
-- builder `.limit()` never applied to it.
--
-- DROP first, deliberately: `create or replace` with a new arity creates an
-- OVERLOAD rather than replacing, and two candidates make PostgREST answer 300
-- for every call. That has bitten this project before.
drop function if exists public.discover_posts(
  double precision, double precision, double precision, lf_mode, integer,
  timestamp with time zone, skill_level, lf_flair);

CREATE OR REPLACE FUNCTION public.discover_posts(_lat double precision, _lng double precision, _radius_m double precision DEFAULT 25000, _mode lf_mode DEFAULT NULL::lf_mode, _max_overs integer DEFAULT NULL::integer, _on_or_after timestamp with time zone DEFAULT NULL::timestamp with time zone, _skill skill_level DEFAULT NULL::skill_level, _flair lf_flair DEFAULT NULL::lf_flair, _limit integer DEFAULT 100)
 RETURNS TABLE(post_id uuid, author_id uuid, team_id uuid, mode lf_mode, flair lf_flair, title text, description text, place_label text, match_at timestamp with time zone, overs integer, skill skill_level, slots_needed integer, created_at timestamp with time zone, image_urls text[], link_url text, approx_m double precision, author_name text, team_name text, ball_type ball_type)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
           p.geog_coarse operator(extensions.<->) (select g from probe)
  -- Bounded, and clamped like the radius already is. Without this the feed
  -- returned every open post inside a radius that can reach 50 km - in a city
  -- that is thousands of rows, serialised and parsed on a phone, on every open
  -- and every pull-to-refresh (review #2, finding 58).
  limit least(greatest(coalesce(_limit, 100), 1), 200);
$function$;
