create or replace function public.compute_innings_state(_innings_id uuid)
returns jsonb language plpgsql security invoker set search_path = public stable as $$
declare
  _runs int := 0; _wickets int := 0; _legal int := 0;
  _wides int := 0; _nb int := 0; _byes int := 0; _lb int := 0; _pen int := 0;
  _striker uuid; _non_striker uuid; _tmp uuid;
  _legal_this_over int := 0; _bpo int; _rr int;
  d record;
begin
  select i.opening_striker_id, i.opening_non_striker_id, coalesce(m.balls_per_over,6)
    into _striker, _non_striker, _bpo
  from public.innings i join public.matches m on m.id = i.match_id
  where i.id = _innings_id;

  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _runs := _runs + d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    if d.wicket_type is not null and d.wicket_type <> 'retired_not_out' then _wickets := _wickets + 1; end if;
    _wides := _wides + d.extra_wides; _nb := _nb + d.extra_no_ball_penalty;
    _byes := _byes + d.extra_byes; _lb := _lb + d.extra_leg_byes; _pen := _pen + d.extra_penalty;

    -- running runs that flip strike (4/6 off bat and 4 byes/leg-byes/wide-allowance are boundaries: no crossing)
    _rr := 0;
    if d.runs_off_bat not in (4,6) then _rr := _rr + d.runs_off_bat; end if;
    if d.extra_byes <> 4 then _rr := _rr + d.extra_byes; end if;
    if d.extra_leg_byes <> 4 then _rr := _rr + d.extra_leg_byes; end if;
    if d.extra_wides > 1 and (d.extra_wides - 1) <> 4 then _rr := _rr + (d.extra_wides - 1); end if;
    if (_rr % 2) = 1 then _tmp := _striker; _striker := _non_striker; _non_striker := _tmp; end if;

    if d.is_legal then
      _legal := _legal + 1;
      _legal_this_over := _legal_this_over + 1;
      if _legal_this_over = _bpo then
        _legal_this_over := 0;
        _tmp := _striker; _striker := _non_striker; _non_striker := _tmp;  -- end-of-over swap
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'runs', _runs, 'wickets', _wickets, 'legal_balls', _legal,
    'over', (_legal/6)::text || '.' || (_legal%6)::text,
    'extras', jsonb_build_object('wides',_wides,'no_balls',_nb,'byes',_byes,'leg_byes',_lb,'penalty',_pen),
    'striker_id', _striker, 'non_striker_id', _non_striker
  );
end; $$;
revoke all on function public.compute_innings_state(uuid) from public;
grant execute on function public.compute_innings_state(uuid) to authenticated, anon;
