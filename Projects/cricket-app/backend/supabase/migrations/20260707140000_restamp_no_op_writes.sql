-- HIGH (penetration review 2026-07-07, corrections-broadcast-storm - found by
-- the completeness critic): restamp_innings_strike rewrote EVERY delivery row
-- unconditionally, and a per-row broadcast trigger fires on each one. Correcting
-- a single wide on ball 3 of a 120-ball innings therefore emitted ~121 realtime
-- messages on match:<id>, and every connected viewer did a FULL RE-FOLD per
-- message. insert_ball was worse (renumber + restamp = ~235).
--
-- Fix: only write rows whose stamped pair actually changed. The fold logic is
-- untouched - this is purely "do not UPDATE a row to the value it already has".
create or replace function public.restamp_innings_strike(_innings_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  _m uuid; _bpo int; _striker uuid; _non uuid; _tmp uuid;
  _target int; _max_overs int; _squad_size int; _lms boolean; _all_out int; _max_legal int;
  _legal int := 0; _legal_this_over int := 0; _runs int := 0; _wickets int := 0;
  _ended boolean := false; _facing uuid; _facing_ns uuid; _out uuid; _rr int; _d_total int; _is_wkt boolean;
  d record;
begin
  -- LOCKSTEP: identical parameters to the other two folds.
  select p.match_id, p.bpo, p.opening_striker, p.opening_non_striker,
         p.target, p.max_overs, p.squad_size, p.lms, p.all_out, p.max_legal
    into _m, _bpo, _striker, _non, _target, _max_overs, _squad_size, _lms,
         _all_out, _max_legal
  from public._innings_fold_params(_innings_id) p;
  if _m is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _facing := _striker; _facing_ns := _non;
    -- ONLY write when the pair actually moved: an unconditional UPDATE here made
    -- one correction fan out into a realtime message per delivery.
    if (d.striker_id, d.non_striker_id) is distinct from (_facing, _facing_ns) then
      update public.deliveries set striker_id = _facing, non_striker_id = _facing_ns
       where id = d.id;
    end if;
    if _ended then continue; end if;  -- orphaned balls keep the end-of-innings pair

    -- v14: non-ball events between deliveries
    if d.event_kind = 'strike_swap' then
      _tmp := _striker; _striker := _non; _non := _tmp;
      continue;
    elsif d.event_kind = 'retirement' then
      _out := d.dismissed_player_id;
      if d.wicket_type <> 'retired_not_out' then _wickets := _wickets + 1; end if;
      if d.incoming_batter_id is not null then
        if _striker = _out then _striker := d.incoming_batter_id;
        elsif _non = _out then _non := d.incoming_batter_id; end if;
      end if;
      if _wickets >= _all_out then _ended := true; end if;
      continue;
    end if;

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
    if _is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed, false) then
      _tmp := _striker; _striker := _non; _non := _tmp;
    end if;

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
