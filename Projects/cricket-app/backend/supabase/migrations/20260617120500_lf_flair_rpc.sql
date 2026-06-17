-- Sub-project 4, Task 2: thread flair through create_looking_for_post + discover_posts.
-- Drop the old overloads first so PostgREST/callers see exactly one signature each.
drop function public.create_looking_for_post(public.lf_mode,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz);
drop function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level);

-- _flair is REQUIRED and placed right after _mode (required params precede defaulted ones).
create function public.create_looking_for_post(
  _mode public.lf_mode, _flair public.lf_flair, _lat float, _lng float, _description text default null,
  _team_id uuid default null, _title text default null, _match_at timestamptz default null,
  _overs int default null, _skill public.skill_level default null, _slots_needed int default null,
  _place_label text default null, _expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid()); _id uuid;
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _team_id is not null and not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.looking_for_posts(author_id, team_id, mode, flair, title, description, geog, place_label, match_at, overs, skill, slots_needed, expires_at)
  values (_uid, _team_id, _mode, _flair, _title, _description,
          extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography,
          _place_label, _match_at, _overs, _skill, _slots_needed, _expires_at)
  returning id into _id;
  return _id;
end; $$;

-- _flair appended LAST (optional) to preserve positional call compatibility; the feed reads flair off each row.
create function public.discover_posts(
  _lat float, _lng float, _radius_m float default 25000,
  _mode public.lf_mode default null, _max_overs int default null,
  _on_or_after timestamptz default null, _skill public.skill_level default null,
  _flair public.lf_flair default null
) returns table (
  post_id uuid, author_id uuid, team_id uuid, mode public.lf_mode, flair public.lf_flair,
  title text, description text, place_label text, match_at timestamptz,
  overs int, skill public.skill_level, slots_needed int, created_at timestamptz, approx_m float
) language sql security definer set search_path = '' stable as $$
  select p.id, p.author_id, p.team_id, p.mode, p.flair, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at,
         round(extensions.st_distance(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography) / 100.0) * 100 as approx_m
  from public.looking_for_posts p
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

revoke all on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) to authenticated;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level,public.lf_flair) to authenticated;
