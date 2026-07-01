-- SCOR-23: over notation, CRR/RRR, and bowler overs/economy hardcoded /6 and %6,
-- which is wrong for the non-6-ball formats the app supports (matches.balls_per_over).
-- Recompute all over-math off _bpo. Behaviour-identical for the default 6-ball over.
-- (compute_innings_state fold v11)
create or replace function public.compute_innings_state(_innings_id uuid)
returns jsonb language plpgsql security invoker set search_path = public stable as $$
declare
  _runs int := 0; _wickets int := 0; _legal int := 0; _d_total int; _is_wkt boolean;
  _wides int := 0; _nb int := 0; _byes int := 0; _lb int := 0; _pen int := 0;
  _striker uuid; _non_striker uuid; _tmp uuid; _facing uuid; _out uuid; _survivor uuid;
  _legal_this_over int := 0; _bpo int; _rr int; _over_bowler_runs int := 0;
  _match_id uuid; _batting_team uuid; _bowling_team uuid; _count_nb_faced boolean;
  _target int; _max_overs int; _squad_size int; _lms boolean; _all_out int; _max_legal int;
  _ended boolean := false; _orphaned jsonb := '[]'::jsonb;
  _bowlers jsonb := '{}'::jsonb; _bkey text; _bcur jsonb; _dconc int;
  _batters jsonb := '{}'::jsonb; _btkey text; _btcur jsonb;
  _free_hit boolean := false; _did_not_bat jsonb; _fow jsonb := '[]'::jsonb;
  _partnerships jsonb := '[]'::jsonb; _ps_a uuid; _ps_b uuid; _ps_a_runs int := 0; _ps_b_runs int := 0;
  _ps_start_runs int := 0; _ps_start_legal int := 0;
  _over_runs int := 0; _over_wkts int := 0; _over_index int := 0; _per_over jsonb := '[]'::jsonb; _worm jsonb := '[]'::jsonb;
  _crr numeric; _rrr numeric; _balls_rem int; _wkts_rem int; _runs_req int; _result jsonb; _status text;
  d record;
