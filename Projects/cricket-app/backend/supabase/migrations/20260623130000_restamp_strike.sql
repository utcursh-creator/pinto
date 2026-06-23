-- Re-stamp deliveries.striker_id/non_striker_id from the fold after a
-- correction, so direct readers of those columns (ball-log UI, per-delivery
-- stats, wagon-by-batter) see the rotation-correct facing batter. The scorecard
-- fold (compute_innings_state) was already correct (it re-derives strike), but
-- edit_ball/insert_ball/delete_ball used to leave the stored stamps stale.
-- The loop mirrors compute_innings_state's strike logic EXACTLY (running-runs
-- rotation -> over-end swap -> wicket incoming-batter), stripped of aggregation.
create or replace function public.restamp_innings_strike(_innings_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  _m uuid; _bpo int; _striker uuid; _non uuid; _tmp uuid;
  _target int; _max_overs int; _squad_size int; _lms boolean; _all_out int; _max_legal int;
  _legal int := 0; _legal_this_over int := 0; _runs int := 0; _wickets int := 0;
  _ended boolean := false; _facing uuid; _facing_ns uuid; _out uuid; _rr int; _d_total int; _is_wkt boolean;
  d record;
begin
  select i.match_id, coalesce(m.balls_per_over,6), i.opening_striker_id, i.opening_non_striker_id,
         i.target, coalesce(i.revised_overs, i.overs_limit, m.overs_limit),
         coalesce((m.rules->>'squad_size')::int, 11), coalesce((m.rules->>'last_man_stands')::boolean, false)
    into _m, _bpo, _striker, _non, _target, _max_overs, _squad_size, _lms
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;
  if _m is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  _all_out := case when _lms then _squad_size else _squad_size - 1 end;
  _max_legal := _max_overs * _bpo;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _facing := _striker; _facing_ns := _non;
    update public.deliveries set striker_id = _facing, non_striker_id = _facing_ns where id = d.id;
    if _ended then continue; end if;  -- orphaned balls keep the end-of-innings pair

    _d_total := d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    _is_wkt := (d.wicket_type is not null and d.wicket_type <> 'retired_not_out');
    _runs := _runs + _d_total;
    if _is_wkt then _wickets := _wickets + 1; end if;

    _rr := 0;
    if d.runs_off_bat not in (4,6) then _rr := _rr + d.runs_off_bat; end if;
    if d.extra_byes <> 4 then _rr := _rr + d.extra_byes; end if;
    if d.extra_leg_byes <> 4 then _rr := _rr + d.extra_leg_byes; end if;
    if d.extra_wides > 1 and (d.extra_wides - 1) <> 4 then _rr := _rr + (d.extra_wides - 1); end if;
    if (_rr % 2) = 1 then _tmp := _striker; _striker := _non; _non := _tmp; end if;

    if d.is_legal then
      _legal := _legal + 1; _legal_this_over := _legal_this_over + 1;
      if _legal_this_over = _bpo then
        _legal_this_over := 0;
        _tmp := _striker; _striker := _non; _non := _tmp;
      end if;
    end if;

    if _is_wkt then
      if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing; end if;
      if d.incoming_batter_id is not null then
        if _striker = _out then _striker := d.incoming_batter_id;
        elsif _non = _out then _non := d.incoming_batter_id; end if;
      end if;
    end if;

    if (_target is not null and _runs >= _target) or (_wickets >= _all_out) or (_legal >= _max_legal) then
      _ended := true;
    end if;
  end loop;
end; $$;

revoke all on function public.restamp_innings_strike(uuid) from public;
grant execute on function public.restamp_innings_strike(uuid) to authenticated;

-- Wire the re-stamp into the three corrections (record_ball/undo need no change:
-- record_ball stamps the appended ball from the live fold; undo removes the tail).
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
  perform public.restamp_innings_strike(_in);
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
  -- re-stamp strike from the fold: an edit can change downstream rotation.
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
declare _m uuid; _id uuid; _os uuid; _ons uuid;
begin
  select match_id into _m from public.innings where id = _innings_id;
  if _m is null or not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));
  select opening_striker_id, opening_non_striker_id into _os, _ons from public.innings where id = _innings_id;
  update public.deliveries set seq = -(seq + 1) where innings_id = _innings_id and seq > _after_seq;
  update public.deliveries set seq = -seq where innings_id = _innings_id and seq < 0;
  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,striker_id,non_striker_id)
  values (_innings_id,_after_seq+1,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_os,_ons)
  returning id into _id;
  -- re-stamp strike from the fold (the inserted row's opening-pair stamp + all
  -- shifted rows are corrected here).
  perform public.restamp_innings_strike(_innings_id);
  return _id;
end; $$;

comment on column public.deliveries.striker_id is
  'Facing batter for this ball. Stamped from the fold on record_ball and kept '
  'rotation-correct after edit/insert/delete via restamp_innings_strike. Any new '
  'mutation path that changes downstream rotation MUST call restamp_innings_strike.';
comment on column public.deliveries.non_striker_id is
  'Non-striker for this ball; maintained alongside striker_id (see its comment).';
