-- helper to authorize + lock by innings
create or replace function public._scoring_innings_match(_innings_id uuid) returns uuid
language sql security definer set search_path = public stable as $$
  select match_id from public.innings where id = _innings_id;
$$;

create or replace function public.undo_last_ball(_innings_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _m uuid;
begin
  select match_id into _m from public.innings where id = _innings_id;
  if _m is null or not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));
  delete from public.deliveries where innings_id = _innings_id
    and seq = (select max(seq) from public.deliveries where innings_id = _innings_id);
end; $$;

create or replace function public.delete_ball(_delivery_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _in uuid; _m uuid;
begin
  select innings_id into _in from public.deliveries where id = _delivery_id;
  if _in is null then raise exception 'delivery not found' using errcode='P0001'; end if;
  select match_id into _m from public.innings where id = _in;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_in::text, 0));
  delete from public.deliveries where id = _delivery_id;
end; $$;

create or replace function public.edit_ball(
  _delivery_id uuid,
  _runs_off_bat int default 0, _extra_wides int default 0, _extra_no_ball_penalty int default 0,
  _extra_byes int default 0, _extra_leg_byes int default 0, _extra_penalty int default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null,
  _crossed boolean default null, _prevented_catch boolean default null,
  _is_overthrow boolean default false, _overthrow_crossed boolean default null,
  _wagon_x real default null, _wagon_y real default null, _wagon_zone smallint default null,
  _commentary_text text default null
) returns void language plpgsql security definer set search_path = public as $$
declare _in uuid; _m uuid;
begin
  select innings_id into _in from public.deliveries where id = _delivery_id;
  if _in is null then raise exception 'delivery not found' using errcode='P0001'; end if;
  select match_id into _m from public.innings where id = _in;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_in::text, 0));
  update public.deliveries set
    runs_off_bat=_runs_off_bat, extra_wides=_extra_wides, extra_no_ball_penalty=_extra_no_ball_penalty,
    extra_byes=_extra_byes, extra_leg_byes=_extra_leg_byes, extra_penalty=_extra_penalty,
    noball_secondary_kind=_noball_secondary_kind, wicket_type=_wicket_type, dismissed_player_id=_dismissed_player_id,
    incoming_batter_id=_incoming_batter_id, fielder_id=_fielder_id, crossed=_crossed, prevented_catch=_prevented_catch,
    is_overthrow=_is_overthrow, overthrow_crossed=_overthrow_crossed, wagon_x=_wagon_x, wagon_y=_wagon_y,
    wagon_zone=_wagon_zone, commentary_text=_commentary_text, updated_at=now()
  where id = _delivery_id;
  -- striker_id/non_striker_id stamps are intentionally left as-is: the fold derives strike and ignores them.
end; $$;

create or replace function public.insert_ball(
  _innings_id uuid, _after_seq bigint, _bowler_id uuid,
  _runs_off_bat int default 0, _extra_wides int default 0, _extra_no_ball_penalty int default 0,
  _extra_byes int default 0, _extra_leg_byes int default 0, _extra_penalty int default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _m uuid; _id uuid; _os uuid; _ons uuid;
begin
  select match_id into _m from public.innings where id = _innings_id;
  if _m is null or not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));
  select opening_striker_id, opening_non_striker_id into _os, _ons from public.innings where id = _innings_id;
  -- shift later deliveries up by one via a two-step negation (the unique index is not deferred,
  -- so a plain seq=seq+1 would transiently collide; negatives never collide with positives).
  update public.deliveries set seq = -(seq + 1) where innings_id = _innings_id and seq > _after_seq;
  update public.deliveries set seq = -seq where innings_id = _innings_id and seq < 0;
  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,striker_id,non_striker_id)
  values (_innings_id,_after_seq+1,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_os,_ons)
  returning id into _id;
  return _id;
end; $$;

revoke all on function public.undo_last_ball(uuid) from public;
revoke all on function public.delete_ball(uuid) from public;
grant execute on function public.undo_last_ball(uuid) to authenticated;
grant execute on function public.delete_ball(uuid) to authenticated;
grant execute on function public.edit_ball(uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text) to authenticated;
grant execute on function public.insert_ball(uuid,bigint,uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid) to authenticated;
