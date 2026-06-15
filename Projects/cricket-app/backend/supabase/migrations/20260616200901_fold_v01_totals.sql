create or replace function public.compute_innings_state(_innings_id uuid)
returns jsonb language plpgsql security invoker set search_path = public stable as $$
declare
  _runs int := 0; _wickets int := 0; _legal int := 0;
  _wides int := 0; _nb int := 0; _byes int := 0; _lb int := 0; _pen int := 0;
  d record;
begin
  for d in select * from public.deliveries where innings_id = _innings_id order by seq loop
    _runs := _runs + d.runs_off_bat + d.extra_wides + d.extra_no_ball_penalty + d.extra_byes + d.extra_leg_byes + d.extra_penalty;
    if d.is_legal then _legal := _legal + 1; end if;
    if d.wicket_type is not null and d.wicket_type <> 'retired_not_out' then _wickets := _wickets + 1; end if;
    _wides := _wides + d.extra_wides; _nb := _nb + d.extra_no_ball_penalty;
    _byes := _byes + d.extra_byes; _lb := _lb + d.extra_leg_byes; _pen := _pen + d.extra_penalty;
  end loop;
  return jsonb_build_object(
    'runs', _runs, 'wickets', _wickets, 'legal_balls', _legal,
    'over', (_legal/6)::text || '.' || (_legal%6)::text,
    'extras', jsonb_build_object('wides',_wides,'no_balls',_nb,'byes',_byes,'leg_byes',_lb,'penalty',_pen)
  );
end; $$;
revoke all on function public.compute_innings_state(uuid) from public;
grant execute on function public.compute_innings_state(uuid) to authenticated, anon;
