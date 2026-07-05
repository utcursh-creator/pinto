-- Apply correction_wicket_guard to edit_ball + insert_ball (bodies otherwise
-- identical to 20260623130000_restamp_strike.sql - restamp preserved).
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
declare _in uuid; _m uuid; _seq int;
begin
  select innings_id, seq into _in, _seq from public.deliveries where id = _delivery_id;
  if _in is null then raise exception 'delivery not found' using errcode='P0001'; end if;
  select match_id into _m from public.innings where id = _in;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_in::text, 0));
  -- SCOR-2/5: a wicket edit mid-innings must name the incoming batter.
  perform public.correction_wicket_guard(_in, _seq, _wicket_type, _incoming_batter_id, false);
  update public.deliveries set
    runs_off_bat=_runs_off_bat, extra_wides=_extra_wides, extra_no_ball_penalty=_extra_no_ball_penalty,
    extra_byes=_extra_byes, extra_leg_byes=_extra_leg_byes, extra_penalty=_extra_penalty,
    noball_secondary_kind=_noball_secondary_kind, wicket_type=_wicket_type, dismissed_player_id=_dismissed_player_id,
    incoming_batter_id=_incoming_batter_id, fielder_id=_fielder_id, crossed=_crossed, prevented_catch=_prevented_catch,
    is_overthrow=_is_overthrow, overthrow_crossed=_overthrow_crossed, wagon_x=_wagon_x, wagon_y=_wagon_y,
    wagon_zone=_wagon_zone, commentary_text=_commentary_text, updated_at=now()
  where id = _delivery_id;
  perform public.restamp_innings_strike(_in);
end; $$;

create or replace function public.insert_ball(
  _innings_id uuid, _after_seq bigint, _bowler_id uuid,
  _runs_off_bat int default 0, _extra_wides int default 0, _extra_no_ball_penalty int default 0,
  _extra_byes int default 0, _extra_leg_byes int default 0, _extra_penalty int default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _m uuid; _id uuid; _os uuid; _ons uuid; _shifting boolean;
begin
  select match_id into _m from public.innings where id = _innings_id;
  if _m is null or not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));
  -- SCOR-2/5: an inserted wicket with balls after it must name the incoming batter.
  select exists (select 1 from public.deliveries
                 where innings_id = _innings_id and seq > _after_seq) into _shifting;
  perform public.correction_wicket_guard(_innings_id, _after_seq::int, _wicket_type, _incoming_batter_id, _shifting);
  select opening_striker_id, opening_non_striker_id into _os, _ons from public.innings where id = _innings_id;
  update public.deliveries set seq = -(seq + 1) where innings_id = _innings_id and seq > _after_seq;
  update public.deliveries set seq = -seq where innings_id = _innings_id and seq < 0;
  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,striker_id,non_striker_id)
  values (_innings_id,_after_seq+1,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_os,_ons)
  returning id into _id;
  perform public.restamp_innings_strike(_innings_id);
  return _id;
end; $$;
