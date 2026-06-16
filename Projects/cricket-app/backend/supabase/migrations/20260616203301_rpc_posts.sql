create or replace function public.create_looking_for_post(
  _mode public.lf_mode, _lat float, _lng float, _description text default null,
  _team_id uuid default null, _title text default null, _match_at timestamptz default null,
  _overs int default null, _skill public.skill_level default null, _slots_needed int default null,
  _place_label text default null, _expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid()); _id uuid;
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _team_id is not null and not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.looking_for_posts(author_id, team_id, mode, title, description, geog, place_label, match_at, overs, skill, slots_needed, expires_at)
  values (_uid, _team_id, _mode, _title, _description,
          extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography,
          _place_label, _match_at, _overs, _skill, _slots_needed, _expires_at)
  returning id into _id;
  return _id;
end; $$;

create or replace function public.cancel_post(_post_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.looking_for_posts set status='cancelled'
   where id=_post_id and author_id = (select auth.uid());
  if not found then raise exception 'not authorized or not found' using errcode='P0001'; end if;
end; $$;

create or replace function public.mark_post_filled(_post_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.looking_for_posts set status='filled'
   where id=_post_id and author_id = (select auth.uid());
  if not found then raise exception 'not authorized or not found' using errcode='P0001'; end if;
end; $$;

revoke all on function public.create_looking_for_post(public.lf_mode,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) to authenticated;
revoke all on function public.cancel_post(uuid) from public;  grant execute on function public.cancel_post(uuid) to authenticated;
revoke all on function public.mark_post_filled(uuid) from public; grant execute on function public.mark_post_filled(uuid) to authenticated;
