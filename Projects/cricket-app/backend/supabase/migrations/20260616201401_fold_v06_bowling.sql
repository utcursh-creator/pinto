create or replace function public.compute_innings_state(_innings_id uuid)
returns jsonb language plpgsql security invoker set search_path = public stable as $$
declare
  _runs int := 0; _wickets int := 0; _legal int := 0;
  _wides int := 0; _nb int := 0; _byes int := 0; _lb int := 0; _pen int := 0;
  _striker uuid; _non_striker uuid; _tmp uuid; _facing uuid;
  _legal_this_over int := 0; _bpo int; _rr int; _over_bowler_runs int := 0;
  _match_id uuid; _batting_team uuid; _count_nb_faced boolean;
  _bowlers jsonb := '{}'::jsonb; _bkey text; _bcur jsonb; _dconc int;
  _batters jsonb := '{}'::jsonb; _btkey text; _btcur jsonb;
  _free_hit boolean := false; _did_not_bat jsonb;
  d record;
begin
  select i.opening_striker_id, i.opening_non_striker_id, coalesce(m.balls_per_over,6),
         i.match_id, i.batting_team_id, coalesce((m.rules->>'count_noball_as_ball_faced')::boolean, true)
    into _striker, _non_striker, _bpo, _match_id, _batting_team, _count_nb_faced
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _facing := _striker;
    _runs := _runs + d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    if d.wicket_type is not null and d.wicket_type <> 'retired_not_out' then _wickets := _wickets + 1; end if;
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
          _bcur := _bowlers -> _bkey;
          _bcur := jsonb_set(_bcur, '{maidens}', to_jsonb((_bcur->>'maidens')::int + 1));
          _bowlers := jsonb_set(_bowlers, array[_bkey], _bcur);
        end if;
        _over_bowler_runs := 0;
        _tmp := _striker; _striker := _non_striker; _non_striker := _tmp;
      end if;
    end if;

    if d.extra_no_ball_penalty > 0 then _free_hit := true;
    elsif d.is_legal then _free_hit := false;
    end if;
  end loop;

  _did_not_bat := (
    select coalesce(jsonb_agg(ms.team_member_id order by ms.batting_order nulls last), '[]'::jsonb)
    from public.match_squad ms
    where ms.match_id = _match_id and ms.team_id = _batting_team and not (_batters ? ms.team_member_id::text)
  );

  return jsonb_build_object(
    'runs', _runs, 'wickets', _wickets, 'legal_balls', _legal,
    'over', (_legal/6)::text || '.' || (_legal%6)::text,
    'extras', jsonb_build_object('wides',_wides,'no_balls',_nb,'byes',_byes,'leg_byes',_lb,'penalty',_pen),
    'striker_id', _striker, 'non_striker_id', _non_striker, 'free_hit_active', _free_hit,
    'batting', coalesce((select jsonb_agg(value) from jsonb_each(_batters)), '[]'::jsonb),
    'bowling', coalesce((select jsonb_agg(
        value || jsonb_build_object(
          'overs', ((value->>'legal_balls')::int/6)::text || '.' || ((value->>'legal_balls')::int%6)::text,
          'economy', case when (value->>'legal_balls')::int = 0 then null
                          else round((value->>'runs_conceded')::numeric / ((value->>'legal_balls')::numeric/6), 2) end
        )) from jsonb_each(_bowlers)), '[]'::jsonb),
    'did_not_bat', _did_not_bat
  );
end; $$;
revoke all on function public.compute_innings_state(uuid) from public;
grant execute on function public.compute_innings_state(uuid) to authenticated, anon;
