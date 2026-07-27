-- LOW (penetration review 2026-07-07, did_not_bat includes a dismissed batter):
-- compute_innings_state built its "did not bat" list as "everyone in the squad
-- who is not in _batters", and _batters only gains an entry when a player FACES
-- a delivery. A batter run out at the non-striker's end while backing up, or run
-- out off a wide, never faces one - so the scorecard listed a player who was
-- dismissed under "did not bat".
--
-- Recreated verbatim from the live definition with only that one expression
-- changed, so the fold stays in lockstep with compute_innings_cards and
-- restamp_innings_strike.

CREATE OR REPLACE FUNCTION public.compute_innings_state(_innings_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
  _last_seq bigint := 0;
  d record;
begin
  -- LOCKSTEP: every innings-level parameter comes from the one shared helper.
  select p.opening_striker, p.opening_non_striker, p.bpo,
         p.match_id, p.batting_team, p.bowling_team,
         p.count_nb_faced, p.target, p.max_overs, p.squad_size, p.lms,
         p.all_out, p.max_legal
    into _striker, _non_striker, _bpo, _match_id, _batting_team, _bowling_team,
         _count_nb_faced, _target, _max_overs, _squad_size, _lms,
         _all_out, _max_legal
  from public._innings_fold_params(_innings_id) p;
  _ps_a := _striker; _ps_b := _non_striker;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _last_seq := d.seq;
    if _ended then _orphaned := _orphaned || to_jsonb(d.id); continue; end if;

    -- v14: non-ball events between deliveries
    if d.event_kind = 'strike_swap' then
      _tmp := _striker; _striker := _non_striker; _non_striker := _tmp;
      continue;
    elsif d.event_kind = 'retirement' then
      _out := d.dismissed_player_id;
      if d.wicket_type <> 'retired_not_out' then
        _wickets := _wickets + 1; _over_wkts := _over_wkts + 1;
        _fow := _fow || jsonb_build_object('wicket_number', _wickets, 'score_at_fall', _runs,
          'over', (_legal/_bpo)::text || '.' || (_legal%_bpo)::text, 'dismissed_player_id', _out);
      end if;
      _partnerships := _partnerships || jsonb_build_object('wicket_number',_wickets,'batter_a',_ps_a,'batter_b',_ps_b,
        'runs',_runs-_ps_start_runs,'balls',_legal-_ps_start_legal,'a_runs',_ps_a_runs,'b_runs',_ps_b_runs,
        'start_score',_ps_start_runs,'end_score',_runs);
      if d.incoming_batter_id is not null then
        if _striker = _out then _striker := d.incoming_batter_id;
        elsif _non_striker = _out then _non_striker := d.incoming_batter_id; end if;
        _survivor := case when _striker = d.incoming_batter_id then _non_striker else _striker end;
        _ps_a := _survivor; _ps_b := d.incoming_batter_id; _ps_a_runs := 0; _ps_b_runs := 0;
        _ps_start_runs := _runs; _ps_start_legal := _legal;
      end if;
      if _wickets >= _all_out then _ended := true; end if;
      continue;
    end if;

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
    -- SCOR-3: on a run-out the batters may have crossed on the fatal (incomplete)
    -- run; that crossing is not in runs_off_bat. Apply it from the stored
    -- `crossed` flag before the dismissed batter is replaced.
    if _is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed, false) then
      _tmp := _striker; _striker := _non_striker; _non_striker := _tmp;
    end if;

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

  -- `_batters` only gains a key when someone FACES a ball, so a batter who came
  -- to the crease and was run out backing up (or off a wide) without facing one
  -- was reported as "did not bat" - on a scorecard that reads as though a
  -- dismissed player never came in. Anyone who appeared at the crease at all has
  -- batted; the card lists them as 0, out or not out (fix run 2026-07-07).
  _did_not_bat := (
    select coalesce(jsonb_agg(ms.team_member_id order by ms.batting_order nulls last), '[]'::jsonb)
    from public.match_squad ms
    where ms.match_id = _match_id and ms.team_id = _batting_team
      and not (_batters ? ms.team_member_id::text)
      -- alias `crease`, not `d`: the enclosing function already uses `d` for
      -- the delivery cursor, and a bare `d.innings_id` here is ambiguous
      and not exists (
        select 1 from public.deliveries crease
        where crease.innings_id = _innings_id
          and (crease.striker_id = ms.team_member_id
            or crease.non_striker_id = ms.team_member_id
            or crease.dismissed_player_id = ms.team_member_id
            or crease.incoming_batter_id = ms.team_member_id)
      )
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
    'innings_status', _status, 'result', _result, 'orphaned_deliveries', _orphaned,
    'last_seq', _last_seq
  );
end; $function$;

-- pg_get_functiondef does not emit the grants, so restate them: this function
-- is readable by anyone watching a public match.
revoke all on function public.compute_innings_state(uuid) from public;
grant execute on function public.compute_innings_state(uuid) to anon, authenticated;

-- LOW (penetration review 2026-07-07): insert_ball was still executable by
-- PUBLIC - i.e. by `anon`. Its own scorer gate stops an anonymous caller doing
-- damage, but a SECURITY DEFINER mutation should not be reachable at all by a
-- role that has no business calling it. edit_ball and delete_ball were already
-- revoked; this was the one that got missed.
revoke all on function public.insert_ball(uuid, bigint, uuid, int, int, int, int, int, int, public.noball_secondary_kind, public.wicket_type, uuid, uuid, uuid) from public;
grant execute on function public.insert_ball(uuid, bigint, uuid, int, int, int, int, int, int, public.noball_secondary_kind, public.wicket_type, uuid, uuid, uuid) to authenticated;
