-- DISC-1 (last field): looking-for posts can say which ball they play with -
-- tennis vs leather is the single biggest compatibility filter in street
-- cricket. Column + create param + both read paths.
alter table public.looking_for_posts add column ball_type public.ball_type;

drop function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text);
create function public.create_looking_for_post(
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
  insert into public.looking_for_posts(author_id, team_id, mode, flair, title, description, geog, place_label, match_at, overs, skill, slots_needed, expires_at, image_urls, link_url, ball_type)
  values (_uid, _team_id, _mode, _flair, _title, _description,
          extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography,
          _place_label, _match_at, _overs, _skill, _slots_needed, _expires_at,
          coalesce(_image_urls, '{}'), _link_url, _ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,public.lf_flair,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz,text[],text,public.ball_type) to authenticated;
