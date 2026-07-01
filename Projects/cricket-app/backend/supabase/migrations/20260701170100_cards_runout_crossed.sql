-- SCOR-3: apply the run-out `crossed` strike swap in the per-player fold too, in
-- lockstep with compute_innings_state (the divergence guard requires it).
create or replace function public.compute_innings_cards(_innings_id uuid)
returns jsonb language plpgsql security invoker set search_path = public stable as $$
declare
  _striker uuid; _non uuid; _tmp uuid; _facing uuid; _out uuid;
  _bpo int; _count_nb_faced boolean;
  _target int; _max_overs int; _squad_size int; _lms boolean; _all_out int; _max_legal int;
  _legal int := 0; _legal_this_over int := 0; _runs int := 0; _wickets int := 0;
  _over_bowler_runs int := 0; _ended boolean := false;
  _rr int; _d_total int; _is_wkt boolean; _dconc int;
  _batters jsonb := '{}'::jsonb; _btkey text; _btcur jsonb;
  _bowlers jsonb := '{}'::jsonb; _bkey text; _bcur jsonb;
  _fielders jsonb := '{}'::jsonb; _fkey text; _fcur jsonb;
  d record;
begin
  select i.opening_striker_id, i.opening_non_striker_id, coalesce(m.balls_per_over,6),
         coalesce((m.rules->>'count_noball_as_ball_faced')::boolean, true), i.target,
         coalesce(i.revised_overs, i.overs_limit, m.overs_limit),
         coalesce((m.rules->>'squad_size')::int, 11), coalesce((m.rules->>'last_man_stands')::boolean, false)
    into _striker, _non, _bpo, _count_nb_faced, _target, _max_overs, _squad_size, _lms
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;
  _all_out := case when _lms then _squad_size else _squad_size - 1 end;
  _max_legal := _max_overs * _bpo;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    if _ended then continue; end if;  -- balls after the innings ended do not count
    _facing := _striker;
    _d_total := d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    _is_wkt := (d.wicket_type is not null and d.wicket_type <> 'retired_not_out');
    _runs := _runs + _d_total;
    if _is_wkt then _wickets := _wickets + 1; end if;

    -- bowling line (runs_conceded = off-bat + wides + no-ball penalty; byes/leg-byes/penalty excluded)
    _dconc := d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty;
    _over_bowler_runs := _over_bowler_runs + _dconc;
    _bkey := d.bowler_id::text;
    _bcur := coalesce(_bowlers -> _bkey, jsonb_build_object('member_id', d.bowler_id,'legal_balls',0,'runs_conceded',0,'maidens',0,'dots',0,'wides',0,'no_balls',0,'wickets',0));
    _bcur := jsonb_set(_bcur, '{runs_conceded}', to_jsonb((_bcur->>'runs_conceded')::int + _dconc));
    if d.is_legal then _bcur := jsonb_set(_bcur, '{legal_balls}', to_jsonb((_bcur->>'legal_balls')::int + 1)); end if;
    if d.is_legal and (d.runs_off_bat + d.extra_byes + d.extra_leg_byes + d.extra_penalty) = 0 then
      _bcur := jsonb_set(_bcur, '{dots}', to_jsonb((_bcur->>'dots')::int + 1));
    end if;
    if d.extra_wides > 0 then _bcur := jsonb_set(_bcur, '{wides}', to_jsonb((_bcur->>'wides')::int + 1)); end if;
    if d.extra_no_ball_penalty > 0 then _bcur := jsonb_set(_bcur, '{no_balls}', to_jsonb((_bcur->>'no_balls')::int + 1)); end if;
    if d.wicket_type in ('bowled','caught','lbw','stumped','hit_wicket') then
      _bcur := jsonb_set(_bcur, '{wickets}', to_jsonb((_bcur->>'wickets')::int + 1));
    end if;
    _bowlers := jsonb_set(_bowlers, array[_bkey], _bcur);

    -- batting line for the facing batter
    _btkey := _facing::text;
    _btcur := coalesce(_batters -> _btkey, jsonb_build_object('member_id', _facing,'runs',0,'balls',0,'fours',0,'sixes',0,'dismissed',false,'how_out',null));
    _btcur := jsonb_set(_btcur, '{runs}', to_jsonb((_btcur->>'runs')::int + d.runs_off_bat));
    if d.extra_wides = 0 and (d.extra_no_ball_penalty = 0 or _count_nb_faced) then
      _btcur := jsonb_set(_btcur, '{balls}', to_jsonb((_btcur->>'balls')::int + 1));
    end if;
    if d.runs_off_bat = 4 then _btcur := jsonb_set(_btcur, '{fours}', to_jsonb((_btcur->>'fours')::int + 1)); end if;
    if d.runs_off_bat = 6 then _btcur := jsonb_set(_btcur, '{sixes}', to_jsonb((_btcur->>'sixes')::int + 1)); end if;
    _batters := jsonb_set(_batters, array[_btkey], _btcur);

    -- strike rotation: running runs (off-bat 4/6 + bye/lb/wide-allowance of 4 are boundaries, no crossing)
    _rr := 0;
    if d.runs_off_bat not in (4,6) then _rr := _rr + d.runs_off_bat; end if;
    if d.extra_byes <> 4 then _rr := _rr + d.extra_byes; end if;
    if d.extra_leg_byes <> 4 then _rr := _rr + d.extra_leg_byes; end if;
    if d.extra_wides > 1 and (d.extra_wides - 1) <> 4 then _rr := _rr + (d.extra_wides - 1); end if;
    if (_rr % 2) = 1 then _tmp := _striker; _striker := _non; _non := _tmp; end if;
    -- SCOR-3: on a run-out the batters may have crossed on the fatal (incomplete)
    -- run; that crossing is not in runs_off_bat. Apply it from the stored
    -- `crossed` flag before the dismissed batter is replaced.
    if _is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed, false) then
      _tmp := _striker; _striker := _non; _non := _tmp;
    end if;

    -- legal-ball accounting + over-end maiden + over-end strike swap
    if d.is_legal then
      _legal := _legal + 1; _legal_this_over := _legal_this_over + 1;
      if _legal_this_over = _bpo then
        _legal_this_over := 0;
        if _over_bowler_runs = 0 then
          _bcur := _bowlers -> _bkey; _bcur := jsonb_set(_bcur, '{maidens}', to_jsonb((_bcur->>'maidens')::int + 1));
          _bowlers := jsonb_set(_bowlers, array[_bkey], _bcur);
        end if;
        _over_bowler_runs := 0;
        _tmp := _striker; _striker := _non; _non := _tmp;
      end if;
    end if;

    -- dismissal attribution + fielding credit + incoming batter
    if _is_wkt then
      if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing; end if;
      if _out is not null then
        -- the out batter may have a line already (they faced balls) or not
        -- (e.g. a non-striker run out without facing) - ensure one, then flag.
        _btkey := _out::text;
        _btcur := coalesce(_batters -> _btkey, jsonb_build_object('member_id', _out,'runs',0,'balls',0,'fours',0,'sixes',0,'dismissed',false,'how_out',null));
        _btcur := jsonb_set(_btcur, '{dismissed}', 'true'::jsonb);
        _btcur := jsonb_set(_btcur, '{how_out}', to_jsonb(d.wicket_type::text));
        _batters := jsonb_set(_batters, array[_btkey], _btcur);
      end if;
      if d.fielder_id is not null and d.wicket_type in ('caught','run_out','stumped') then
        _fkey := d.fielder_id::text;
        _fcur := coalesce(_fielders -> _fkey, jsonb_build_object('member_id', d.fielder_id,'catches',0,'run_outs',0,'stumpings',0));
        if d.wicket_type = 'caught' then _fcur := jsonb_set(_fcur, '{catches}', to_jsonb((_fcur->>'catches')::int + 1));
        elsif d.wicket_type = 'run_out' then _fcur := jsonb_set(_fcur, '{run_outs}', to_jsonb((_fcur->>'run_outs')::int + 1));
        elsif d.wicket_type = 'stumped' then _fcur := jsonb_set(_fcur, '{stumpings}', to_jsonb((_fcur->>'stumpings')::int + 1)); end if;
        _fielders := jsonb_set(_fielders, array[_fkey], _fcur);
      end if;
      if d.incoming_batter_id is not null then
        if _striker = _out then _striker := d.incoming_batter_id;
        elsif _non = _out then _non := d.incoming_batter_id; end if;
      end if;
    end if;

    if (_target is not null and _runs >= _target) or (_wickets >= _all_out) or (_legal >= _max_legal) then
      _ended := true;
    end if;
  end loop;

  return jsonb_build_object(
    'batting',  coalesce((select jsonb_agg(value) from jsonb_each(_batters)), '[]'::jsonb),
    'bowling',  coalesce((select jsonb_agg(value) from jsonb_each(_bowlers)), '[]'::jsonb),
    'fielding', coalesce((select jsonb_agg(value) from jsonb_each(_fielders)), '[]'::jsonb)
  );
end; $$;
revoke all on function public.compute_innings_cards(uuid) from public;
grant execute on function public.compute_innings_cards(uuid) to authenticated, anon;