begin
  select i.opening_striker_id, i.opening_non_striker_id, coalesce(m.balls_per_over,6),
         i.match_id, i.batting_team_id, i.bowling_team_id,
         coalesce((m.rules->>'count_noball_as_ball_faced')::boolean, true), i.target,
         coalesce(i.revised_overs, i.overs_limit, m.overs_limit),
         coalesce((m.rules->>'squad_size')::int, 11), coalesce((m.rules->>'last_man_stands')::boolean, false)
    into _striker, _non_striker, _bpo, _match_id, _batting_team, _bowling_team,
         _count_nb_faced, _target, _max_overs, _squad_size, _lms
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;
  _ps_a := _striker; _ps_b := _non_striker;
  _all_out := case when _lms then _squad_size else _squad_size - 1 end;
  _max_legal := _max_overs * _bpo;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    if _ended then _orphaned := _orphaned || to_jsonb(d.id); continue; end if;
    _facing := _striker;
    _d_total := d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    _is_wkt := (d.wicket_type is not null and d.wicket_type <> 'retired_not_out');
    _runs := _runs + _d_total; _over_runs := _over_runs + _d_total;
    if _is_wkt then _wickets := _wickets + 1; _over_wkts := _over_wkts + 1; end if;
    _wides := _wides + d.extra_wides; _nb := _nb + d.extra_no_ball_penalty;
    _byes := _byes + d.extra_byes; _lb := _lb + d.extra_leg_byes; _pen := _pen + d.extra_penalty;

    _dconc := d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty;
    _over_bowler_runs := _over_bowler_runs + _dconc;
    _bkey := d.bowler_id::text;
    _bcur := coalesce(_bowlers -> _bkey, jsonb_build_object('bowler_id', d.bowler_id, 'legal_balls',0,'runs_conceded',0,'maidens',0,'dots',0,'wides_bowled',0,'no_balls_bowled',0,'wickets',0));
    _bcur := jsonb_set(_bcur, '{runs_conceded}', to_jsonb((_bcur->>'runs_conceded')::int + _dconc));
    if d.is_legal then _bcur := jsonb_set(_bcur, '{legal_balls}', to_jsonb((_bcur->>'legal_balls')::int + 1)); end if;
    if d.is_legal and (d.runs_off_bat + d.extra_byes + d.extra_leg_byes + d.extra_penalty) = 0 then
      _bcur := jsonb_set(_bcur, '{dots}', to_jsonb((_bcur->>'dots')::int + 1));
    end if;
    if d.extra_wides > 0 then _bcur := jsonb_set(_bcur, '{wides_bowled}', to_jsonb((_bcur->>'wides_bowled')::int + 1)); end if;
    if d.extra_no_ball_penalty > 0 then _bcur := jsonb_set(_bcur, '{no_balls_bowled}', to_jsonb((_bcur->>'no_balls_bowled')::int + 1)); end if;
    if d.wicket_type in ('bowled','caught','lbw','stumped','hit_wicket') then
      _bcur := jsonb_set(_bcur, '{wickets}', to_jsonb((_bcur->>'wickets')::int + 1));
    end if;
    _bowlers := jsonb_set(_bowlers, array[_bkey], _bcur);

    _btkey := _facing::text;
    _btcur := coalesce(_batters -> _btkey, jsonb_build_object('batter_id', _facing,'runs',0,'balls',0,'fours',0,'sixes',0));
    _btcur := jsonb_set(_btcur, '{runs}', to_jsonb((_btcur->>'runs')::int + d.runs_off_bat));
    if d.extra_wides = 0 and (d.extra_no_ball_penalty = 0 or _count_nb_faced) then
      _btcur := jsonb_set(_btcur, '{balls}', to_jsonb((_btcur->>'balls')::int + 1));
    end if;
    if d.runs_off_bat = 4 then _btcur := jsonb_set(_btcur, '{fours}', to_jsonb((_btcur->>'fours')::int + 1)); end if;
    if d.runs_off_bat = 6 then _btcur := jsonb_set(_btcur, '{sixes}', to_jsonb((_btcur->>'sixes')::int + 1)); end if;
    _batters := jsonb_set(_batters, array[_btkey], _btcur);

    if _facing = _ps_a then _ps_a_runs := _ps_a_runs + d.runs_off_bat;
    elsif _facing = _ps_b then _ps_b_runs := _ps_b_runs + d.runs_off_bat; end if;

    _rr := 0;
    if d.runs_off_bat not in (4,6) then _rr := _rr + d.runs_off_bat; end if;
    if d.extra_byes <> 4 then _rr := _rr + d.extra_byes; end if;
    if d.extra_leg_byes <> 4 then _rr := _rr + d.extra_leg_byes; end if;
    if d.extra_wides > 1 and (d.extra_wides - 1) <> 4 then _rr := _rr + (d.extra_wides - 1); end if;
    if (_rr % 2) = 1 then _tmp := _striker; _striker := _non_striker; _non_striker := _tmp; end if;

    if d.is_legal then
      _legal := _legal + 1; _legal_this_over := _legal_this_over + 1;
      if _legal_this_over = _bpo then
        _legal_this_over := 0;
        if _over_bowler_runs = 0 then
          _bcur := _bowlers -> _bkey; _bcur := jsonb_set(_bcur, '{maidens}', to_jsonb((_bcur->>'maidens')::int + 1));
          _bowlers := jsonb_set(_bowlers, array[_bkey], _bcur);
        end if;
        _over_bowler_runs := 0;
        _tmp := _striker; _striker := _non_striker; _non_striker := _tmp;
        _over_index := _over_index + 1;
        _per_over := _per_over || jsonb_build_object('over_number',_over_index,'runs_in_over',_over_runs,'wickets_in_over',_over_wkts);
        _worm := _worm || jsonb_build_object('over',_over_index,'cumulative_runs',_runs,'cumulative_wickets',_wickets);
        _over_runs := 0; _over_wkts := 0;
      end if;
    end if;

    if _is_wkt then
      if d.wicket_type in ('run_out','obstructing') then _out := d.dismissed_player_id; else _out := _facing; end if;
      _fow := _fow || jsonb_build_object('wicket_number', _wickets, 'score_at_fall', _runs,
        'over', (_legal/_bpo)::text || '.' || (_legal%_bpo)::text, 'dismissed_player_id', _out);
      if d.incoming_batter_id is not null then
        if _striker = _out then _striker := d.incoming_batter_id;
        elsif _non_striker = _out then _non_striker := d.incoming_batter_id; end if;
      end if;
      _partnerships := _partnerships || jsonb_build_object('wicket_number',_wickets,'batter_a',_ps_a,'batter_b',_ps_b,
        'runs',_runs-_ps_start_runs,'balls',_legal-_ps_start_legal,'a_runs',_ps_a_runs,'b_runs',_ps_b_runs,
        'start_score',_ps_start_runs,'end_score',_runs);
      if d.incoming_batter_id is not null then
        _survivor := case when _striker = d.incoming_batter_id then _non_striker else _striker end;
        _ps_a := _survivor; _ps_b := d.incoming_batter_id; _ps_a_runs := 0; _ps_b_runs := 0;
        _ps_start_runs := _runs; _ps_start_legal := _legal;
      end if;
    end if;

    if d.extra_no_ball_penalty > 0 then _free_hit := true;
    elsif d.is_legal then _free_hit := false; end if;

    -- innings-end detection (priority): chase reached / all out / overs bowled
    if (_target is not null and _runs >= _target) or (_wickets >= _all_out) or (_legal >= _max_legal) then
      _ended := true;
    end if;
  end loop;

  if _legal_this_over > 0 or _over_runs <> 0 or _over_wkts <> 0 then
    _over_index := _over_index + 1;
    _per_over := _per_over || jsonb_build_object('over_number',_over_index,'runs_in_over',_over_runs,'wickets_in_over',_over_wkts);
    _worm := _worm || jsonb_build_object('over',_over_index,'cumulative_runs',_runs,'cumulative_wickets',_wickets);
  end if;

  _did_not_bat := (
    select coalesce(jsonb_agg(ms.team_member_id order by ms.batting_order nulls last), '[]'::jsonb)
    from public.match_squad ms
    where ms.match_id = _match_id and ms.team_id = _batting_team and not (_batters ? ms.team_member_id::text)
  );

  -- live rates + result
  _wkts_rem := _all_out - _wickets;
  _balls_rem := greatest(_max_legal - _legal, 0);
  if _legal > 0 then _crr := round(_runs::numeric / (_legal::numeric/_bpo), 2); else _crr := null; end if;
  _status := case when _ended then 'completed' else 'in_progress' end;
  if _target is not null then
    _runs_req := greatest(_target - _runs, 0);
    if _balls_rem > 0 then _rrr := round(_runs_req::numeric / (_balls_rem::numeric/_bpo), 2); else _rrr := null; end if;
    if _runs >= _target then
      _result := jsonb_build_object('result_type','win_by_wickets','winner_team_id',_batting_team,
        'margin_wickets',_wkts_rem,'margin_runs',null,'balls_remaining',_balls_rem);
    elsif _ended then
      if _runs = _target - 1 then _result := jsonb_build_object('result_type','tie','winner_team_id',null);
      else _result := jsonb_build_object('result_type','win_by_runs','winner_team_id',_bowling_team,
        'margin_runs',(_target - 1) - _runs,'margin_wickets',null); end if;
    else _result := null; end if;
  else _result := null; _runs_req := null; _rrr := null; end if;

  return jsonb_build_object(
    'runs', _runs, 'wickets', _wickets, 'legal_balls', _legal,
    'over', (_legal/_bpo)::text || '.' || (_legal%_bpo)::text,
    'extras', jsonb_build_object('wides',_wides,'no_balls',_nb,'byes',_byes,'leg_byes',_lb,'penalty',_pen),
    'striker_id', _striker, 'non_striker_id', _non_striker, 'free_hit_active', _free_hit,
    'batting', coalesce((select jsonb_agg(value) from jsonb_each(_batters)), '[]'::jsonb),
    'bowling', coalesce((select jsonb_agg(
        value || jsonb_build_object(
          'overs', ((value->>'legal_balls')::int/_bpo)::text || '.' || ((value->>'legal_balls')::int%_bpo)::text,
          'economy', case when (value->>'legal_balls')::int = 0 then null
                          else round((value->>'runs_conceded')::numeric / ((value->>'legal_balls')::numeric/_bpo), 2) end
        )) from jsonb_each(_bowlers)), '[]'::jsonb),
    'fall_of_wickets', _fow, 'partnerships', _partnerships,
    'current_partnership', jsonb_build_object('batter_a',_ps_a,'batter_b',_ps_b,'runs',_runs-_ps_start_runs,
        'balls',_legal-_ps_start_legal,'a_runs',_ps_a_runs,'b_runs',_ps_b_runs),
    'per_over', _per_over, 'worm', _worm,
    'did_not_bat', _did_not_bat,
    'crr', _crr, 'rrr', _rrr, 'runs_required', _runs_req,
    'balls_remaining', _balls_rem, 'wickets_remaining', _wkts_rem,
    'innings_status', _status, 'result', _result, 'orphaned_deliveries', _orphaned
  );
end; $$;
revoke all on function public.compute_innings_state(uuid) from public;
grant execute on function public.compute_innings_state(uuid) to authenticated, anon;
